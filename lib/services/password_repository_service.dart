import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as path_utils;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/password_entry.dart';
import '../models/password_repository_profile.dart';
import '../core/utils/secure_storage.dart';
import '../models/git_repository_model.dart';
import 'gpg_key_service.dart';
import 'git_service.dart';

class PasswordRepositoryService {
  static final PasswordRepositoryService _instance = PasswordRepositoryService._internal();
  factory PasswordRepositoryService() => _instance;

  late FlutterSecureStorage _secureStorage;
  late GPGService _gpgService;
  late GitService _gitService;
  static const String _profilesKey = 'password_repository_profiles';
  List<PasswordRepositoryProfile> _profiles = [];

  // Current active profile
  String? _activeProfileId;

  // Stream controller for profile changes
  final StreamController<List<PasswordRepositoryProfile>> _profilesController =
  StreamController<List<PasswordRepositoryProfile>>.broadcast();

  // Stream of profiles
  Stream<List<PasswordRepositoryProfile>> get profilesStream => _profilesController.stream;

  // Private constructor
  PasswordRepositoryService._internal() {
    _secureStorage = secureStorage;
    _gpgService = GPGService();
    _gitService = GitService();
    _loadProfiles();
  }

  /// Returns true if there is an active profile selected and it exists in the profiles list
  bool hasActiveProfile() {
    if (_activeProfileId == null) return false;
    return _profiles.any((profile) => profile.id == _activeProfileId);
  }

  // Test constructor for dependency injection
  PasswordRepositoryService.test({
    required FlutterSecureStorage secureStorage,
    required GPGService gpgService,
    required GitService gitService,
  }) {
    _secureStorage = secureStorage;
    _gpgService = gpgService;
    _gitService = gitService;
    _loadProfiles();
  }


  // Load all profiles from secure storage
  Future<void> _loadProfiles() async {
    try {
      final profilesJson = await _secureStorage.read(key: _profilesKey);
      if (profilesJson != null) {
        final List<dynamic> profilesList = jsonDecode(profilesJson);
        _profiles = profilesList
            .map((e) => PasswordRepositoryProfile.fromJson(e as Map<String, dynamic>))
            .toList();
        _profilesController.add(List.unmodifiable(_profiles));
      }

      // Load active profile
      _activeProfileId = await _secureStorage.read(key: 'active_profile_id');
      
      // Validate that the active profile exists in the profiles list
      if (_activeProfileId != null && !_profiles.any((p) => p.id == _activeProfileId)) {
        // Clear the active profile if it doesn't exist in the profiles list
        _activeProfileId = null;
        await _secureStorage.delete(key: 'active_profile_id');
      }
    } catch (e) {
      print('Error loading profiles: $e');
      rethrow;
    }
  }

  // Save all profiles to secure storage
  Future<void> _saveProfiles() async {
    try {
      final profilesJson = jsonEncode(_profiles.map((p) => p.toJson()).toList());
      await _secureStorage.write(key: _profilesKey, value: profilesJson);
      _profilesController.add(List.unmodifiable(_profiles));
    } catch (e) {
      print('Error saving profiles: $e');
      rethrow;
    }
  }

  // Get all profiles
  List<PasswordRepositoryProfile> getProfiles() {
    return List.unmodifiable(_profiles);
  }

  // Get active profile
  PasswordRepositoryProfile? getActiveProfile() {
    if (_activeProfileId == null) return null;
    try {
      return _profiles.firstWhere(
            (profile) => profile.id == _activeProfileId,
      );
    } catch (e) {
      // If profile not found, clear the active profile ID
      _activeProfileId = null;
      _secureStorage.delete(key: 'active_profile_id');
      return null;
    }
  }

  // Set active profile
  Future<void> setActiveProfile(String profileId) async {
    if (!_profiles.any((p) => p.id == profileId)) {
      throw Exception('Profile not found');
    }
    _activeProfileId = profileId;
    await _secureStorage.write(key: 'active_profile_id', value: profileId);
  }

  // Add a new repository profile
  Future<PasswordRepositoryProfile> addRepository({
    String? id,
    required String profileName, // Был 'name'
    required PasswordSourceType type,
    String? gitProviderName,
    // String? repositoryId, // Можно извлечь из gitRepositoryInfo
    // required String repositoryFullName, // Можно извлечь из gitRepositoryInfo
    GitRepository? gitRepositoryInfo, // Используем модель
    String? localFolderPath, // Для PasswordSourceType.localFolder
    String? defaultBranch, // Можно извлечь из gitRepositoryInfo
    Map<String, String>? authTokens,
    // GPG Key Options - НУЖНО ДОБАВИТЬ ЭТИ ПАРАМЕТРЫ В ВЫЗОВ МЕТОДА
    required String gpgUserPassphrase, // Парольная фраза для доступа к профилю и для нового ключа
    bool generateNewGpgKey = true, // Флаг для генерации нового ключа
    String? email,
    String? gpgExistingPrivateKeyArmored,
    String? gpgPassphraseForExistingKey, // Парольная фраза самого ИМПОРТИРУЕМОГО ключа
    String? gpgExistingPublicKeyArmored,
  }) async {
    final profileId = id ?? const Uuid().v4();

    // 1. GPG Key Setup (ПЕРЕД СОЗДАНИЕМ ДИРЕКТОРИИ И КЛОНИРОВАНИЕМ)
    if (generateNewGpgKey) {
      await _gpgService.generateNewKeyForProfile(
        profileId: profileId,
        passphrase: gpgUserPassphrase,
        userName: profileName,
        userEmail: email, // userEmail is optional
      );
    } else if (gpgExistingPrivateKeyArmored != null && gpgPassphraseForExistingKey != null) {
      await _gpgService.importPrivateKeyForProfile(
        profileId: profileId,
        privateKeyArmored: gpgExistingPrivateKeyArmored,
        passphraseForImportedKey: gpgPassphraseForExistingKey,
        publicKeyArmored: gpgExistingPublicKeyArmored,
      );
    } else {
      // Не указаны ни генерация, ни импорт - это ошибка конфигурации
      throw Exception("GPG key configuration is missing for new profile.");
    }

    // 2. Auth Tokens (как у вас)
    // ... ваш код для сохранения токенов ...
    // Убедитесь, что accessTokenKey и refreshTokenKey генерируются правильно
    // String accessTokenStorageKey = PasswordRepositoryProfile.generateAccessTokenKey(profileId);
    // String refreshTokenStorageKey = PasswordRepositoryProfile.generateRefreshTokenKey(profileId);


    // 3. Ensure repository directory exists and clone if necessary
    final repoPath = await getRepositoryPath(profileId);
    final repoDir = Directory(repoPath);

    if (type == PasswordSourceType.localFolder) {
      if (!await repoDir.exists()) {
        await repoDir.create(recursive: true);
      }
    } else if (type == PasswordSourceType.github || type == PasswordSourceType.gitlab) {
      if (gitRepositoryInfo == null) {
        throw ArgumentError('gitRepositoryInfo is required for Git-based profile types.');
      }
      if (!await repoDir.exists()) {
        await _gitService.cloneRepository(gitRepositoryInfo, profileId); // profileId нужен для пути и токенов
      } else {
        throw Exception("Repository directory for profile $profileId already exists. Skipping clone.");
      }
    }
    // TODO: Обработка других типов репозиториев (например, SSH)


    final profile = PasswordRepositoryProfile(
      id: profileId,
      profileName: profileName,
      type: type,
      gitProviderName: gitProviderName,
      repositoryId: gitRepositoryInfo?.id, // Используем из gitRepositoryInfo
      repositoryFullName: (type == PasswordSourceType.localFolder)
          ? localFolderPath ?? repoPath
          : gitRepositoryInfo!.name, // name из GitRepository это обычно full_name
      defaultBranch: gitRepositoryInfo?.defaultBranch,
      // accessTokenKey и refreshTokenKey больше не нужны в модели PasswordRepositoryProfile,
      // если вы используете статические методы для генерации ключей к secureStorage.
      // Если они есть в модели, то здесь их нужно корректно устанавливать.
      // accessTokenKey: authTokens != null ? accessTokenStorageKey : null,
      // refreshTokenKey: authTokens != null ? refreshTokenStorageKey : null,
    );

    _profiles.add(profile);
    await _saveProfiles();

    if (getActiveProfile() == null && _profiles.isNotEmpty) {
      await setActiveProfile(profile.id);
    }

    return profile;
  }


  Future<List<PasswordEntry>> getAllPasswordEntries({
    required String profileId,
    required String userGpgPassphrase,
  }) async {
    // ... (код из предыдущего ответа, который сканирует директорию,
    //      дешифрует .gpg файлы и создает PasswordEntry)


    if (!_profiles.any((p) => p.id == profileId)) {
      throw Exception('Profile not found for getting passwords');
    }

    final repoPath = await getRepositoryPath(profileId);
    final rootDir = Directory(repoPath);

    if (!await rootDir.exists()) {
      print('Repository directory not found for profile $profileId: $repoPath');
      return [];
    }

    final List<PasswordEntry> entries = [];
    // Используем path_utils для корректной работы с путями
    final List<FileSystemEntity> files = await rootDir.list(recursive: true, followLinks: false).toList();

    for (final entity in files) {
      if (entity is File && entity.path.endsWith('.gpg')) {
        final relativePath = path_utils.relative(entity.path, from: repoPath);
        final entryNameWithExt = path_utils.basename(relativePath);
        final entryName = entryNameWithExt.substring(0, entryNameWithExt.length - '.gpg'.length);
        String folderPath = path_utils.dirname(relativePath);
        if (folderPath == '.' || folderPath == repoPath) folderPath = ''; // Корень

        try {
          final encryptedContent = await entity.readAsString();
          final decryptedContent = await _gpgService.decryptDataForProfile(
            encryptedContent,
            profileId,
            userGpgPassphrase,
          );
          final fileStat = await entity.stat();

          entries.add(PasswordEntry.fromPassFileContent(
            decryptedContent,
            entryName,
            folderPath,
            fileStat.modified,
          ));
        } catch (e) {
          print('Failed to decrypt or parse ${entity.path} for profile $profileId: $e. Skipping file.');
          if (e.toString().contains('Incorrect GPG passphrase')) {
            throw Exception('Incorrect GPG passphrase. Cannot list all passwords.');
          }
          // Можно добавить "поврежденную" запись или просто пропустить
        }
      }
    }
    entries.sort((a, b) => a.fullPath.compareTo(b.fullPath));
    return entries;
  }

  Future<void> deletePasswordEntry({
    required String profileId,
    required String entryName,
    String folderPath = '',
    // userGpgPassphrase здесь может быть не нужна для самого удаления файла,
    // но может понадобиться, если git push требует аутентификации или подписи,
    // или если сообщение коммита генерируется на основе содержимого (что здесь не так).
    // required String userGpgPassphrase,
  }) async {
    final profile = _profiles.firstWhere((p) => p.id == profileId,
        orElse: () => throw Exception('Profile not found for deleting password'));

    final repoPath = await getRepositoryPath(profileId);
    final fullEntryPathForDisplay = folderPath.isEmpty ? entryName : path_utils.join(folderPath, entryName);
    final passwordFilePath = path_utils.join(repoPath, folderPath, '$entryName.gpg');
    final passwordFile = File(passwordFilePath);

    if (!await passwordFile.exists()) {
      print('Password file to delete not found: $passwordFilePath');
      return;
    }

    await passwordFile.delete();
    print('Deleted password entry: $passwordFilePath');

    // Если это Git репозиторий, коммитим и пушим изменения
    if (profile.type != PasswordSourceType.localFolder) {
      try {
        await _gitService.pushChanges(
          repoPath,
          'Remove password: $fullEntryPathForDisplay',
        );
      } catch (e) {
        print("Error pushing changes after deleting password $fullEntryPathForDisplay: $e");
        throw Exception('Password deleted locally, but failed to push to remote: $e');
      }
    }
  }
  // Update an existing repository profile
  // В PasswordRepositoryService
  Future<PasswordRepositoryProfile> updateRepository({
    required String profileId,
    String? newProfileName,
    PasswordSourceType? newType,
    String? newRepositoryFullName,
    String? newGitProviderName,
    // String? newRepositoryId, // Обычно не меняется пользователем напрямую, а получается от сервиса
    String? newLocalPath,    // Если вы его добавили в модель
    String? newDefaultBranch,
    Map<String, String>? newAuthTokens,
    bool shouldRegenerateGpgKey = false,
    String? newGpgUserName,
    String? newGpgUserEmail,
    String? newGpgPassphrase,
  }) async {
    final index = _profiles.indexWhere((p) => p.id == profileId);
    if (index == -1) {
      throw Exception('Repository profile not found for update');
    }

    PasswordRepositoryProfile originalProfile = _profiles[index];

    // --- Переменные для хранения новых значений ---
    // Начинаем со значений из originalProfile
    String currentProfileName = newProfileName ?? originalProfile.profileName;
    PasswordSourceType currentType = originalProfile.type;
    String currentRepositoryFullName = originalProfile.repositoryFullName;
    String? currentGitProviderName = originalProfile.gitProviderName;
    String? currentRepositoryId = originalProfile.repositoryId;
    String? currentLocalPath = originalProfile.localPath; // Если есть в модели
    String? currentDefaultBranch = originalProfile.defaultBranch;
    String? currentAccessTokenKey = originalProfile.accessTokenKey;
    String? currentRefreshTokenKey = originalProfile.refreshTokenKey;


    // --- 1. Обработка изменения типа (если newType предоставлен и отличается) ---
    if (newType != null && newType != originalProfile.type) {
      print('Changing profile type from ${originalProfile.type} to $newType for profile $profileId');
      final repoPath = await getRepositoryPath(profileId); // Путь не меняется, т.к. привязан к profileId
      final repoDir = Directory(repoPath);

      if (await repoDir.exists()) {
        print('Deleting existing repository directory: $repoPath for type change.');
        await repoDir.delete(recursive: true);
      }
      await repoDir.create(recursive: true);
      print('Recreated repository directory: $repoPath');

      currentType = newType; // Обновляем тип

      if (newType == PasswordSourceType.localFolder) {
        // Для LocalFolder, repositoryFullName это путь.
        // Если newRepositoryFullName не предоставлен UI специально для LocalFolder,
        // то он должен быть равен repoPath.
        currentRepositoryFullName = newRepositoryFullName ?? repoPath;
        currentGitProviderName = null;
        currentRepositoryId = null;
        currentDefaultBranch = null;
        currentLocalPath = null; // localPath нерелевантен или дублирует repositoryFullName для localFolder
        // Очистить токены
        if (currentAccessTokenKey != null) await _secureStorage.delete(key: currentAccessTokenKey);
        if (currentRefreshTokenKey != null) await _secureStorage.delete(key: currentRefreshTokenKey);
        currentAccessTokenKey = null;
        currentRefreshTokenKey = null;

      } else if (newType == PasswordSourceType.github || newType == PasswordSourceType.gitlab) {
        if (newRepositoryFullName == null || newRepositoryFullName.isEmpty) {
          throw ArgumentError('New repository URL (newRepositoryFullName) is required when changing type to Git.');
        }
        if (newGitProviderName == null || newGitProviderName.isEmpty) {
          throw ArgumentError('New Git provider name is required when changing type to Git.');
        }

        currentRepositoryFullName = newRepositoryFullName; // Это URL
        currentGitProviderName = newGitProviderName;
        currentDefaultBranch = newDefaultBranch ?? 'main'; // Или взять из originalProfile, если не указан новый
        currentLocalPath = newLocalPath ?? originalProfile.localPath; // Сохраняем, если был, или используем новый
        // или null, если всегда используется путь по умолчанию

        final newRepoInfo = GitRepository(
            id: '', name: currentRepositoryFullName, htmlUrl: currentRepositoryFullName,
            description: '', isPrivate: true, defaultBranch: currentDefaultBranch
        );
        print('Cloning new Git repository from ${newRepoInfo.htmlUrl} into $repoPath');
        await _gitService.cloneRepository(newRepoInfo, profileId);
        // Токены будут обработаны ниже
      }
    } else {
      // Тип не менялся, но другие поля могли измениться
      if (newRepositoryFullName != null) currentRepositoryFullName = newRepositoryFullName;
      if (newGitProviderName != null) currentGitProviderName = newGitProviderName;
      if (newDefaultBranch != null) currentDefaultBranch = newDefaultBranch;
      if (newLocalPath != null) currentLocalPath = newLocalPath; // Если есть в модели
      // Если тип не менялся, но URL Git-репозитория изменился, нужно переклонировать
      if (originalProfile.type != PasswordSourceType.localFolder &&
          newRepositoryFullName != null && newRepositoryFullName != originalProfile.repositoryFullName) {
        print('Repository URL changed. Re-cloning for profile $profileId...');
        final repoPath = await getRepositoryPath(profileId);
        final repoDir = Directory(repoPath);
        if (await repoDir.exists()) await repoDir.delete(recursive: true);
        await repoDir.create(recursive: true);

        final changedRepoInfo = GitRepository(
            id: currentRepositoryId ?? '', name: currentRepositoryFullName, htmlUrl: currentRepositoryFullName,
            description: '', isPrivate: true, defaultBranch: currentDefaultBranch!
        );
        await _gitService.cloneRepository(changedRepoInfo, profileId);
      }
    }

    // --- 2. Обновление токенов (если переданы) ---
    if (newAuthTokens != null && (currentType == PasswordSourceType.github || currentType == PasswordSourceType.gitlab)) {
      String accessTokenStorageKey = currentAccessTokenKey ?? PasswordRepositoryProfile.generateAccessTokenKey(profileId);
      String refreshTokenStorageKey = currentRefreshTokenKey ?? PasswordRepositoryProfile.generateRefreshTokenKey(profileId);

      await _secureStorage.write(key: accessTokenStorageKey, value: newAuthTokens['access_token']);
      currentAccessTokenKey = accessTokenStorageKey; // Обновляем ключ для нового экземпляра Profile

      if (newAuthTokens['refresh_token'] != null) {
        await _secureStorage.write(key: refreshTokenStorageKey, value: newAuthTokens['refresh_token']);
        currentRefreshTokenKey = refreshTokenStorageKey;
      } else {
        await _secureStorage.delete(key: refreshTokenStorageKey);
        currentRefreshTokenKey = null;
      }
    }

    // --- 3. Перегенерация GPG ключа (если требуется) ---
    if (shouldRegenerateGpgKey) {
      if (newGpgUserName == null || newGpgUserEmail == null || newGpgPassphrase == null) {
        throw ArgumentError('User name, email, and passphrase are required to regenerate GPG key.');
      }
      // ... (удаление старого ключа) ...
      try {
        if (await _gpgService.hasKeyForProfileById(profileId)) {
          await _gpgService.deleteKeyForProfileById(profileId);
        }
      } catch (e) { print('Warning: Could not delete old GPG key for profile $profileId: $e');}

      await _gpgService.generateNewKeyForProfile(
        profileId: profileId,
        userName: newGpgUserName, // Или currentProfileName, если newGpgUserName не предоставлен
        userEmail: newGpgUserEmail,
        passphrase: newGpgPassphrase,
      );
    }

    // --- 4. Создание нового экземпляра PasswordRepositoryProfile ---
    // Так как почти все поля final, мы должны создать новый объект.
    final updatedProfile = PasswordRepositoryProfile(
      id: originalProfile.id, // ID не меняется
      profileName: currentProfileName, // Это единственное поле, которое могло быть не final
      type: currentType,
      gitProviderName: currentGitProviderName,
      repositoryId: currentRepositoryId, // Мы его не меняли в этой логике явно
      repositoryFullName: currentRepositoryFullName,
      localPath: currentLocalPath, // Если есть в модели
      defaultBranch: currentDefaultBranch,
      createdAt: originalProfile.createdAt, // Дата создания не меняется
      accessTokenKey: currentAccessTokenKey,
      refreshTokenKey: currentRefreshTokenKey,
    );

    _profiles[index] = updatedProfile;
    await _saveProfiles();

    return updatedProfile;
  }

  // Remove a repository profile
  Future<void> removeRepository(String id) async {
    final index = _profiles.indexWhere((p) => p.id == id);
    if (index == -1) return;

    final profile = _profiles[index];

    // Clean up secure storage
    await Future.wait([
      if (profile.accessTokenKey != null)
        _secureStorage.delete(key: profile.accessTokenKey!),
      if (profile.refreshTokenKey != null)
        _secureStorage.delete(key: profile.refreshTokenKey!),
    ]);

    // Remove GPG keys if they exist
    try {
      final gpgKey = await _gpgService.getKeyForProfileById(id);
      if (gpgKey != null) {
        await _gpgService.deleteKeyForProfileById(id);
      }
    } catch (e) {
      throw Exception('Error removing GPG keys: $e');
    }

    // Remove from profiles
    _profiles.removeAt(index);
    await _saveProfiles();

    // If active profile was removed, set a new active profile if available
    if (_activeProfileId == id) {
      _activeProfileId = _profiles.isNotEmpty ? _profiles.first.id : null;
      if (_activeProfileId != null) {
        await _secureStorage.write(key: 'active_profile_id', value: _activeProfileId);
      } else {
        await _secureStorage.delete(key: 'active_profile_id');
      }
    }
  }

  // Get repository directory path
  Future<String> getRepositoryPath(String profileId) async {
    final appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}/repositories/$profileId';
  }

  // Clone or update repository
  Future<void> syncRepository(String profileId, String userGpgPassphrase) async { // Добавлен userGpgPassphrase
    final profile = _profiles.firstWhere((p) => p.id == profileId,
        orElse: () => throw Exception('Profile not found for sync'));

    final repoPath = await getRepositoryPath(profileId);
    final dir = Directory(repoPath);

    if (profile.type == PasswordSourceType.localFolder) {
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return; // Для локальной папки просто убеждаемся, что она есть
    }

    // Для Git репозиториев
    if (!await dir.exists()) {
      // Если директории нет, клонируем
      if (profile.repositoryFullName.isEmpty) { // Должен быть repositoryFullName для Git
        throw Exception('Repository full name is missing for Git profile sync.');
      }
      // Предполагаем, что gitRepositoryInfo можно восстановить или оно не нужно для простого pull/clone
      // Для клонирования нужен URL, который формируется из repositoryFullName и gitProviderName
      // Это упрощение, в идеале, вы должны хранить GitRepository модель в профиле.
      final repoInfoForClone = GitRepository( // Заглушка, если нет полной информации
          id: profile.repositoryId ?? '',
          name: profile.repositoryFullName,
          htmlUrl: _buildGitRepoUrl(profile), // Нужен метод для построения URL
          description: '',
          isPrivate: true, // Предположение
          defaultBranch: profile.defaultBranch ?? 'main');
      await _gitService.cloneRepository(repoInfoForClone, profileId);
    } else {
      // Директория есть, делаем pull
      try {
        await _gitService.pullChanges(repoPath);
      } catch (e) {
        // Можно попытаться разблокировать, если это частая проблема
        // await _gitService.cleanupLockFiles(repoPath);
        // await _gitService.pullChanges(repoPath); // Повторная попытка
        throw Exception('Error pulling changes for $profileId: $e. Repository might be locked or network issue.');
      }
    }
  }

  String _buildGitRepoUrl(PasswordRepositoryProfile profile) {
    if (profile.gitProviderName?.toLowerCase() == 'github') {
      return 'https://github.com/${profile.repositoryFullName}.git';
    } else if (profile.gitProviderName?.toLowerCase() == 'gitlab') {
      // GitLab URL может отличаться, если используется собственный хостинг
      return 'https://gitlab.com/${profile.repositoryFullName}.git';
    }
    // Для других типов или если нет providerName, вернуть пустую строку или кинуть ошибку
    return '';
  }
  // This is the userId parameter

  // Get repository status (behind/ahead/up-to-date)
  Future<Map<String, dynamic>> getRepositoryStatus(String profileId) async {
    final profile = _profiles.firstWhere(
          (p) => p.id == profileId,
      orElse: () => throw Exception('Profile not found'),
    );

    if (profile.type == PasswordSourceType.localFolder) {
      return {'status': 'local'};
    }

    final repoPath = await getRepositoryPath(profileId);
    try {
      return await _gitService.getRepoStatus(repoPath);
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  // Encrypt and save a password
  Future<void> savePasswordEntry({
    required String profileId,
    required PasswordEntry entry,
    required String userGpgPassphrase, // Парольная фраза пользователя для доступа к профилю
  }) async {
    final profile = _profiles.firstWhere((p) => p.id == profileId,
        orElse: () => throw Exception('Profile not found for saving password'));

    final repoPath = await getRepositoryPath(profileId);
    // Формируем полный путь к файлу пароля, включая подпапки
    final passwordFilePath = path_utils.join(repoPath, entry.folderPath, '${entry.entryName}.gpg');
    final passwordFile = File(passwordFilePath);

    // Убеждаемся, что директория для файла существует
    if (!await passwordFile.parent.exists()) {
      await passwordFile.parent.create(recursive: true);
    }

    final fileContent = entry.toPassFileContent();
    final encryptedContent = await _gpgService.encryptDataForProfile(fileContent, profileId); // Шифруем для профиля

    await passwordFile.writeAsString(encryptedContent);

    // Если это Git репозиторий, коммитим и пушим изменения
    if (profile.type != PasswordSourceType.localFolder) {
      try {
        await _gitService.pushChanges(
          repoPath,
          'Update password: ${entry.fullPath}', // Сообщение коммита
        );
      } catch (e) {
        // Ошибка не критична для локального сохранения, но пользователь должен знать
        // Можно добавить флаг "требуется синхронизация" для профиля
        throw Exception('Password saved locally, but failed to push to remote: $e');
      }
    }
  }

  /// Получает одну запись пароля.
  Future<PasswordEntry?> getPasswordEntry({
    required String profileId,
    required String entryName, // Имя файла без .gpg
    String folderPath = '', // Путь к папке
    required String userGpgPassphrase,
  }) async {
    final repoPath = await getRepositoryPath(profileId);
    final passwordFilePath = path_utils.join(repoPath, folderPath, '$entryName.gpg');
    final passwordFile = File(passwordFilePath);

    if (!await passwordFile.exists()) {
      print('Password file not found: $passwordFilePath');
      return null;
    }

    try {
      final encryptedContent = await passwordFile.readAsString();
      final decryptedContent = await _gpgService.decryptDataForProfile(
        encryptedContent,
        profileId,
        userGpgPassphrase,
      );
      final fileStat = await passwordFile.stat();

      return PasswordEntry.fromPassFileContent(
        decryptedContent,
        entryName,
        folderPath,
        fileStat.modified, // Используем время модификации файла
      );
    } catch (e) {
      print('Error getting password entry $entryName from $folderPath: $e');
      if (e.toString().contains('Incorrect passphrase')) {
        throw Exception('Incorrect GPG passphrase.');
      }
      rethrow; // Перебрасываем, чтобы UI мог обработать
    }
  }

  // Close the service
  Future<void> dispose() async {
    await _profilesController.close();
  }

  String generateRandomPassword({int length = 16, bool includeSpecialChars = true, bool includeNumbers = true, bool includeUppercase = true, bool includeLowercase = true}) {
    // Простая реализация. Для более криптостойких паролей используйте специализированные пакеты.
    final StringBuffer password = StringBuffer();
    String chars = '';
    if (includeLowercase) chars += 'abcdefghijklmnopqrstuvwxyz';
    if (includeUppercase) chars += 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    if (includeNumbers) chars += '0123456789';
    if (includeSpecialChars) chars += '!@#\$%^&*()-_=+[]{}|;:,.<>?';

    if (chars.isEmpty) return ''; // Не из чего генерировать

    final random = Random(); // Используйте dart:math Random
    for (int i = 0; i < length; i++) {
      password.write(chars[random.nextInt(chars.length)]);
    }
    return password.toString();
  }
}