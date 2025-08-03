
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import '../../core/utils/enums.dart';
import '../../core/utils/password_generator.dart';
import '../../models/password_entry.dart';
import '../../services/GPG_services/gpg_session_service.dart';
import '../../services/password_repository_service.dart';

class AddEditPasswordEntryViewModel extends ChangeNotifier {
  final PasswordRepositoryService _passwordRepoService;
  final GPGSessionService _gpgSessionService; // <--- ДОБАВЛЕНО
  final String _profileId;
  final PasswordEntry? _initialEntry;

  static final _log = Logger('AddEditPasswordEntryViewModel');

  AddEditPasswordEntryViewModel({
    required PasswordRepositoryService passwordRepoService,
    required GPGSessionService gpgSessionService, // <--- ДОБАВЛЕНО
    required String profileId,
    PasswordEntry? entryToEdit,
  })  : _passwordRepoService = passwordRepoService,
        _gpgSessionService = gpgSessionService, // <--- ИНИЦИАЛИЗИРОВАНО
        _profileId = profileId,
        _initialEntry = entryToEdit {
    _log.info(
        "AddEditPasswordEntryViewModel created for profileId: $_profileId. Editing: ${entryToEdit != null}");
    if (entryToEdit != null) {
      entryName = entryToEdit.entryName;
      folderPath = entryToEdit.folderPath;
      password = entryToEdit.password;
      _metadata = Map.from(entryToEdit.metadata);
      url = entryToEdit.url; // Предполагая, что PasswordEntry имеет эти поля напрямую
      username = entryToEdit.username; // или вы их извлекаете из метаданных, как раньше
      notes = _extractCombinedNotes(entryToEdit.metadata);
      _metadata.removeWhere((key, _) =>
      ['url', 'URL', 'username', 'user', 'login', 'notes', 'comment']
          .contains(key.toLowerCase()) || // Сделал toLowerCase для надежности
          key.startsWith('line_'));
    } else {
      // password = generateSecurePassword(); // Можно генерировать сразу, если нужно
    }
  }

  String entryName = '';
  String folderPath = '';
  String password = '';
  String? url;
  String? username;
  String? notes;
  Map<String, String> _metadata = {};

  Map<String, String> get customMetadata => Map.unmodifiable(_metadata); // Неизменяемая копия для безопасности

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  final StreamController<AddEditEntryNavigation> _navigationController =
  StreamController.broadcast();
  Stream<AddEditEntryNavigation> get navigationEvents =>
      _navigationController.stream;

  String? validateEntryName(String? value) {
    if (value == null || value.isEmpty) {
      return 'Entry name cannot be empty.';
    }
    if (value.contains('/')) {
      return 'Entry name cannot contain "/" characters. Use the folder path field.';
    }
    return null;
  }

  String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password cannot be empty.';
    }
    return null;
  }

  String? validateUrl(String? value) {
    if (value != null && value.isNotEmpty) {
      final uri = Uri.tryParse(value);
      if (uri == null || !uri.hasAbsolutePath || !uri.hasScheme) { // Проверка схемы и абсолютного пути
        return 'Invalid URL format (e.g., http://example.com).';
      }
    }
    return null;
  }

  String _extractCombinedNotes(Map<String, String> metadataMap) {
    List<String> notesParts = [];
    if (metadataMap['notes'] != null) notesParts.add(metadataMap['notes']!);
    if (metadataMap['comment'] != null && metadataMap['notes'] == null) {
      notesParts.add(metadataMap['comment']!);
    }
    metadataMap.forEach((key, value) {
      if (key.startsWith('line_')) {
        notesParts.add(value);
      }
    });
    return notesParts.join('\n');
  }

  void updateEntryName(String value) {
    entryName = value;
    notifyListeners();
  }

  void updateFolderPath(String value) {
    folderPath = value.trim();
    if (folderPath.startsWith('/')) folderPath = folderPath.substring(1);
    if (folderPath.endsWith('/')) folderPath = folderPath.substring(0, folderPath.length - 1);
    notifyListeners();
  }

  void updatePassword(String value) {
    password = value;
    notifyListeners();
  }

  void updateUrl(String? value) {
    url = value?.trim();
    notifyListeners();
  }

  void updateUsername(String? value) {
    username = value?.trim();
    notifyListeners();
  }

  void updateNotes(String? value) {
    notes = value; // trim() может быть нежелателен для многострочных заметок
    notifyListeners();
  }

  void addCustomMetadataField(String key, String value) {
    if (key.isNotEmpty) {
      _metadata[key.trim()] = value.trim();
      notifyListeners();
    }
  }

  void removeCustomMetadataField(String key) {
    _metadata.remove(key);
    notifyListeners();
  }

  void generateNewPassword({
    int length = 16, // Эти значения могут приходить из настроек пользователя
    bool includeUppercase = true,
    bool includeLowercase = true,
    bool includeNumbers = true,
    bool includeSymbols = true,
  }) {
    password = generateSecurePassword( // Убедитесь, что generateSecurePassword импортирована
      length: length,
      includeUppercase: includeUppercase,
      includeLowercase: includeLowercase,
      includeNumbers: includeNumbers,
      includeSymbols: includeSymbols,
    );
    _log.fine("New password generated.");
    notifyListeners();
  }

  Future<void> saveEntry({required String userGpgPassphrase}) async {
    _log.info("Attempting to save entry '$entryName' for profile '$_profileId'.");
    _errorMessage = null;

    if (validateEntryName(entryName) != null ||
        validatePassword(password) != null ||
        validateUrl(url) != null) {
      _errorMessage = "Please correct the errors in the form.";
      _log.warning("Validation failed: $_errorMessage");
      notifyListeners();
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      final Map<String, String> finalMetadata = Map.from(_metadata);
      if (url != null && url!.isNotEmpty) finalMetadata['url'] = url!;
      if (username != null && username!.isNotEmpty) finalMetadata['username'] = username!;
      if (notes != null && notes!.isNotEmpty) {
        // Если вы храните notes в 'notes' или 'comment', убедитесь, что это согласовано
        finalMetadata['notes'] = notes!;
      }

      PasswordEntry entryToSave;
      if (_initialEntry != null) {
        entryToSave = _initialEntry.copyWith(
          entryName: entryName.trim(),
          folderPath: folderPath.trim(),
          password: password, // Пароль не шифруется здесь, это делает репозиторий
          metadata: finalMetadata,
          // lastModified можно обновить в репозитории или оставить как есть
        );
      } else {
        entryToSave = PasswordEntry(
          entryName: entryName.trim(),
          folderPath: folderPath.trim(),
          password: password,
          metadata: finalMetadata,
          lastModified: DateTime.now().toUtc(), // Используйте UTC для консистентности
        );
      }

      await _passwordRepoService.savePasswordEntry(
        profileId: _profileId,
        entry: entryToSave,
        userGpgPassphrase: userGpgPassphrase,
      );

      // Если сохранение успешно, значит парольная фраза верна. Кэшируем ее.
      _gpgSessionService.setPassphrase(_profileId, userGpgPassphrase); // <--- КЭШИРУЕМ
      _log.info(
          "Entry '${entryToSave.fullPath}' saved successfully for profile '$_profileId'. Passphrase cached.");

      _navigationController.add(AddEditEntryNavigation.backToList);
    } catch (e, stackTrace) {
      _log.severe("Error saving entry '$_profileId/${entryName.trim()}': $e", e, stackTrace);
      _errorMessage = "Failed to save entry: $e";
      if (e.toString().toLowerCase().contains("gpg") ||
          e.toString().toLowerCase().contains("passphrase") ||
          e.toString().toLowerCase().contains("decryption failed")) { // Добавил decryption failed
        _errorMessage = "GPG error during save: ${e.toString().split(':').last.trim()}. Check passphrase or GPG setup.";
        _gpgSessionService.clearPassphrase(reason: "Encryption/save error"); // <--- ОЧИЩАЕМ КЭШ ПРИ ОШИБКЕ
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  /// Очищает сообщение об ошибке. Вызывать из UI после его отображения.
  void clearErrorMessage() {
    _errorMessage = null;
    notifyListeners();
  }


  @override
  void dispose() {
    _log.info("AddEditPasswordEntryViewModel for profile '$_profileId' disposed.");
    _navigationController.close();
    super.dispose();
  }
}