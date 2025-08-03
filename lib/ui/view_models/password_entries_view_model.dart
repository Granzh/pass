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
  final GPGSessionService _gpgSessionService;

  static final _log = Logger('PasswordEntriesViewModel');

  PasswordEntriesViewModel({
    required PasswordRepositoryService passwordRepoService,
    required GPGSessionService gpgSessionService,
  })  : _passwordRepoService = passwordRepoService,
        _gpgSessionService = gpgSessionService {
    _log.info("PasswordEntriesViewModel created.");
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
      phraseToUse = _gpgSessionService.getPassphrase(_currentActiveProfile!.id);
      if (phraseToUse != null) {
        _log.info("Using cached GPG passphrase for profile ${_currentActiveProfile!.id}.");
      }
    }

    if (phraseToUse == null) {
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
      _needsGpgPassphrase = false;
      _log.info(
          "Successfully loaded ${fetchedEntries.length} entries for profile ${_currentActiveProfile!.id}.");

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
        _gpgSessionService.clearPassphrase(reason: "Decryption error on loadEntries");
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
        return (entry.entryName.toLowerCase().contains(queryLower)) ||
            (entry.username?.toLowerCase().contains(queryLower) ?? false) ||
            (entry.folderPath.toLowerCase().contains(queryLower));
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

    String? gpgPassphrase = _gpgSessionService.getPassphrase(_currentActiveProfile!.id);
    if (gpgPassphrase == null) {
      _log.info("GPG passphrase required for delete operation, not found in cache.");
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
    _log.info("Navigating to EditEntry screen for entry: ${entry.fullPath}");
    _navigationController.add(PasswordEntriesNavigationEvent(
        destination: PasswordEntriesNavigation.toEditEntry, entryToEdit: entry));
  }

  void clearGpgPassphraseCache() {
    if (_currentActiveProfile != null) {
      _gpgSessionService.clearPassphrase(reason: "User requested cache clear");
      _needsGpgPassphrase = true;
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