import 'dart:convert';



import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:pass/models/password_repository_profile.dart';
import 'package:pass/services/git_service.dart';
import 'package:pass/services/gpg_key_service.dart';
import 'package:pass/services/password_repository_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

// Mock classes
class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}
class MockGPGService extends Mock implements GPGService {}
class MockGitService extends Mock implements GitService {}

// Mock path provider
class MockPathProviderPlatform extends Mock implements PathProviderPlatform {
  @override
  Future<String> getApplicationDocumentsPath() async {
    return 'test/path';
  }
}

@GenerateMocks([MockFlutterSecureStorage, MockGPGService, MockGitService])
void main() {
  late PasswordRepositoryService service;
  late MockFlutterSecureStorage mockStorage;
  late MockGPGService mockGPGService;
  late MockGitService mockGitService;
  final mockPathProvider = MockPathProviderPlatform();

  setUpAll(() {
    PathProviderPlatform.instance = mockPathProvider;
  });

  setUp(() {
    mockStorage = MockFlutterSecureStorage();
    mockGPGService = MockGPGService();
    mockGitService = MockGitService();
    
    service = PasswordRepositoryService.test(
      secureStorage: mockStorage,
      gpgService: mockGPGService,
      gitService: mockGitService,
    );
  });

  group('PasswordRepositoryService', () {
    final testProfile = PasswordRepositoryProfile(
      id: 'test-id',
      profileName: 'Test Profile',
      type: PasswordSourceType.github,
      gitProviderName: 'github',
      repositoryId: '123',
      repositoryFullName: 'test/repo',
      defaultBranch: 'main',
    );

    test('getProfiles returns empty list when no profiles exist', () async {
      // Arrange
      when(mockStorage.read(key: 'password_repository_profiles'))
          .thenAnswer((_) async => null);

      // Act
      final profiles = service.getProfiles();

      // Assert
      expect(profiles, isEmpty);
    });

    test('addRepository adds a new repository profile', () async {
      // Arrange
      when(mockStorage.read(key: 'password_repository_profiles'))
          .thenAnswer((_) async => null);
      when(mockStorage.write(
        key: 'password_repository_profiles',
        value: anyNamed('value'),
      )).thenAnswer((_) async => Future.value());
      when(mockStorage.write(
        key: 'active_profile_id',
        value: anyNamed('value'),
      )).thenAnswer((_) async => Future.value());

      // Act
      final profile = await service.addRepository(
        name: 'Test Repo',
        type: PasswordSourceType.github,
        repositoryFullName: 'test/repo',
      );

      // Assert
      expect(profile.profileName, 'Test Repo');
      expect(profile.type, PasswordSourceType.github);
      expect(profile.repositoryFullName, 'test/repo');
      verify(mockStorage.write(
        key: 'password_repository_profiles',
        value: anyNamed('value'),
      )).called(1);
    });

    test('getRepositoryPath returns correct path', () async {
      // Act
      final path = await service.getRepositoryPath('test-id');
      
      // Assert
      expect(path, 'test/path/repositories/test-id');
    });

    test('setActiveProfile updates active profile ID', () async {
      // Arrange
      when(mockStorage.write(
        key: 'active_profile_id',
        value: 'test-id',
      )).thenAnswer((_) async => Future.value());

      // Act
      await service.setActiveProfile('test-id');

      // Assert
      verify(mockStorage.write(
        key: 'active_profile_id',
        value: 'test-id',
      )).called(1);
    });

    test('removeRepository removes the repository and cleans up', () async {
      // Arrange
      when(mockStorage.read(key: 'password_repository_profiles'))
          .thenAnswer((_) async => jsonEncode([testProfile.toJson()]));
      when(mockStorage.write(
        key: 'password_repository_profiles',
        value: anyNamed('value'),
      )).thenAnswer((_) async => Future.value());
      when(mockStorage.delete(key: 'any_key'))
          .thenAnswer((_) async => '');
      when(mockGPGService.getKeyForProfileById('test-id'))
          .thenAnswer((_) async => null);

      // Act
      await service.removeRepository('test-id');

      // Assert
      verify(mockStorage.write(
        key: 'password_repository_profiles',
        value: '[]',
      )).called(1);
    });

    test('updateRepository updates the repository profile', () async {
      // Arrange
      when(mockStorage.read(key: 'password_repository_profiles'))
          .thenAnswer((_) async => jsonEncode([testProfile.toJson()]));
      when(mockStorage.write(
        key: 'password_repository_profiles',
        value: anyNamed('value'),
      )).thenAnswer((_) async => Future.value());

      // Act
      final updatedProfile = await service.updateRepository(
        id: 'test-id',
        name: 'Updated Name',
      );

      // Assert
      expect(updatedProfile.profileName, 'Updated Name');
      verify(mockStorage.write(
        key: 'password_repository_profiles',
        value: anyNamed('value'),
      )).called(1);
    });

    test('syncRepository creates directory for local folder', () async {
      // Arrange
      when(mockStorage.read(key: 'password_repository_profiles'))
          .thenAnswer((_) async => jsonEncode([
                PasswordRepositoryProfile(
                  id: 'local-id',
                  profileName: 'Local',
                  type: PasswordSourceType.localFolder,
                  repositoryFullName: 'local',
                ).toJson()
              ]));

      // Act & Assert
      await expectLater(
        service.syncRepository('local-id'),
        completes,
      );
    });
  });
}
