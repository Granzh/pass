import 'package:flutter_test/flutter_test.dart';
import 'package:pass/core/utils/enums.dart';
import 'package:pass/models/password_repository_profile.dart';


void main() {
  final testDateTime = DateTime(2023, 1, 1, 12, 0, 0);
  final testDateTimeIso = testDateTime.toIso8601String();

  group('PasswordRepositoryProfile', () {
    group('Constructor and Defaults', () {
      test('should correctly initialize with required fields and default createdAt', () {
        final beforeCreation = DateTime.now();
        final profile = PasswordRepositoryProfile(
          id: 'id1',
          profileName: 'Profile 1',
          type: PasswordSourceType.github,
          repositoryFullName: 'user/repo1',
        );
        final afterCreation = DateTime.now();

        expect(profile.id, 'id1');
        expect(profile.profileName, 'Profile 1');
        expect(profile.type, PasswordSourceType.github);
        expect(profile.repositoryFullName, 'user/repo1');
        expect(profile.createdAt.isAfter(beforeCreation) || profile.createdAt.isAtSameMomentAs(beforeCreation), isTrue);
        expect(profile.createdAt.isBefore(afterCreation) || profile.createdAt.isAtSameMomentAs(afterCreation), isTrue);

        // Check optional fields are null by default
        expect(profile.gitProviderName, isNull);
        expect(profile.repositoryId, isNull);
        // ... (check all other optional fields)
        expect(profile.localPath, isNull);
      });

      test('should use provided createdAt', () {
        final profile = PasswordRepositoryProfile(
          id: 'id1',
          profileName: 'Profile 1',
          type: PasswordSourceType.github,
          repositoryFullName: 'user/repo1',
          createdAt: testDateTime,
        );
        expect(profile.createdAt, testDateTime);
      });

      test('should correctly initialize with all fields provided', () {
        final profile = PasswordRepositoryProfile(
          id: 'id-full',
          profileName: 'Full Profile',
          type: PasswordSourceType.gitlab,
          gitProviderName: 'gitlab',
          repositoryId: 'repo-id-123',
          repositoryFullName: 'gitlab-user/project-x',
          repositoryShortName: 'project-x',
          repositoryCloneUrl: 'https://gitlab.com/gitlab-user/project-x.git',
          repositoryDescription: 'A test project',
          isPrivateRepository: true,
          defaultBranch: 'main',
          gpgUserName: 'tester@example.com',
          createdAt: testDateTime,
          accessTokenKey: 'access_key_1',
          refreshTokenKey: 'refresh_key_1',
          localPath: '/path/to/repo',
        );

        expect(profile.id, 'id-full');
        expect(profile.profileName, 'Full Profile');
        expect(profile.type, PasswordSourceType.gitlab);
        expect(profile.gitProviderName, 'gitlab');
        expect(profile.repositoryId, 'repo-id-123');
        expect(profile.repositoryFullName, 'gitlab-user/project-x');
        expect(profile.repositoryShortName, 'project-x');
        // ...expect for all other fields
        expect(profile.createdAt, testDateTime);
        expect(profile.localPath, '/path/to/repo');
      });
    });

    group('empty() static method', () {
      test('should return a profile with correct default empty values', () {
        final emptyProfile = PasswordRepositoryProfile.empty();
        // We need to compare createdAt separately or mock DateTime.now
        final now = DateTime.now();

        expect(emptyProfile.id, '');
        expect(emptyProfile.profileName, 'Unknown Profile');
        expect(emptyProfile.repositoryFullName, 'Unknown Repository');
        expect(emptyProfile.type, PasswordSourceType.unknown);
        // Check that createdAt is recent
        expect(now.difference(emptyProfile.createdAt).inSeconds < 2, isTrue);


        // Optional fields should be null
        expect(emptyProfile.gitProviderName, isNull);
        // ... (check all other optional fields are null)
        expect(emptyProfile.localPath, isNull);
      });
    });

    group('Serialization/Deserialization', () {
      final fullJson = {
        'id': 'id123',
        'profileName': 'Test Profile',
        'type': 'github', // Assuming PasswordSourceType.github.name or your_to_string_method
        'gitProviderName': 'github',
        'repositoryId': 'repo789',
        'repositoryFullName': 'testuser/testrepo',
        'repositoryShortName': 'testrepo',
        'repositoryCloneUrl': 'https://github.com/testuser/testrepo.git',
        'repositoryDescription': 'A public test repo',
        'isPrivateRepository': false,
        'defaultBranch': 'main',
        'gpgUserName': 'test.user@example.com',
        'createdAt': testDateTimeIso,
        'accessTokenKey': 'access_token_key_example',
        'refreshTokenKey': 'refresh_token_key_example',
        'localPath': '/some/local/path',
      };

      final minimalJson = {
        'id': 'id_min',
        'profileName': 'Minimal Profile',
        'type': 'localFolder',
        'repositoryFullName': 'local_repo_name', // Still required
        'createdAt': testDateTimeIso,
        // All other optional fields are absent (null)
      };

      group('toJson()', () {
        test('should correctly serialize a full profile to JSON', () {
          final profile = PasswordRepositoryProfile(
            id: 'id123',
            profileName: 'Test Profile',
            type: PasswordSourceType.github,
            gitProviderName: 'github',
            repositoryId: 'repo789',
            repositoryFullName: 'testuser/testrepo',
            repositoryShortName: 'testrepo',
            repositoryCloneUrl: 'https://github.com/testuser/testrepo.git',
            repositoryDescription: 'A public test repo',
            isPrivateRepository: false,
            defaultBranch: 'main',
            gpgUserName: 'test.user@example.com',
            createdAt: testDateTime,
            accessTokenKey: 'access_token_key_example',
            refreshTokenKey: 'refresh_token_key_example',
            localPath: '/some/local/path',
          );
          expect(profile.toJson(), equals(fullJson));
        });

        test('should correctly serialize a minimal profile to JSON (nulls for optionals)', () {
          final profile = PasswordRepositoryProfile(
            id: 'id_min',
            profileName: 'Minimal Profile',
            type: PasswordSourceType.localFolder,
            repositoryFullName: 'local_repo_name',
            createdAt: testDateTime,
          );
          // Construct expected JSON carefully, including explicit nulls if toJson includes them
          final expectedMinimalJson = {
            'id': 'id_min',
            'profileName': 'Minimal Profile',
            'type': PasswordSourceType.passwordSourceTypeToString(PasswordSourceType.localFolder),
            'gitProviderName': null,
            'repositoryId': null,
            'repositoryFullName': 'local_repo_name',
            'repositoryShortName': null,
            'repositoryCloneUrl': null,
            'repositoryDescription': null,
            'isPrivateRepository': null,
            'defaultBranch': null,
            'gpgUserName': null,
            'createdAt': testDateTimeIso,
            'accessTokenKey': null,
            'refreshTokenKey': null,
            'localPath': null,
          };
          expect(profile.toJson(), equals(expectedMinimalJson));
        });
      });

      group('fromJson()', () {
        test('should correctly deserialize a full profile from JSON', () {
          final profile = PasswordRepositoryProfile.fromJson(fullJson);

          expect(profile.id, 'id123');
          expect(profile.profileName, 'Test Profile');
          expect(profile.type, PasswordSourceType.github);
          expect(profile.gitProviderName, 'github');
          expect(profile.repositoryId, 'repo789');
          expect(profile.repositoryFullName, 'testuser/testrepo');
          // ... (expect for all other fields)
          expect(profile.createdAt, testDateTime);
          expect(profile.localPath, '/some/local/path');
        });

        test('should correctly deserialize a minimal profile from JSON (optionals as null)', () {
          final profile = PasswordRepositoryProfile.fromJson(minimalJson);
          expect(profile.id, 'id_min');
          expect(profile.profileName, 'Minimal Profile');
          expect(profile.type, PasswordSourceType.localFolder);
          expect(profile.repositoryFullName, 'local_repo_name');
          expect(profile.createdAt, testDateTime);

          // Assert optional fields are null
          expect(profile.gitProviderName, isNull);
          expect(profile.repositoryId, isNull);
          // ... (check all other optional fields)
          expect(profile.localPath, isNull);
        });

        test('should throw an error if required field "id" is missing', () {
          final Map<String, dynamic> invalidJson = Map.from(minimalJson)..remove('id');
          expect(() => PasswordRepositoryProfile.fromJson(invalidJson), throwsA(isA<TypeError>())); // Or specific cast error
        });
        test('should throw an error if "type" cannot be parsed', () {
          final Map<String, dynamic> invalidJson = Map.from(minimalJson)..['type'] = 'invalid_type_value';
          // This depends on how passwordSourceTypeFromString handles errors.
          // If it throws, test for that. If it returns a default (like .unknown), test for that.
          // Assuming it might throw or result in .unknown which is then used.
          // For this test, let's assume passwordSourceTypeFromString returns .unknown for invalid strings
          final profile = PasswordRepositoryProfile.fromJson(invalidJson);
          expect(profile.type, PasswordSourceType.unknown);
        });
      });
    });

    group('Key Generation Static Methods', () {
      test('generateAccessTokenKey should return correct format', () {
        expect(PasswordRepositoryProfile.generateAccessTokenKey('profile123'),
            'profile_profile123_access_token');
      });

      test('generateRefreshTokenKey should return correct format', () {
        expect(PasswordRepositoryProfile.generateRefreshTokenKey('profileXYZ'),
            'profile_profileXYZ_refresh_token');
      });
    });

    group('copyWith()', () {
      late PasswordRepositoryProfile originalProfile;

      setUp(() {
        originalProfile = PasswordRepositoryProfile(
          id: 'orig-id',
          profileName: 'Original Name',
          type: PasswordSourceType.github,
          repositoryFullName: 'user/original-repo',
          gitProviderName: 'github',
          createdAt: testDateTime,
          localPath: '/original/path',
        );
      });

      test('should create an exact copy if no parameters are provided', () {
        final copy = originalProfile.copyWith();
        expect(copy.id, originalProfile.id);
        expect(copy.profileName, originalProfile.profileName);
        expect(copy.type, originalProfile.type);
        // ... (check all fields)
        expect(copy.localPath, originalProfile.localPath);
        expect(copy.createdAt, originalProfile.createdAt);
        expect(copy, isNot(same(originalProfile)));
      });

      test('should update only the profileName', () {
        final updated = originalProfile.copyWith(profileName: 'Updated Name');
        expect(updated.profileName, 'Updated Name');
        expect(updated.id, originalProfile.id); // Should remain unchanged
        expect(updated.type, originalProfile.type);
      });

      test('should update multiple fields correctly', () {
        final newTime = DateTime(2024, 5, 5);
        final updated = originalProfile.copyWith(
          type: PasswordSourceType.localFolder,
          repositoryFullName: 'user/new-repo',
          localPath: '/new/path',
          createdAt: newTime,
          isPrivateRepository: true,
        );
        expect(updated.type, PasswordSourceType.localFolder);
        expect(updated.repositoryFullName, 'user/new-repo');
        expect(updated.localPath, '/new/path');
        expect(updated.createdAt, newTime);
        expect(updated.isPrivateRepository, isTrue);
        expect(updated.profileName, originalProfile.profileName); // Unchanged
      });
    });

    group('isGitType()', () {
      test('should return true for GitHub type', () {
        final profile = PasswordRepositoryProfile(id: '1', profileName: 'p', type: PasswordSourceType.github, repositoryFullName: 'r');
        expect(profile.isGitType(), isTrue);
      });
      test('should return true for GitLab type', () {
        final profile = PasswordRepositoryProfile(id: '1', profileName: 'p', type: PasswordSourceType.gitlab, repositoryFullName: 'r');
        expect(profile.isGitType(), isTrue);
      });
      test('should return false for localFolder type', () {
        final profile = PasswordRepositoryProfile(id: '1', profileName: 'p', type: PasswordSourceType.localFolder, repositoryFullName: 'r');
        expect(profile.isGitType(), isFalse);
      });
      test('should return true for unknown type (as it is not localFolder)', () {
        // This depends on the definition of "Git type". If unknown is implicitly not local, then true.
        final profile = PasswordRepositoryProfile(id: '1', profileName: 'p', type: PasswordSourceType.unknown, repositoryFullName: 'r');
        expect(profile.isGitType(), isTrue);
      });
    });
  });
}