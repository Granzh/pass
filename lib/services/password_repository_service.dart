import 'dart:async';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logging/logging.dart';
import 'package:pass/services/password_services/password_entry_service.dart';
import 'package:pass/services/profile_services/repository_profile_manager.dart';
import 'package:uuid/uuid.dart';

import '../core/utils/enums.dart';
import '../models/password_entry.dart';
import '../models/password_repository_profile.dart';
import '../models/git_repository_model.dart';
import 'git_services/git_orchestrator.dart';
import 'GPG_services/gpg_key_service.dart';

class PasswordRepositoryService {
  final RepositoryProfileManager _profileManager;
  final PasswordEntryService _entryService;
  final GitOrchestrator _gitOrchestrator;
  final GPGService _gpgService;
  final FlutterSecureStorage _secureStorage;
  static final _log = Logger('PasswordRepositoryService');


  PasswordRepositoryService({
    required RepositoryProfileManager profileManager,
    required PasswordEntryService entryService,
    required GitOrchestrator gitOrchestrator,
    required GPGService gpgService,
    required FlutterSecureStorage secureStorage,
  })  : _profileManager = profileManager,
        _entryService = entryService,
        _gitOrchestrator = gitOrchestrator,
        _gpgService = gpgService,
        _secureStorage = secureStorage;


  Future<void> loadProfiles() => _profileManager.loadProfiles();
  List<PasswordRepositoryProfile> getProfiles() => _profileManager.getProfiles();
  Stream<List<PasswordRepositoryProfile>> get profilesStream => _profileManager.profilesStream;


  Future<PasswordRepositoryProfile> createProfile({
    required String profileName,
    required PasswordSourceType type,
    String? gitProviderName,
    GitRepository? gitRepositoryInfo,
    String? explicitLocalFolderPath,
    Map<String, String>? authTokens,
    required String gpgUserPassphrase,
    bool generateNewGpgKey = true,
    String? emailForGpg,
    String? gpgExistingPrivateKeyArmored,
    String? gpgPassphraseForExistingKey,
    String? gpgExistingPublicKeyArmored,
  }) async {
    final profileId = Uuid().v4();

    // 1. GPG Key Setup
    if (generateNewGpgKey) {
      await _gpgService.generateNewKeyForProfile(
        profileId: profileId,
        passphrase: gpgUserPassphrase,
        userName: profileName,
        userEmail: emailForGpg,
      );
    } else if (gpgExistingPrivateKeyArmored != null && gpgPassphraseForExistingKey != null) {
      await _gpgService.importPrivateKeyForProfile(
        profileId: profileId,
        privateKeyArmored: gpgExistingPrivateKeyArmored,
        passphraseForImportedKey: gpgPassphraseForExistingKey,
        publicKeyArmored: gpgExistingPublicKeyArmored,
      );
    } else {
      throw Exception("GPG key configuration is missing for new profile.");
    }

    String? accessTokenStorageKey;
    String? refreshTokenStorageKey;
    if (authTokens != null && (type == PasswordSourceType.github || type == PasswordSourceType.gitlab)) {
      accessTokenStorageKey = PasswordRepositoryProfile.generateAccessTokenKey(profileId);
      refreshTokenStorageKey = PasswordRepositoryProfile.generateRefreshTokenKey(profileId);
      await _secureStorage.write(key: accessTokenStorageKey, value: authTokens['access_token']);
      if (authTokens['refresh_token'] != null) {
        await _secureStorage.write(key: refreshTokenStorageKey, value: authTokens['refresh_token']);
      }
    }

    PasswordRepositoryProfile newProfile;
    if (type == PasswordSourceType.localFolder) {
      newProfile = PasswordRepositoryProfile(
        id: profileId,
        profileName: profileName,
        type: type,
        repositoryFullName: explicitLocalFolderPath ?? profileName,
        accessTokenKey: null,
        refreshTokenKey: null,
      );
    } else if (type == PasswordSourceType.github || type == PasswordSourceType.gitlab) {
      if (gitRepositoryInfo == null) throw ArgumentError('GitRepositoryInfo is required.');
      newProfile = PasswordRepositoryProfile(
        id: profileId,
        profileName: profileName,
        type: type,
        gitProviderName: gitProviderName,
        repositoryId: gitRepositoryInfo.id.toString(),
        repositoryFullName: gitRepositoryInfo.name,
        repositoryShortName: gitRepositoryInfo.name,
        repositoryCloneUrl: gitRepositoryInfo.htmlUrl,
        repositoryDescription: gitRepositoryInfo.description,
        isPrivateRepository: gitRepositoryInfo.isPrivate,
        defaultBranch: gitRepositoryInfo.defaultBranch,
        accessTokenKey: accessTokenStorageKey,
        refreshTokenKey: refreshTokenStorageKey,
      );
    } else {
      throw UnimplementedError('Profile creation for type $type is not implemented.');
    }

    await _profileManager.addProfile(newProfile);
    try {
      await _gitOrchestrator.initializeRepositoryForProfile(
          profile: _profileManager.getProfile(profileId)!,
          gitRepoInfo: gitRepositoryInfo,
          explicitLocalFolderPath: explicitLocalFolderPath
      );
    } catch (e) {
      await _gpgService.deleteKeyForProfileById(profileId).catchError((_) {});
      if (accessTokenStorageKey != null) await _secureStorage.delete(key: accessTokenStorageKey);
      if (refreshTokenStorageKey != null) await _secureStorage.delete(key: refreshTokenStorageKey);
      await _profileManager.deleteProfile(profileId);
      rethrow;
    }

    return _profileManager.getProfile(profileId)!;
  }

  Future<PasswordRepositoryProfile> updateProfileDetails({
    required String profileId,
    String? newProfileName,
    Map<String, String>? newAuthTokens,
    // GPG
    bool shouldRegenerateGpgKey = false,
    String? newGpgUserName,
    String? newGpgUserEmail,
    String? newGpgPassphraseForRegen,
  }) async {
    PasswordRepositoryProfile? profile = _profileManager.getProfile(profileId);
    if (profile == null) throw Exception('Profile not found for update');

    bool profileChanged = false;
    String finalProfileName = newProfileName ?? profile.profileName;

    if (newProfileName != null && newProfileName != profile.profileName) {
      profile = profile.copyWith(profileName: newProfileName);
      profileChanged = true;
    }

    if (newAuthTokens != null && (profile.type == PasswordSourceType.github || profile.type == PasswordSourceType.gitlab)) {
      final currentAccessTokenKey = profile.accessTokenKey ?? PasswordRepositoryProfile.generateAccessTokenKey(profileId);
      final currentRefreshTokenKey = profile.refreshTokenKey ?? PasswordRepositoryProfile.generateRefreshTokenKey(profileId);

      await _secureStorage.write(key: currentAccessTokenKey, value: newAuthTokens['access_token']);
      profile = profile.copyWith(accessTokenKey: currentAccessTokenKey);

      if (newAuthTokens['refresh_token'] != null) {
        await _secureStorage.write(key: currentRefreshTokenKey, value: newAuthTokens['refresh_token']);
        profile = profile.copyWith(refreshTokenKey: currentRefreshTokenKey);
      } else {
        await _secureStorage.delete(key: currentRefreshTokenKey);
        profile = profile.copyWith(refreshTokenKey: null);
      }
      profileChanged = true;
    }

    if (shouldRegenerateGpgKey) {
      if (newGpgPassphraseForRegen == null) throw ArgumentError('Passphrase required for GPG key regeneration.');
      await _gpgService.deleteKeyForProfileById(profileId).catchError((_) {});
      await _gpgService.generateNewKeyForProfile(
        profileId: profileId,
        passphrase: newGpgPassphraseForRegen,
        userName: newGpgUserName ?? finalProfileName,
        userEmail: newGpgUserEmail,
      );

    }

    if (profileChanged) {
      await _profileManager.updateProfile(profileId, profile);
    }
    return _profileManager.getProfile(profileId)!;
  }

  Future<void> updateGitRepositoryRemoteDetails(String profileId, GitRepository newGitRepoInfo) async {
    final profile = _profileManager.getProfile(profileId);
    if (profile == null || (profile.type != PasswordSourceType.github && profile.type != PasswordSourceType.gitlab)) {
      throw ArgumentError('Profile not found or not a Git profile.');
    }
    await _gitOrchestrator.reCloneRepository(profileId: profileId, newGitRepoInfo: newGitRepoInfo);
  }


  Future<void> deleteProfile(String profileId, {bool deleteLocalData = true}) async {
    final profile = _profileManager.getProfile(profileId);
    if (profile == null) return;

    await _gpgService.deleteKeyForProfileById(profileId).catchError((e) {
      // log warning, e.g. key not found
    });

    if (profile.accessTokenKey != null) await _secureStorage.delete(key: profile.accessTokenKey!);
    if (profile.refreshTokenKey != null) await _secureStorage.delete(key: profile.refreshTokenKey!);

    if (deleteLocalData && profile.localPath != null) {
      final repoDir = Directory(profile.localPath!);
      if (await repoDir.exists()) {
        await repoDir.delete(recursive: true).catchError((e) {
          _log.severe('Error deleting local data for profile $profileId: $e');
          throw e;
        });
      }
    }

    await _profileManager.deleteProfile(profileId);
  }

  Future<void> syncProfileRepository(String profileId) =>
      _gitOrchestrator.syncRepository(profileId);

  Future<Map<String, dynamic>> getProfileRepositoryStatus(String profileId) =>
      _gitOrchestrator.getRepositoryStatus(profileId);

  Future<List<PasswordEntry>> getAllPasswordEntries({
    required String profileId,
    required String userGpgPassphrase,
  }) => _entryService.getAllEntries(profileId, userGpgPassphrase);

  Future<PasswordEntry?> getPasswordEntry({
    required String profileId,
    required String entryName,
    String folderPath = '',
    required String userGpgPassphrase,
  }) => _entryService.getEntry(profileId, entryName, folderPath, userGpgPassphrase);

  Future<void> savePasswordEntry({
    required String profileId,
    required PasswordEntry entry,
    required String userGpgPassphrase,
  }) => _entryService.saveEntry(profileId, entry, userGpgPassphrase);

  Future<void> deletePasswordEntry({
    required String profileId,
    required String entryName,
    String folderPath = '',
  }) => _entryService.deleteEntry(profileId, entryName, folderPath);
}