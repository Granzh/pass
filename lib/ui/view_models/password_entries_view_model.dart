import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:pass/services/GPG_services/gpg_session_service.dart';

import '../../core/utils/enums.dart';
import '../../models/password_entry.dart';
import '../../models/password_repository_profile.dart';
import '../../services/password_repository_service.dart';

class PasswordEntriesNavigationEvent {
  final PasswordEntriesNavigation destination;
  final PasswordEntry? entryToEdit;

  PasswordEntriesNavigationEvent({required this.destination, this.entryToEdit});
}

class PasswordEntriesViewModel extends ChangeNotifier {
  final PasswordRepositoryService _passwordRepoService;
  final GPGSessionService _gpgSessionService; // <--- ДОБАВЛЕНО

  static final _log = Logger('PasswordEntriesViewModel');

  PasswordEntriesViewModel({
    required PasswordRepositoryService passwordRepoService,
    required GPGSessionService gpgSessionService, // <--- ДОБАВЛЕНО
  })  : _passwordRepoService = passwordRepoService,
        _gpgSessionService = gpgSessionService { // <--- ИНИЦИАЛИЗИРОВАНО
    _log.info("PasswordEntriesViewModel created.");
    _activeProfileSubscription =
        _passwordRepoService.activeProfileStream.listen(_onActiveProfileChanged);
    _loadInitialActiveProfile();
  }

  StreamSubscription<PasswordRepositoryProfile?>? _activeProfileSubscription;
  PasswordRepositoryProfile? _currentActiveProfile;

  List<PasswordEntry> _entries = [];
  List<PasswordEntry> get entries => _entries;

  List<PasswordEntry> _filteredEntries = [];
  List<PasswordEntry> get filteredEntries => _searchQuery.isEmpty ? _entries : _filteredEntries;

  PasswordRepositoryProfile? get currentActiveProfile => _currentActiveProfile;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool _needsGpgPassphrase = false;
  bool get needsGpgPassphrase => _needsGpgPassphrase;

  String _searchQuery = "";
  String get searchQuery => _searchQuery;

  final StreamController<PasswordEntriesNavigationEvent> _navigationController =
  StreamController.broadcast();
  Stream<PasswordEntriesNavigationEvent> get navigationEvents =>
      _navigationController.stream;

  final StreamController<String> _infoMessageController = StreamController.broadcast();
  Stream<String> get infoMessages => _infoMessageController.stream;

  void _loadInitialActiveProfile() {
    final activeProfile = _passwordRepoService.getActiveProfile();
    _onActiveProfileChanged(activeProfile);
  }

  void _onActiveProfileChanged(PasswordRepositoryProfile? activeProfile) {
    if (activeProfile == null) {
      _log.info("Active profile is null. Clearing entries and GPG session.");
      _currentActiveProfile = null;
      _entries = [];
      _filteredEntries = [];
      _isLoading = false;
      _needsGpgPassphrase = false;
      _errorMessage = "No active profile selected.";
      _gpgSessionService.clearPassphrase(reason: "Active profile became null"); // Очищаем кэш
      notifyListeners();
      return;
    }

    if (_currentActiveProfile?.id != activeProfile.id || _entries.isEmpty) {
      _log.info(
          "Active profile changed to ${activeProfile.profileName} (ID: ${activeProfile.id}). Loading entries.");
      _currentActiveProfile = activeProfile;
      // При смене профиля, если старый ID не null, очищаем кэш для старого профиля.
      // Новый loadEntries попытается взять из кэша для нового ID.
      if (_currentActiveProfile != null && _currentActiveProfile!.id != activeProfile.id) {
        _gpgSessionService.clearPassphrase(reason: "Profile changed");
      }
      loadEntries(); // Сначала попытается загрузить из кэша для нового профиля
    }
  }

  Future<void> loadEntries({String? gpgPassphrase}) async {
    if (_currentActiveProfile == null) {
      _log.warning("Attempted to load entries with no active profile.");
      _errorMessage = "Cannot load entries: No active profile.";
      _entries = [];
      _filteredEntries = [];
      _isLoading = false;
      notifyListeners();
      return;
    }

    _isLoading = true;
    _needsGpgPassphrase = false;
    _errorMessage = null;
    notifyListeners();

    String? phraseToUse = gpgPassphrase;

    if (phraseToUse == null) {
      // Пытаемся получить из кэша GpgSessionService
      phraseToUse = _gpgSessionService.getPassphrase(_currentActiveProfile!.id);
      if (phraseToUse != null) {
        _log.info("Using cached GPG passphrase for profile ${_currentActiveProfile!.id}.");
      }
    }

    if (phraseToUse == null) {
      // Если это условие все еще истинно, значит, isGpgProtected == true и пароль не в кэше и не передан
      // (Предполагаем, что профиль может иметь флаг, нужна ли ему GPG-защита.
      // Если такого флага нет, то просто всегда запрашиваем, если не в кэше)
      // Для простоты, если профиль есть, но фразы нет, будем считать, что она нужна.
      _log.info("GPG Passphrase needed for profile ${_currentActiveProfile!.id} (not cached or provided).");
      _needsGpgPassphrase = true;
      _errorMessage = "GPG passphrase required for profile '${_currentActiveProfile!.profileName}'.";
      _isLoading = false;
      notifyListeners();
      return;
    }

    try {
      final fetchedEntries = await _passwordRepoService.getAllPasswordEntries(
        profileId: _currentActiveProfile!.id,
        userGpgPassphrase: phraseToUse,
      );
      _entries = fetchedEntries;
      _applySearchFilter();
      _isLoading = false;
      _needsGpgPassphrase = false; // Успешно загрузили
      _log.info(
          "Successfully loaded ${fetchedEntries.length} entries for profile ${_currentActiveProfile!.id}.");

      // Если мы успешно использовали ЯВНО ПЕРЕДАННУЮ фразу (а не из кэша),
      // кэшируем ее.
      if (gpgPassphrase != null && gpgPassphrase == phraseToUse) {
        _gpgSessionService.setPassphrase(_currentActiveProfile!.id, gpgPassphrase);
        _log.info("Provided GPG passphrase for '${_currentActiveProfile!.id}' was valid and cached.");
      }
    } catch (e, stackTrace) {
      _log.severe(
          "Error loading entries for profile ${_currentActiveProfile!.id}: $e", e, stackTrace);
      if (e.toString().toLowerCase().contains("gpg") ||
          e.toString().toLowerCase().contains("passphrase") ||
          e.toString().toLowerCase().contains("decryption failed")) {
        _needsGpgPassphrase = true;
        _errorMessage =
        "GPG passphrase incorrect or an error occurred during decryption for profile '${_currentActiveProfile!.profileName}'.";
        _gpgSessionService.clearPassphrase(reason: "Decryption error on loadEntries"); // <--- ОЧИЩАЕМ КЭШ ПРИ ОШИБКЕ
        _log.info(
            "GPG Passphrase issue for profile ${_currentActiveProfile!.id}. Cache cleared.");
      } else {
        _errorMessage = "Failed to load entries: $e";
      }
      _entries = [];
      _filteredEntries = [];
      _isLoading = false;
    }
    notifyListeners();
  }

  void updateSearchQuery(String query) {
    _searchQuery = query;
    _applySearchFilter();
    notifyListeners();
  }

  void _applySearchFilter() {
    if (_searchQuery.isEmpty) {
      _filteredEntries = List.from(_entries);
    } else {
      final queryLower = _searchQuery.toLowerCase();
      _filteredEntries = _entries.where((entry) {
        return (entry.entryName.toLowerCase().contains(queryLower)) || // Изменил с entry.name
            (entry.username?.toLowerCase().contains(queryLower) ?? false) ||
            (entry.folderPath.toLowerCase().contains(queryLower)); // Изменил с entry.path
      }).toList();
    }
  }

  Future<void> copyToClipboard(String text, String successMessage) async {
    if (text.isEmpty) {
      _log.info("Attempted to copy empty text to clipboard.");
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    _log.info("Copied '$successMessage' to clipboard.");
    _infoMessageController.add("'$successMessage' copied to clipboard.");
  }

  Future<void> deleteEntry(PasswordEntry entry) async {
    if (_currentActiveProfile == null) return;

    // Запрашиваем пароль перед удалением, если его нет в кэше.
    // Удаление - это операция записи, требующая пароля.
    String? gpgPassphrase = _gpgSessionService.getPassphrase(_currentActiveProfile!.id);
    if (gpgPassphrase == null) {
      _log.info("GPG passphrase required for delete operation, not found in cache.");
      // Сообщаем UI, что нужен пароль. UI должен будет его запросить и вызвать deleteEntry снова с паролем.
      // Или, если это нежелательно, можно добавить параметр gpgPassphrase в deleteEntry
      // и UI будет передавать его аналогично loadEntries.
      // Для простоты пока будем считать, что UI должен обеспечить пароль, если операция его требует.
      // Но лучше, чтобы deleteEntry тоже принимал passphrase, как loadEntries.
      // **** РЕКОМЕНДАЦИЯ: Добавить параметр `String? gpgPassphrase` в `deleteEntry` ****
      // **** и чтобы UI его предоставлял, если `_gpgSessionService.getPassphrase` вернул null ****
      _needsGpgPassphrase = true;
      _errorMessage = "GPG passphrase required to delete entry '${entry.entryName}'.";
      notifyListeners();
      return;
    }


    _log.info(
        "Attempting to delete entry: ${entry.fullPath} for profile ${_currentActiveProfile!.id}");
    _isLoading = true;
    notifyListeners();
    try {
      await _passwordRepoService.deletePasswordEntry(
        profileId: _currentActiveProfile!.id,
        entryName: entry.entryName,
        folderPath: entry.folderPath,
      );
      _log.info("Entry ${entry.fullPath} deleted successfully.");
      _infoMessageController.add("Entry '${entry.entryName}' deleted.");
      // После успешного удаления перезагружаем записи.
      // loadEntries сам попробует взять из кэша.
      await loadEntries();
    } catch (e, stackTrace) {
      _log.severe("Failed to delete entry ${entry.fullPath}: $e", e, stackTrace);
      if (e.toString().toLowerCase().contains("gpg") ||
          e.toString().toLowerCase().contains("passphrase") ||
          e.toString().toLowerCase().contains("decryption failed")) {
        _errorMessage = "GPG error during delete: $e. Check passphrase.";
        _gpgSessionService.clearPassphrase(reason: "Decryption error on deleteEntry");
        _needsGpgPassphrase = true;
      } else {
        _errorMessage = "Failed to delete entry: $e";
      }
      _isLoading = false;
      notifyListeners();
    }
  }

  void navigateToAddEntry() {
    _log.info("Navigating to AddEntry screen.");
    _navigationController.add(
        PasswordEntriesNavigationEvent(destination: PasswordEntriesNavigation.toAddEntry));
  }

  void navigateToEditEntry(PasswordEntry entry) {
    _log.info("Navigating to EditEntry screen for entry: ${entry.fullPath}"); // Изменил с entry.path
    _navigationController.add(PasswordEntriesNavigationEvent(
        destination: PasswordEntriesNavigation.toEditEntry, entryToEdit: entry));
  }

  /// Явно очищает кэш парольной фразы GPG.
  void clearGpgPassphraseCache() {
    if (_currentActiveProfile != null) {
      _gpgSessionService.clearPassphrase(reason: "User requested cache clear");
      _needsGpgPassphrase = true; // Теперь точно понадобится пароль
      _errorMessage = "GPG passphrase cache cleared. Passphrase will be required.";
      _log.info(
          "User requested GPG passphrase cache clear for profile '${_currentActiveProfile!.id}'.");
      notifyListeners();
    }
  }


  @override
  void dispose() {
    _log.info("PasswordEntriesViewModel disposed.");
    _activeProfileSubscription?.cancel();
    _navigationController.close();
    _infoMessageController.close();
    super.dispose();
  }
}