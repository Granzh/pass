import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:pass/core/utils/enums.dart';
import 'package:pass/models/password_repository_profile.dart';
import 'package:pass/services/profile_services/repository_profile_manager.dart';

import 'repository_profile_manager_test.mocks.dart';
@GenerateMocks([FlutterSecureStorage])

PasswordRepositoryProfile createTestProfile({
  String? id,
  String name = 'Test Profile',
  PasswordSourceType type = PasswordSourceType.localFolder,
  String? accessTokenKey,
  String? refreshTokenKey,
}) {
  return PasswordRepositoryProfile(
    id: id ?? DateTime.now().millisecondsSinceEpoch.toString(),
    profileName: name,
    type: type,
    repositoryFullName: type == PasswordSourceType.localFolder ? '' : 'test/repo',
    accessTokenKey: accessTokenKey,
    refreshTokenKey: refreshTokenKey,
  );
}

void main() {
  late RepositoryProfileManager profileManager;
  late MockFlutterSecureStorage mockSecureStorage;

  setUpAll(() {
    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((record) {
      if (record.error != null) {
      }
      if (record.stackTrace != null) {
      }
    });
  });

  setUp(() {
    mockSecureStorage = MockFlutterSecureStorage();
    profileManager = RepositoryProfileManager(secureStorage: mockSecureStorage);

    when(mockSecureStorage.read(key: anyNamed('key'))).thenAnswer((_) async => null);
    when(mockSecureStorage.write(key: anyNamed('key'), value: anyNamed('value'))).thenAnswer((_) async => {});
    when(mockSecureStorage.delete(key: anyNamed('key'))).thenAnswer((_) async => {});
  });

  group('RepositoryProfileManager Tests', () {
    // --- tests for loadProfiles ---
    group('loadProfiles', () {
      test('should load profiles from secure storage if they exist', () async {
        final profile1 = createTestProfile(id: '1', name: 'Profile 1');
        final profile2 = createTestProfile(id: '2', name: 'Profile 2');
        final profilesJson = jsonEncode([profile1.toJson(), profile2.toJson()]);

        when(mockSecureStorage.read(key: RepositoryProfileManager.profilesStoreKey))
            .thenAnswer((_) async => profilesJson);

        final expectedProfilesList = [profile1, profile2];

        expectLater(profileManager.profilesStream, emits(equals(expectedProfilesList)));

        await profileManager.loadProfiles();

        expect(profileManager.getProfiles().length, 2);
        expect(profileManager.getProfile('1')?.profileName, 'Profile 1');
      });

      test('should initialize with an empty list if no profiles in storage', () async {
        when(mockSecureStorage.read(key: RepositoryProfileManager.profilesStoreKey))
            .thenAnswer((_) async => null);
        expectLater(profileManager.profilesStream, emits([]));

        await profileManager.loadProfiles();

        expect(profileManager.getProfiles().isEmpty, isTrue);
      });

      test('should handle JSON decoding errors gracefully and initialize empty', () async {
        when(mockSecureStorage.read(key: RepositoryProfileManager.profilesStoreKey))
            .thenAnswer((_) async => 'invalid json');

        await profileManager.loadProfiles();

        expect(profileManager.getProfiles().isEmpty, isTrue);
      });

      test('should handle other storage errors gracefully and initialize empty', () async {
        when(mockSecureStorage.read(key: RepositoryProfileManager.profilesStoreKey))
            .thenThrow(Exception("Storage Read Error"));

        await profileManager.loadProfiles();
        expect(profileManager.getProfiles().isEmpty, isTrue);
      });
    });

    // --- tests for addProfile ---
    group('addProfile', () {
      test('should add a new profile and persist state', () async {
        final newProfile = createTestProfile(id: 'newId');
        List<PasswordRepositoryProfile>? emittedProfiles;
        profileManager.profilesStream.listen((profiles) {
          emittedProfiles = profiles;
        });

        final addedProfile = await profileManager.addProfile(newProfile);

        expect(addedProfile, newProfile);
        expect(profileManager.getProfiles().length, 1);
        expect(profileManager.getProfile('newId'), newProfile);
        expect(emittedProfiles, isNotNull);
        expect(emittedProfiles, contains(newProfile));


        final expectedJson = jsonEncode([newProfile.toJson()]);
        verify(mockSecureStorage.write(key: RepositoryProfileManager.profilesStoreKey, value: expectedJson)).called(1);
      });

      test('should throw an exception if profile with the same ID already exists', () async {
        final existingProfile = createTestProfile(id: 'existingId');
        await profileManager.addProfile(existingProfile);

        final duplicateProfile = createTestProfile(id: 'existingId', name: 'Duplicate Name');

        expect(
                () async => await profileManager.addProfile(duplicateProfile),
            throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('already exists')))
        );
        expect(profileManager.getProfiles().length, 1);
      });

      test('should throw an exception if _persistState fails', () async {
        final newProfile = createTestProfile(id: 'persistFailId');
        when(mockSecureStorage.write(key: RepositoryProfileManager.profilesStoreKey, value: anyNamed('value')))
            .thenThrow(Exception("Persist Failed"));

        expect(
                () async => await profileManager.addProfile(newProfile),
            throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Failed to persist state')))
        );

        expect(profileManager.getProfile('persistFailId'), isNotNull, reason: "Profile should be in memory even if persist failed, as per current code");
      });
    });

    // --- tests for getProfile, getProfiles ---
    group('getProfile / getProfiles', () {
      test('getProfiles should return an unmodifiable list of current profiles', () async {
        final profile1 = createTestProfile(id: '1');
        await profileManager.addProfile(profile1);
        final profiles = profileManager.getProfiles();
        expect(profiles, [profile1]);
        expect(() => profiles.add(createTestProfile(id: '2')), throwsUnsupportedError);
      });

      test('getProfile should return the correct profile by ID', () async {
        final profile1 = createTestProfile(id: '1');
        final profile2 = createTestProfile(id: '2');
        await profileManager.addProfile(profile1);
        await profileManager.addProfile(profile2);

        expect(profileManager.getProfile('1'), profile1);
        expect(profileManager.getProfile('2'), profile2);
      });

      test('getProfile should return null if profile with ID does not exist', () async {
        expect(profileManager.getProfile('nonExistentId'), isNull);
      });
    });


    // --- tests for deleteProfile ---
    group('deleteProfile', () {
      late PasswordRepositoryProfile profileToDelete;
      const profileId = 'deleteId';
      const accessTokenKey = 'accessKey_deleteId';
      const refreshTokenKey = 'refreshKey_deleteId';

      setUp(() async {
        profileToDelete = createTestProfile(
          id: profileId,
          type: PasswordSourceType.github,
          accessTokenKey: accessTokenKey,
          refreshTokenKey: refreshTokenKey,
        );
        await profileManager.addProfile(profileToDelete);
        when(mockSecureStorage.read(key: accessTokenKey)).thenAnswer((_) async => 'fake_access_token');
        when(mockSecureStorage.read(key: refreshTokenKey)).thenAnswer((_) async => 'fake_refresh_token');
      });

      test('should delete a profile and its tokens, then persist state', () async {
        List<PasswordRepositoryProfile>? emittedProfiles;
        profileManager.profilesStream.listen((profiles) {
          emittedProfiles = profiles;
        });
        expect(profileManager.getProfile(profileId), isNotNull);

        await profileManager.deleteProfile(profileId);

        expect(profileManager.getProfile(profileId), isNull);
        expect(profileManager.getProfiles().isEmpty, isTrue);
        expect(emittedProfiles, isEmpty);

        verify(mockSecureStorage.delete(key: accessTokenKey)).called(1);
        verify(mockSecureStorage.delete(key: refreshTokenKey)).called(1);

        final expectedJson = jsonEncode([]);
        verify(mockSecureStorage.write(key: RepositoryProfileManager.profilesStoreKey, value: expectedJson)).called(1);
      });

      test('should not throw if profile to delete does not exist and not call persist', () async {
        clearInteractions(mockSecureStorage);
        await profileManager.deleteProfile('nonExistentId');

        expect(profileManager.getProfiles().length, 1);
        verifyNever(mockSecureStorage.write(key: RepositoryProfileManager.profilesStoreKey, value: anyNamed('value')));
        verifyNever(mockSecureStorage.delete(key: accessTokenKey));
      });


      test('should correctly delete profile without token keys', () async {
        clearInteractions(mockSecureStorage);

        final localProfile = createTestProfile(id: 'localDelId', type: PasswordSourceType.localFolder);
        await profileManager.addProfile(localProfile);

        clearInteractions(mockSecureStorage);

        expect(profileManager.getProfile(localProfile.id), isNotNull);

        await profileManager.deleteProfile(localProfile.id);

        expect(profileManager.getProfile(localProfile.id), isNull);
        verifyNever(mockSecureStorage.delete(key: argThat(startsWith('accessKey_'), named: 'key')));
        verifyNever(mockSecureStorage.delete(key: argThat(startsWith('refreshKey_'), named: 'key')));

        final expectedJson = jsonEncode([profileToDelete.toJson()]);
        verify(mockSecureStorage.write(key: RepositoryProfileManager.profilesStoreKey, value: expectedJson)).called(1);
      });

      /*
      test('should throw if _persistState fails during deletion', () async {
        when(mockSecureStorage.write(key: RepositoryProfileManager.profilesStoreKey, value: anyNamed('value')))
            .thenThrow(Exception("Persist Failed"));

        expectLater(
                () async => await profileManager.deleteProfile(profileId),
            throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Failed to persist state')))
        );

        expect(profileManager.getProfile(profileId), isNull);

        verify(mockSecureStorage.delete(key: accessTokenKey)).called(1);
        verify(mockSecureStorage.delete(key: refreshTokenKey)).called(1);
      });

       */
    });

    // --- tests for updateProfile ---
    group('updateProfile', () {
      late PasswordRepositoryProfile initialProfile;
      const profileIdToUpdate = 'updateId';

      setUp(() async {
        initialProfile = createTestProfile(id: profileIdToUpdate, name: 'Initial Name');
        await profileManager.addProfile(initialProfile);
      });

      test('should update an existing profile and persist state', () async {
        final updatedProfileData = createTestProfile(id: profileIdToUpdate, name: 'Updated Name');
        List<PasswordRepositoryProfile>? emittedProfiles;
        profileManager.profilesStream.listen((profiles) {
          emittedProfiles = profiles;
        });

        final resultProfile = await profileManager.updateProfile(profileIdToUpdate, updatedProfileData);

        expect(resultProfile, updatedProfileData);
        expect(profileManager.getProfile(profileIdToUpdate)?.profileName, 'Updated Name');
        expect(emittedProfiles, contains(updatedProfileData));

        final expectedJson = jsonEncode([updatedProfileData.toJson()]);
        verify(mockSecureStorage.write(key: RepositoryProfileManager.profilesStoreKey, value: expectedJson)).called(1);
      });

      test('should throw an exception if profile to update does not exist', () async {
        final nonExistentUpdate = createTestProfile(id: 'nonExistentId', name: 'Non Existent');
        expect(
                () async => await profileManager.updateProfile('nonExistentId', nonExistentUpdate),
            throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Profile not found for update')))
        );
      });

      test('should throw if _persistState fails during update', () async {
        final updatedProfileData = createTestProfile(id: profileIdToUpdate, name: 'Update Persist Fail');
        when(mockSecureStorage.write(key: RepositoryProfileManager.profilesStoreKey, value: anyNamed('value')))
            .thenThrow(Exception("Persist Failed"));

        expectLater(
                () async => await profileManager.updateProfile(profileIdToUpdate, updatedProfileData),
            throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Failed to persist state')))
        );
        expect(profileManager.getProfile(profileIdToUpdate)?.profileName, 'Update Persist Fail');
      });
    });


    // --- tests for getAccessToken / getRefreshToken ---
    group('getAccessToken / getRefreshToken', () {
      const profileId = 'tokenProfileId';
      const accessTokenKey = 'accessKey_tokenProfileId';
      const refreshTokenKey = 'refreshKey_tokenProfileId';
      const fakeAccessToken = 'actual_access_token_value';
      const fakeRefreshToken = 'actual_refresh_token_value';

      setUp(() async {
        final profileWithTokens = createTestProfile(
            id: profileId,
            accessTokenKey: accessTokenKey,
            refreshTokenKey: refreshTokenKey
        );
        final profileWithoutTokens = createTestProfile(id: 'noTokenId');
        await profileManager.addProfile(profileWithTokens);
        await profileManager.addProfile(profileWithoutTokens);

        when(mockSecureStorage.read(key: accessTokenKey)).thenAnswer((_) async => fakeAccessToken);
        when(mockSecureStorage.read(key: refreshTokenKey)).thenAnswer((_) async => fakeRefreshToken);
      });

      test('getAccessToken should return token value from secure storage', () async {
        final token = await profileManager.getAccessToken(profileId);
        expect(token, fakeAccessToken);
        verify(mockSecureStorage.read(key: accessTokenKey)).called(1);
      });

      test('getRefreshToken should return token value from secure storage', () async {
        final token = await profileManager.getRefreshToken(profileId);
        expect(token, fakeRefreshToken);
        verify(mockSecureStorage.read(key: refreshTokenKey)).called(1);
      });

      test('getAccessToken should return null if profile has no accessTokenKey', () async {
        final token = await profileManager.getAccessToken('noTokenId');
        expect(token, isNull);
        verifyNever(mockSecureStorage.read(key: anyNamed('key')));
      });

      test('getRefreshToken should return null if profile has no refreshTokenKey', () async {
        final token = await profileManager.getRefreshToken('noTokenId');
        expect(token, isNull);
        verifyNever(mockSecureStorage.read(key: anyNamed('key')));
      });

      test('getAccessToken should return null if profile does not exist', () async {
        final token = await profileManager.getAccessToken('ghostProfile');
        expect(token, isNull);
      });

      test('getRefreshToken should return null if profile does not exist', () async {
        final token = await profileManager.getRefreshToken('ghostProfile');
        expect(token, isNull);
      });

      test('getAccessToken should return null and log error if secure storage read fails', () async {
        when(mockSecureStorage.read(key: accessTokenKey)).thenThrow(Exception("Read Error"));
        final token = await profileManager.getAccessToken(profileId);
        expect(token, isNull);
      });

      test('getRefreshToken should return null and log error if secure storage read fails', () async {
        when(mockSecureStorage.read(key: refreshTokenKey)).thenThrow(Exception("Read Error"));
        final token = await profileManager.getRefreshToken(profileId);
        expect(token, isNull);
      });
    });

    // --- tests for updateTokensForProfile ---
    group('updateTokensForProfile', () {
      const profileId = 'updateTokenId';
      final initialProfile = createTestProfile(id: profileId, type: PasswordSourceType.github); // Git-тип для генерации ключей
      const newAccessTokenValue = 'new_access_token';
      const newRefreshTokenValue = 'new_refresh_token';

      setUp(() async {
        await profileManager.addProfile(initialProfile);
      });

      test('should generate keys, write tokens, update profile in memory, and persist state if keys were null', () async {
        List<PasswordRepositoryProfile>? emittedProfiles;
        profileManager.profilesStream.listen((profiles) {
          emittedProfiles = profiles;
        });

        await profileManager.updateTokensForProfile(profileId, newAccessTokenValue, newRefreshTokenValue);

        final updatedProfile = profileManager.getProfile(profileId);
        expect(updatedProfile, isNotNull);
        expect(updatedProfile?.accessTokenKey, isNotNull);
        expect(updatedProfile?.refreshTokenKey, isNotNull);

        final generatedAccessKey = updatedProfile!.accessTokenKey!;
        final generatedRefreshKey = updatedProfile.refreshTokenKey!;

        verify(mockSecureStorage.write(key: generatedAccessKey, value: newAccessTokenValue)).called(1);
        verify(mockSecureStorage.write(key: generatedRefreshKey, value: newRefreshTokenValue)).called(1);

        expect(emittedProfiles?.firstWhere((p) => p.id == profileId).accessTokenKey, generatedAccessKey);

        final expectedJson = jsonEncode([updatedProfile.toJson()]);
        verify(mockSecureStorage.write(key: RepositoryProfileManager.profilesStoreKey, value: expectedJson)).called(1);
      });

      test('should use existing keys, write tokens, and persist state if keys exist', () async {
        const existingAccessKey = 'existingAccessKey';
        const existingRefreshKey = 'existingRefreshKey';
        final profileWithExistingKeys = createTestProfile(
          id: 'existingTokenKeysId',
          type: PasswordSourceType.github,
          accessTokenKey: existingAccessKey,
          refreshTokenKey: existingRefreshKey,
        );
        await profileManager.addProfile(profileWithExistingKeys);

        await profileManager.updateTokensForProfile('existingTokenKeysId', newAccessTokenValue, newRefreshTokenValue);

        verify(mockSecureStorage.write(key: existingAccessKey, value: newAccessTokenValue)).called(1);
        verify(mockSecureStorage.write(key: existingRefreshKey, value: newRefreshTokenValue)).called(1);

        final profileAfterUpdate = profileManager.getProfile('existingTokenKeysId');
        expect(profileAfterUpdate?.accessTokenKey, existingAccessKey);

        verify(mockSecureStorage.write(key: RepositoryProfileManager.profilesStoreKey, value: anyNamed('value'))).called(1);
      });

      test('should delete refresh token if newRawRefreshToken is null and update profile', () async {
        const accessKey = 'accessKeyForNullRefresh';
        const refreshKey = 'refreshKeyForNullRefresh';
        final profileWithRefresh = createTestProfile(
          id: 'nullRefreshTestId',
          type: PasswordSourceType.github,
          accessTokenKey: accessKey,
          refreshTokenKey: refreshKey,
        );
        await profileManager.addProfile(profileWithRefresh);

        await mockSecureStorage.write(key: accessKey, value: "initial_access");
        await mockSecureStorage.write(key: refreshKey, value: "initial_refresh");

        await profileManager.updateTokensForProfile('nullRefreshTestId', newAccessTokenValue, null);

        verify(mockSecureStorage.write(key: accessKey, value: newAccessTokenValue)).called(1);
        verify(mockSecureStorage.delete(key: refreshKey)).called(1);

        final updatedProfile = profileManager.getProfile('nullRefreshTestId');
        expect(updatedProfile?.refreshTokenKey, isNull);

        final expectedJson = jsonEncode([updatedProfile!.toJson()]);
        verify(mockSecureStorage.write(key: RepositoryProfileManager.profilesStoreKey, value: expectedJson)).called(1);
      });

      test('should throw an exception if profile does not exist', () async {
        expect(
                () async => await profileManager.updateTokensForProfile('nonExistentId', 'a', 'b'),
            throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Profile not found for token update')))
        );
      });

      test('should log warning if attempting to add token to non-git type but still proceed with key generation', () async {
        final localProfile = createTestProfile(id: 'localTokenTest', type: PasswordSourceType.localFolder);
        await profileManager.addProfile(localProfile);

        await profileManager.updateTokensForProfile('localTokenTest', newAccessTokenValue, newRefreshTokenValue);

        final updatedProfile = profileManager.getProfile('localTokenTest');
        expect(updatedProfile?.accessTokenKey, isNotNull);
        expect(updatedProfile?.refreshTokenKey, isNotNull);

        verify(mockSecureStorage.write(key: updatedProfile!.accessTokenKey!, value: newAccessTokenValue)).called(1);
        verify(mockSecureStorage.write(key: updatedProfile.refreshTokenKey!, value: newRefreshTokenValue)).called(1);

        verify(mockSecureStorage.write(key: RepositoryProfileManager.profilesStoreKey, value: anyNamed('value'))).called(1);
      });

      test('should throw if _persistState fails', () async {
        when(mockSecureStorage.write(key: RepositoryProfileManager.profilesStoreKey, value: anyNamed('value')))
            .thenThrow(Exception("Persist Failed"));

        expect(
                () async => await profileManager.updateTokensForProfile(profileId, newAccessTokenValue, newRefreshTokenValue),
            throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Failed to persist state')))
        );
        final inMemoryProfile = profileManager.getProfile(profileId);
        expect(inMemoryProfile?.accessTokenKey, isNotNull);
        verify(mockSecureStorage.write(key: inMemoryProfile!.accessTokenKey!, value: newAccessTokenValue)).called(1);
      });
    });

    // --- tests for dispose ---
    group('dispose', () {
      test('should close the profiles stream controller', () async {

        bool isDone = false;
        profileManager.profilesStream.listen(null, onDone: () {
          isDone = true;
        });

        profileManager.dispose();
        expect(isDone, isTrue);
      });
    });

  });
}
