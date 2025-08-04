import '../../models/password_repository_profile.dart';

abstract class IProfileManager {
  Stream<List<PasswordRepositoryProfile>> get profilesStream;
  Stream<PasswordRepositoryProfile?> get activeProfileStream;

  Future<void> loadProfiles();
  void dispose();

  List<PasswordRepositoryProfile> getProfiles();
  PasswordRepositoryProfile? getProfile(String profileId);

  Future<String?> getAccessToken(String profileId);
  Future<String?> getRefreshToken(String profileId);

  Future<PasswordRepositoryProfile> addProfile(PasswordRepositoryProfile profile);
  Future<PasswordRepositoryProfile> setActiveProfile(PasswordRepositoryProfile profile);
  Future<PasswordRepositoryProfile?> getActiveProfile();

  Future<PasswordRepositoryProfile> updateProfile(String profileIdToUpdate, PasswordRepositoryProfile updatedProfile);
  Future<void> deleteProfile(String profileId);
  Future<void> updateTokensForProfile(String profileId, String newAccessToken, String? newRefreshToken);
}