import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logging/logging.dart';
import 'package:pass/services/profile_services/repository_profile_manager_interface.dart';

import '../../models/password_repository_profile.dart';


class RepositoryProfileManager implements IProfileManager {
  static final _log = Logger('RepositoryProfileManager');
  static const String _profilesStoreKey = 'password_repository_profiles';

  static String get profilesStoreKey => _profilesStoreKey;

  List<PasswordRepositoryProfile> _profiles = [];

  final _profilesController = StreamController<List<PasswordRepositoryProfile>>.broadcast();
  @override
  Stream<List<PasswordRepositoryProfile>> get profilesStream => _profilesController.stream;

  final FlutterSecureStorage _secureStorage;

  RepositoryProfileManager({required FlutterSecureStorage secureStorage}) :_secureStorage = secureStorage;

  @override
  Future<PasswordRepositoryProfile> addProfile(PasswordRepositoryProfile profile) async {
    if (_profiles.any((p) => p.id == profile.id)) {
      _log.warning("Profile with ID ${profile.id} already exists. Consider updating instead.");
      throw Exception('Profile with ID ${profile.id} already exists.');
    }

    _log.info("Adding new profile: ${profile.profileName} (ID: ${profile.id})");
    _profiles.add(profile);
    _profilesController.add(List.unmodifiable(_profiles));
    await _persistState();
    return profile;
  }

  @override
  Future<void> deleteProfile(String profileId) async {
    _log.info("Deleting profile: ID $profileId");
    final initialLength = _profiles.length;
    PasswordRepositoryProfile? profileToDelete = getProfile(profileId);

    _profiles.removeWhere((profile) => profile.id == profileId);

    if (_profiles.length < initialLength) {
      if (profileToDelete != null) {
        if (profileToDelete.accessTokenKey != null) {
          await _secureStorage.delete(key: profileToDelete.accessTokenKey!);
          _log.finer("Access token for deleted profile ${profileToDelete.id} deleted from storage.");
        }
        if (profileToDelete.refreshTokenKey != null) {
          await _secureStorage.delete(key: profileToDelete.refreshTokenKey!);
          _log.finer("Refresh token for deleted profile ${profileToDelete.id} deleted from storage.");
        }
      }
      _profilesController.add(List.unmodifiable(_profiles));
      await _persistState();
    } else {
      _log.warning("Profile with ID $profileId not found for deletion.");
    }
  }

  @override
  Future<String?> getAccessToken(String profileId) async {
    final profile = getProfile(profileId);
    if (profile?.accessTokenKey != null) {
      try {
        return await _secureStorage.read(key: profile!.accessTokenKey!);
      } catch (e, s) {
        _log.severe("Error reading access token for ${profile!.id} with key ${profile.accessTokenKey!}: $e", e, s);
        return null;
      }
    }
    return null;
  }

  @override
  Future<String?> getRefreshToken(String profileId) async {
    final profile = getProfile(profileId);
    if (profile?.refreshTokenKey != null) {
      try {
        return await _secureStorage.read(key: profile!.refreshTokenKey!);
      } catch (e, s) {
        _log.severe("Error reading refresh token for ${profile!.id} with key ${profile.refreshTokenKey!}: $e", e, s);
        return null;
      }
    }
    return null;
  }

  @override
  PasswordRepositoryProfile? getProfile(String profileId) {
    try {
      return _profiles.firstWhere((profile) => profile.id == profileId);
    } catch (e) {
      return null;
    }
  }

  @override
  List<PasswordRepositoryProfile> getProfiles() {
    return List.unmodifiable(_profiles);
  }

  @override
  Future<void> loadProfiles() async {
    _log.info("Loading profiles...");
    try {
      final profilesJson = await _secureStorage.read(key: _profilesStoreKey);
      if (profilesJson != null) {
        final List<dynamic> profilesList = jsonDecode(profilesJson);
        _profiles = profilesList
            .map((e) => PasswordRepositoryProfile.fromJson(e as Map<String, dynamic>))
            .toList();
        _profilesController.add(List.unmodifiable(_profiles));
        _log.finer("Loaded ${_profiles.length} profiles from storage.");
      } else {
        _profiles = [];
        _profilesController.add(List.unmodifiable(_profiles));
        _log.finer("No profiles found in storage.");
      }
    } catch (e, s) {
      _log.severe("Error loading profiles: $e", e, s);
      _profiles = [];
      _profilesController.add(List.unmodifiable(_profiles));
    }
  }

  @override
  Future<PasswordRepositoryProfile> updateProfile(String profileIdToUpdate, PasswordRepositoryProfile updatedProfile) async {
    final index = _profiles.indexWhere((profile) => profile.id == profileIdToUpdate);
    if (index != -1) {
      _profiles[index] = updatedProfile;
      _profilesController.add(List.unmodifiable(_profiles));
      await _persistState();
      return updatedProfile;
    } else {
      _log.warning("Profile with ID $profileIdToUpdate not found for update.");
      throw Exception('Profile not found for update.');
    }
  }

  @override
  Future<void> updateTokensForProfile(String profileId, String newRawAccessToken, String? newRawRefreshToken) async {
    PasswordRepositoryProfile? profile = getProfile(profileId);
    if (profile == null) {
      _log.warning("Profile with ID $profileId not found for token update.");
      throw Exception('Profile not found for token update.');
    }

    PasswordRepositoryProfile updatedProfileData = profile;
    bool profileMetaDataChanged = false;

    // Access Token
    String? currentAccessTokenKey = profile.accessTokenKey;
    if (currentAccessTokenKey == null) {
      if (!profile.type.isGitType) {
        _log.warning("Attempting to add access token to a non-git profile type: ${profile.type}");
      }
      currentAccessTokenKey = PasswordRepositoryProfile.generateAccessTokenKey(profile.id);
      updatedProfileData = updatedProfileData.copyWith(accessTokenKey: currentAccessTokenKey);
      profileMetaDataChanged = true;
      _log.finer("Generated new accessTokenKey for profile ${profile.id}: $currentAccessTokenKey");
    }
    await _secureStorage.write(key: currentAccessTokenKey, value: newRawAccessToken);
    _log.info("Access token for profile ${profile.id} updated/written using key $currentAccessTokenKey.");

    // Refresh Token
    String? currentRefreshTokenKey = profile.refreshTokenKey;
    if (newRawRefreshToken != null) {
      if (currentRefreshTokenKey == null) {
        if (!profile.type.isGitType) {
          _log.warning("Attempting to add refresh token to a non-git profile type: ${profile.type}");
        }
        currentRefreshTokenKey = PasswordRepositoryProfile.generateRefreshTokenKey(profile.id);
        updatedProfileData = updatedProfileData.copyWith(refreshTokenKey: currentRefreshTokenKey);
        profileMetaDataChanged = true;
        _log.finer("Generated new refreshTokenKey for profile ${profile.id}: $currentRefreshTokenKey");
      }
      await _secureStorage.write(key: currentRefreshTokenKey, value: newRawRefreshToken);
      _log.info("Refresh token for profile ${profile.id} updated/written using key $currentRefreshTokenKey.");
    } else {
      if (currentRefreshTokenKey != null) {
        await _secureStorage.delete(key: currentRefreshTokenKey);
        updatedProfileData = updatedProfileData.copyWith(refreshTokenKey: null);
        profileMetaDataChanged = true;
        _log.info("Refresh token for profile ${profile.id} (key $currentRefreshTokenKey) deleted as new one is null.");
      }
    }

    if (profileMetaDataChanged) {
      final index = _profiles.indexWhere((p) => p.id == profile.id);
      if (index != -1) {
        _profiles[index] = updatedProfileData;
        _profilesController.add(List.unmodifiable(_profiles));
      }
    }
    await _persistState();
  }

  @override
  void dispose() {
    _profilesController.close();
    _log.info("RepositoryProfileManager disposed.");
  }

  Future<void> _persistState() async {
    _log.finer("Persisting state. Profiles count: ${_profiles.length}");
    try {
      final profilesJson = jsonEncode(_profiles.map((p) => p.toJson()).toList());
      await _secureStorage.write(key: _profilesStoreKey, value: profilesJson);
    } catch (e, s) {
      _log.severe("Error persisting state: $e", e, s);
      throw Exception('Failed to persist state: $e');
    }
  }
}