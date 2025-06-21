import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../logic/password_repository_profile.dart';
import '../logic/secure_storage.dart';
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
    return _profiles.firstWhere(
          (profile) => profile.id == _activeProfileId,
      orElse: () => throw Exception('Active profile not found'),
    );
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
    required String name,
    required PasswordSourceType type,
    String? gitProviderName,
    String? repositoryId,
    required String repositoryFullName,
    String? defaultBranch,
    Map<String, String>? authTokens,
  }) async {
    final profileId = id ?? const Uuid().v4();
    String? accessTokenKey;
    String? refreshTokenKey;

    if (authTokens != null) {
      accessTokenKey = 'profile_${profileId}_access_token';
      refreshTokenKey = 'profile_${profileId}_refresh_token';

      await Future.wait([
        if (authTokens['access_token'] != null)
          _secureStorage.write(key: accessTokenKey, value: authTokens['access_token']!),
        if (authTokens['refresh_token'] != null)
          _secureStorage.write(key: refreshTokenKey, value: authTokens['refresh_token']!),
      ]);
    }

    // Ensure repository directory exists
    final repoPath = await getRepositoryPath(profileId);
    await Directory(repoPath).create(recursive: true);

    final profile = PasswordRepositoryProfile(
      id: profileId,
      profileName: name,
      type: type,
      gitProviderName: gitProviderName,
      repositoryId: repositoryId,
      repositoryFullName: repositoryFullName,
      defaultBranch: defaultBranch,
      accessTokenKey: accessTokenKey,
      refreshTokenKey: refreshTokenKey,
    );

    _profiles.add(profile);
    await _saveProfiles();

    if (_activeProfileId == null) {
      await setActiveProfile(profile.id);
    }

    return profile;
  }

  // Update an existing repository profile
  Future<PasswordRepositoryProfile> updateRepository({
    required String id,
    String? name,
    Map<String, String>? authTokens,
  }) async {
    final index = _profiles.indexWhere((p) => p.id == id);
    if (index == -1) {
      throw Exception('Repository profile not found');
    }

    final profile = _profiles[index];
    String? accessTokenKey = profile.accessTokenKey;
    String? refreshTokenKey = profile.refreshTokenKey;

    if (authTokens != null) {
      accessTokenKey ??= 'profile_${id}_access_token';
      refreshTokenKey ??= 'profile_${id}_refresh_token';

      await Future.wait([
        if (authTokens['access_token'] != null)
          _secureStorage.write(key: accessTokenKey, value: authTokens['access_token']!),
        if (authTokens['refresh_token'] != null)
          _secureStorage.write(key: refreshTokenKey, value: authTokens['refresh_token']!),
      ]);
    }

    final updatedProfile = PasswordRepositoryProfile(
      id: profile.id,
      profileName: name ?? profile.profileName,
      type: profile.type,
      gitProviderName: profile.gitProviderName,
      repositoryId: profile.repositoryId,
      repositoryFullName: profile.repositoryFullName,
      defaultBranch: profile.defaultBranch,
      createdAt: profile.createdAt,
      accessTokenKey: accessTokenKey,
      refreshTokenKey: refreshTokenKey,
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
      print('Error removing GPG keys: $e');
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
  Future<void> syncRepository(String profileId) async {
    final profile = _profiles.firstWhere(
          (p) => p.id == profileId,
      orElse: () => throw Exception('Profile not found'),
    );

    final repoPath = await getRepositoryPath(profileId);
    final dir = Directory(repoPath);

    if (profile.type == PasswordSourceType.localFolder) {
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return;
    }

    // For Git repositories
    final accessToken = profile.accessTokenKey != null
        ? await _secureStorage.read(key: profile.accessTokenKey!)
        : null;

    if (accessToken == null) {
      throw Exception('Not authenticated with Git provider');
    }

    if (await dir.exists()) {
      // Pull latest changes
      await _gitService.pullChanges(repoPath);
    } else {
      // Clone repository
      final repo = GitRepository(
        id: profile.repositoryId ?? '',
        name: profile.repositoryFullName,
        description: '',
        htmlUrl: '',
        isPrivate: true,
        defaultBranch: profile.defaultBranch ?? 'main',
      );
      await _gitService.cloneRepository(repo, profileId);
    }
  }

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
  // Encrypt and save a password
  Future<void> savePassword({
    required String profileId,
    required String name,
    required String password,
    String? description,
    Map<String, String>? metadata,
  }) async {
    final profile = _profiles.firstWhere(
          (p) => p.id == profileId,
      orElse: () => throw Exception('Profile not found'),
    );

    final gpgKey = await _gpgService.getKeyForProfileById(profileId);
    if (gpgKey == null) {
      throw Exception('No GPG key found for this profile');
    }

    // Create password data
    final passwordData = {
      'name': name,
      'password': password, // Store the original password here before encryption
      'description': description,
      'metadata': metadata,
      'createdAt': DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
    };

    // Convert to JSON and encrypt the entire data
    final jsonData = jsonEncode(passwordData);
    final encryptedData = await _gpgService.encryptPassword(
      jsonData,  // Encrypt the entire JSON string
      gpgKey.publicKey,
    );

    final repoPath = await getRepositoryPath(profileId);
    final passwordFile = File('$repoPath/$name.gpg');

    // Ensure directory exists
    await passwordFile.parent.create(recursive: true);

    // Save the encrypted data
    await passwordFile.writeAsString(encryptedData);

    // If using Git, commit the changes
    if (profile.type != PasswordSourceType.localFolder) {
      await _gitService.pushChanges(
        repoPath,
        'Add/update password: $name',
      );
    }
  }

  // Get a decrypted password
  Future<Map<String, dynamic>> getPassword({
    required String profileId,
    required String name,
  }) async {
    final gpgKey = await _gpgService.getKeyForProfileById(profileId);
    if (gpgKey == null) {
      throw Exception('No GPG key found for this profile');
    }

    final repoPath = await getRepositoryPath(profileId);
    final passwordFile = File('$repoPath/$name.gpg');

    if (!await passwordFile.exists()) {
      throw Exception('Password not found');
    }

    final encryptedData = await passwordFile.readAsString();
    final decryptedJson = await _gpgService.decryptPassword(
      encryptedData,
      gpgKey.privateKey,
      gpgKey.passphrase,
    );

    // Parse the JSON data
    final passwordData = jsonDecode(decryptedJson) as Map<String, dynamic>;
    return passwordData;
  }

  // Close the service
  Future<void> dispose() async {
    await _profilesController.close();
  }
}