import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pass/logic/password_repository_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class ProfileService {
  final FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const String _profilesKey = 'password_repository_profiles';

  Future<List<PasswordRepositoryProfile>> getProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? profilesJsonList = prefs.getStringList(_profilesKey);

    if (profilesJsonList == null) {return [];}

    return profilesJsonList.map((profileJson) {
      return PasswordRepositoryProfile.fromJson(json.decode(profileJson) as Map<String, dynamic>);
    }).toList();
  }

  Future<void> _saveProfiles(List<PasswordRepositoryProfile> profiles) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> profilesJsonList = profiles.map((profile) {return json.encode(profile.toJson());}).toList();

    await prefs.setStringList(_profilesKey, profilesJsonList);
  }

  Future<PasswordRepositoryProfile> addProfile({
    required String profileName,
    required PasswordSourceType type,
    String? gitProviderName,
    String? rawAccessToken,
    String? rawRefreshToken,
    String? repositoryId,
    required String repositoryFullName,
    String? defaultBranch
  }) async {
    final newProfile = PasswordRepositoryProfile(
      profileName: profileName,
      type: type,
      gitProviderName: gitProviderName,
      repositoryId: repositoryId,
      repositoryFullName: repositoryFullName,
      defaultBranch: defaultBranch,
      accessTokenKey: (type == PasswordSourceType.github ||
          type == PasswordSourceType.gitlab) && rawAccessToken != null
          ? PasswordRepositoryProfile.generateAccessTokenKey(Uuid().v4())
          : null,
      refreshTokenKey: (type == PasswordSourceType.github ||
          type == PasswordSourceType.gitlab) && rawRefreshToken != null
          ? PasswordRepositoryProfile.generateRefreshTokenKey(Uuid().v4())
          : null,
      id: Uuid().v4(),

    );

    final finalProfile = PasswordRepositoryProfile(
      id: newProfile.id,
      profileName: newProfile.profileName,
      type: newProfile.type,
      gitProviderName: newProfile.gitProviderName,
      repositoryId: newProfile.repositoryId,
      repositoryFullName: newProfile.repositoryFullName,
      defaultBranch: newProfile.defaultBranch,
      createdAt: newProfile.createdAt,
      accessTokenKey: newProfile.accessTokenKey != null
          ? PasswordRepositoryProfile.generateAccessTokenKey(newProfile.id)
          : null,
      refreshTokenKey: newProfile.refreshTokenKey != null
          ? PasswordRepositoryProfile.generateRefreshTokenKey(newProfile.id)
          : null,
    );

    if ((finalProfile.type == PasswordSourceType.github ||
        finalProfile.type == PasswordSourceType.gitlab)) {
      if (rawAccessToken != null && finalProfile.accessTokenKey != null) {
        await _secureStorage.write(
            key: finalProfile.accessTokenKey!, value: rawAccessToken);
        print('Access token for ${finalProfile
            .profileName} saved with key: ${finalProfile.accessTokenKey}');
      }
      if (rawRefreshToken != null && finalProfile.refreshTokenKey != null) {
        await _secureStorage.write(
            key: finalProfile.refreshTokenKey!, value: rawRefreshToken);
        print('Refresh token for ${finalProfile
            .profileName} saved with key: ${finalProfile.refreshTokenKey}');
      }
    }
    final List<PasswordRepositoryProfile> currentProfiles = await getProfiles();
    currentProfiles.add(finalProfile);
    await _saveProfiles(currentProfiles);
    print('Profile added: ${finalProfile.profileName}');
    return finalProfile;
  }
  Future<void> updateProfile(PasswordRepositoryProfile updatedProfile) async {
    final List<PasswordRepositoryProfile> currentProfiles = await getProfiles();
    final index = currentProfiles.indexWhere((p) => p.id == updatedProfile.id);

    if (index != -1) {
      currentProfiles[index] = updatedProfile;
      await _saveProfiles(currentProfiles);
    } else {
      print('Profile with ID ${updatedProfile.id} not found.');
    }
  }

  Future<void> deleteProfile(String profileId) async {
    final List<PasswordRepositoryProfile> currentProfiles = await getProfiles();
    final profileToRemove = currentProfiles.firstWhere((p) => p.id == profileId, orElse: () => throw Exception('Profile not found for deletion'));

    if (profileToRemove.accessTokenKey != null) {
      await _secureStorage.delete(key: profileToRemove.accessTokenKey!);
      print('Access token for profile ${profileToRemove.id} deleted.');
    }
    if (profileToRemove.refreshTokenKey != null) {
      await _secureStorage.delete(key: profileToRemove.refreshTokenKey!);
      print('Refresh token for profile ${profileToRemove.id} deleted.');
    }

    currentProfiles.removeWhere((p) => p.id == profileId);
    await _saveProfiles(currentProfiles);
    print('Profile deleted: $profileId');
  }

  Future<String?> getAccessTokenForProfile(String profileId) async {
    final profiles = await getProfiles();
    try {
      final profile = profiles.firstWhere((p) => p.id == profileId);
      if (profile.accessTokenKey != null) {
        return await _secureStorage.read(key: profile.accessTokenKey!);
      }
    } catch (e) {
      print('Profile with id $profileId not found when getting access token.');
      return null;
    }
    return null;
  }

  Future<String?> getRefreshTokenForProfile(String profileId) async {
    final profiles = await getProfiles();
    try {
      final profile = profiles.firstWhere((p) => p.id == profileId);
      if (profile.refreshTokenKey != null) {
        return await _secureStorage.read(key: profile.refreshTokenKey!);
      }
    } catch (e) {
      print('Profile with id $profileId not found when getting refresh token.');
      return null;
    }
    return null;
  }

  Future<void> updateTokensForProfile(String profileId, String newAccessToken, String? newRefreshToken) async {
    final profiles = await getProfiles();
    try {
      final profile = profiles.firstWhere((p) => p.id == profileId);
      if (profile.accessTokenKey != null) {
        await _secureStorage.write(key: profile.accessTokenKey!, value: newAccessToken);
        print('Access token updated for profile $profileId');
      }
      if (newRefreshToken != null && profile.refreshTokenKey != null) {
        await _secureStorage.write(key: profile.refreshTokenKey!, value: newRefreshToken);
        print('Refresh token updated for profile $profileId');
      }
    } catch (e) {
      print('Profile with id $profileId not found when updating tokens.');
    }
  }
}