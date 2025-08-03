import 'dart:convert';
import 'dart:io' show ProcessResult;

import 'package:file/memory.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git/git.dart' show GitDir, GitError;
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:pass/models/git_repository_model.dart';
import 'package:pass/services/Git_services/git_service.dart';
import 'package:pass/services/git_services/process_runner.dart';

import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:path/path.dart' as p;

@GenerateMocks([
  FlutterSecureStorage,
  GitDir,
  IProcessRunner,
])
import 'git_service_test.mocks.dart';

class MockPathProviderPlatform extends Mock
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  String mockPath;

  MockPathProviderPlatform({this.mockPath = '/mock/documents'});

  @override
  Future<String?> getApplicationDocumentsPath() async {
    return mockPath;
  }

  @override
  Future<String?> getTemporaryPath() async => p.join(mockPath, 'temp');

  @override
  Future<String?> getApplicationSupportPath() async => p.join(mockPath, 'support');

}

ProcessResult mockProcessResult(int exitCode, String stdout, String stderr) {
  return ProcessResult(0, exitCode, stdout, stderr);
}

void main() {
  late GitService gitService;
  late MockFlutterSecureStorage mockSecureStorage;
  late MockIProcessRunner mockProcessRunner;
  late MockGitDir mockGitDir;
  late MemoryFileSystem memoryFileSystem;
  late MockPathProviderPlatform mockPathProviderPlatform;

  const String testProfileId = 'test_profile';
  const String testRepoName = 'test-repo';
  const String testRepoHtmlUrl = 'https://example.com/git/test-repo.git';
  const String testAccessToken = 'test_token';
  const String appDocsPath = '/mock_app_docs';
  final String reposBasePath = p.join(appDocsPath, 'repos');
  final String mockRepoPath = p.join(reposBasePath, testRepoName);


  setUp(() {
    mockSecureStorage = MockFlutterSecureStorage();
    mockProcessRunner = MockIProcessRunner();
    mockGitDir = MockGitDir();
    memoryFileSystem = MemoryFileSystem();

    mockPathProviderPlatform = MockPathProviderPlatform(mockPath: appDocsPath);
    PathProviderPlatform.instance = mockPathProviderPlatform;
    memoryFileSystem.directory(appDocsPath).createSync(recursive: true);


    gitService = GitService(
      secureStorage: mockSecureStorage,
      fileSystem: memoryFileSystem,
      processRunner: mockProcessRunner,
      gitDirFactory: (String path) async {
        return mockGitDir;
      },
    );

    when(mockSecureStorage.read(key: anyNamed('key'))).thenAnswer((_) async => null);
    when(mockSecureStorage.write(key: anyNamed('key'), value: anyNamed('value'))).thenAnswer((_) async {});

    when(mockGitDir.runCommand(any)).thenAnswer((_) async => mockProcessResult(0, '', ''));

    when(mockProcessRunner.run(any, any,
        workingDirectory: anyNamed('workingDirectory')))
        .thenAnswer((_) async => mockProcessResult(0, '', ''));
  });

  final testGitRepositoryModel = GitRepository(
    id: '1',
    name: testRepoName,
    htmlUrl: testRepoHtmlUrl,
    description: 'Test repository description',
    defaultBranch: 'main',
    isPrivate: false,
    providerName: 'github'
  );

  group('cloneRepository', () {
    setUp(() {
      memoryFileSystem.directory(reposBasePath).createSync(recursive: true);
    });

    test('successfully clones repository if it does not exist', () async {
      // Arrange
      when(mockSecureStorage.read(key: 'profile_${testProfileId}_access_token'))
          .thenAnswer((_) async => testAccessToken);

      final expectedAuthUrl = testRepoHtmlUrl.replaceFirst('https://', 'https://oauth2:$testAccessToken@');
      when(mockProcessRunner.run(
        'git',
        ['clone', expectedAuthUrl, testRepoName],
        workingDirectory: reposBasePath,
      )).thenAnswer((invocation) async {
        memoryFileSystem.directory(mockRepoPath).createSync(recursive: true);
        return mockProcessResult(0, 'Cloned successfully', '');
      });

      when(mockGitDir.runCommand(['config', 'user.name', GitService.gitConfigName]))
          .thenAnswer((_) async => mockProcessResult(0, '', ''));
      when(mockGitDir.runCommand(['config', 'user.email', GitService.gitConfigEmail]))
          .thenAnswer((_) async => mockProcessResult(0, '', ''));

      // Act
      final resultPath = await gitService.cloneRepository(testGitRepositoryModel, testProfileId);

      // Assert
      expect(resultPath, equals(mockRepoPath));
      expect(memoryFileSystem.directory(mockRepoPath).existsSync(), isTrue);

      verify(mockSecureStorage.read(key: 'profile_${testProfileId}_access_token')).called(1);
      verify(mockProcessRunner.run(
        'git',
        ['clone', expectedAuthUrl, testRepoName],
        workingDirectory: reposBasePath,
      )).called(1);
      verify(mockGitDir.runCommand(['config', 'user.name', GitService.gitConfigName])).called(1);
      verify(mockGitDir.runCommand(['config', 'user.email', GitService.gitConfigEmail])).called(1);
    });



    test('returns path if repository directory already exists', () async {
      // Arrange
      memoryFileSystem.directory(mockRepoPath).createSync(recursive: true);

      // Act
      final resultPath = await gitService.cloneRepository(testGitRepositoryModel, testProfileId);

      // Assert
      expect(resultPath, equals(mockRepoPath));
      verifyNever(mockSecureStorage.read(key: anyNamed('key')));
      verifyNever(mockProcessRunner.run(any, any, workingDirectory: anyNamed('workingDirectory')));
    });

    test('throws exception if access token is not found', () async {
      // Arrange
      when(mockSecureStorage.read(key: 'profile_${testProfileId}_access_token'))
          .thenAnswer((_) async => null);

      // Act & Assert
      expect(
            () => gitService.cloneRepository(testGitRepositoryModel, testProfileId),
        throwsA(isA<Exception>().having(
                (e) => e.toString(), 'message', contains('No access token found for profile $testProfileId'))),
      );
      verifyNever(mockSecureStorage.read(key: 'profile_${testProfileId}_access_token'));
      verifyNever(mockProcessRunner.run(any, any, workingDirectory: anyNamed('workingDirectory')));
    });

    test('throws exception if git clone fails', () async {
      // Arrange
      when(mockSecureStorage.read(key: 'profile_${testProfileId}_access_token'))
          .thenAnswer((_) async => testAccessToken);
      final expectedAuthUrl = testRepoHtmlUrl.replaceFirst('https://', 'https://oauth2:$testAccessToken@');
      when(mockProcessRunner.run(
        'git',
        ['clone', expectedAuthUrl, testRepoName],
        workingDirectory: reposBasePath,
      )).thenAnswer((_) async => mockProcessResult(1, '', 'Git clone error'));

      // Act & Assert
      expect(
            () => gitService.cloneRepository(testGitRepositoryModel, testProfileId),
        throwsA(isA<Exception>().having(
                (e) => e.toString(), 'message', contains('Failed to clone repository: Git clone error'))),
      );
    });
  });

  group('_getRepository (tested implicitly via other methods)', () {
    test('throws if directory does not exist when getting repository', () async {
      // Arrange

      // Act & Assert
      expect(
            () => gitService.pullChanges(mockRepoPath),
        throwsA(isA<Exception>().having(
                (e) => e.toString(), 'message', contains('Repository directory does not exist: $mockRepoPath'))),
      );
    });

    test('_getRepository caches the repository instance', () async {
      // Arrange
      memoryFileSystem.directory(mockRepoPath).createSync(recursive: true);

      // Act
      await gitService.pullChanges(mockRepoPath);
      await gitService.pullChanges(mockRepoPath);

      // Assert
      verify(mockGitDir.runCommand(['pull'])).called(2);
    });
  });


  group('pullChanges', () {
    setUp(() {
      memoryFileSystem.directory(mockRepoPath).createSync(recursive: true);
    });

    test('successfully pulls changes', () async {
      // Arrange
      when(mockGitDir.runCommand(['pull'])).thenAnswer((_) async => mockProcessResult(0, 'Pulled successfully', ''));

      // Act
      await gitService.pullChanges(mockRepoPath);

      // Assert
      verify(mockGitDir.runCommand(['pull'])).called(1);
    });

    test('throws exception on pull failure', () async {
      // Arrange
      final gitErrorMessage = 'Pull operation failed from mock';
      final simulatedGitError = GitError(gitErrorMessage); // GitError из package:git
      when(mockGitDir.runCommand(['pull'])).thenThrow(simulatedGitError);

      // Act
      final future = gitService.pullChanges(mockRepoPath);

      // Assert
      await expectLater(
        future,
        throwsA(isA<Exception>().having(
              (e) => e.toString(),
          'message',
          contains('Failed to pull changes: $gitErrorMessage'),
        )),
      );
    });
  });

  group('pushChanges', () {
    setUp(() {
      memoryFileSystem.directory(mockRepoPath).createSync(recursive: true);
    });

    test('successfully adds, commits, and pushes if changes exist', () async {
      // Arrange
      when(mockGitDir.runCommand(['add', '.'])).thenAnswer((_) async => mockProcessResult(0, '', ''));
      when(mockGitDir.runCommand(['status', '--porcelain'])).thenAnswer((_) async => mockProcessResult(0, 'M  file.txt', ''));
      when(mockGitDir.runCommand(['commit', '-m', 'Test commit'])).thenAnswer((_) async => mockProcessResult(0, '', ''));
      when(mockGitDir.runCommand(['push', 'origin', 'HEAD'])).thenAnswer((_) async => mockProcessResult(0, '', ''));

      // Act
      await gitService.pushChanges(mockRepoPath, 'Test commit');

      // Assert
      verifyInOrder([
        mockGitDir.runCommand(['add', '.']),
        mockGitDir.runCommand(['status', '--porcelain']),
        mockGitDir.runCommand(['commit', '-m', 'Test commit']),
        mockGitDir.runCommand(['push', 'origin', 'HEAD']),
      ]);
    });

    test('does nothing if no changes to commit', () async {
      // Arrange
      when(mockGitDir.runCommand(['add', '.'])).thenAnswer((_) async => mockProcessResult(0, '', ''));
      when(mockGitDir.runCommand(['status', '--porcelain'])).thenAnswer((_) async => mockProcessResult(0, '', ''));

      // Act
      await gitService.pushChanges(mockRepoPath, 'Test commit');

      // Assert
      verify(mockGitDir.runCommand(['add', '.'])).called(1);
      verify(mockGitDir.runCommand(['status', '--porcelain'])).called(1);
      verifyNever(mockGitDir.runCommand(argThat(contains('commit'))));
      verifyNever(mockGitDir.runCommand(argThat(contains('push'))));
    });

    test('throws exception if push fails', () async {
      // Arrange
      when(mockGitDir.runCommand(['add', '.'])).thenAnswer((_) async => mockProcessResult(0, '', ''));
      when(mockGitDir.runCommand(['status', '--porcelain'])).thenAnswer((_) async => mockProcessResult(0, 'M  file.txt', ''));
      when(mockGitDir.runCommand(['commit', '-m', 'Test commit'])).thenAnswer((_) async => mockProcessResult(0, '', ''));
      when(mockGitDir.runCommand(['push', 'origin', 'HEAD'])).thenAnswer((_) async => mockProcessResult(1, '', 'Push error'));

      // Act & Assert
      expect(
            () => gitService.pushChanges(mockRepoPath, 'Test commit'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Failed to push changes: Push error'))),
      );
    });

    test('throws GitError if git operation fails (e.g. commit)', () async {
      // Arrange
      when(mockGitDir.runCommand(['add', '.'])).thenAnswer((_) async => mockProcessResult(0, '', ''));
      when(mockGitDir.runCommand(['status', '--porcelain'])).thenAnswer((_) async => mockProcessResult(0, 'M  file.txt', ''));
      when(mockGitDir.runCommand(['commit', '-m', 'Test commit'])).thenThrow(GitError('Commit failed'));

      // Act & Assert
      expect(
            () => gitService.pushChanges(mockRepoPath, 'Test commit'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Git operation failed: Commit failed'))),
      );
    });
  });

  group('getRepoStatus', () {
    setUp(() {
      memoryFileSystem.directory(mockRepoPath).createSync(recursive: true);
    });

    test('returns correct status map', () async {
      // Arrange
      final commitData = {
        "hash": "abcdef123456",
        "author": "Test User <test@example.com>",
        "date": "2023-10-27T10:00:00Z",
        "message": "feat: amazing new feature"
      };
      final commitJson = json.encode(commitData);

      when(mockGitDir.runCommand(['branch', '--show-current'])).thenAnswer((_) async => mockProcessResult(0, 'main', ''));
      when(mockGitDir.runCommand(['status', '--porcelain'])).thenAnswer((_) async => mockProcessResult(0, ' M modified_file.txt', ''));
      when(mockGitDir.runCommand(['ls-files', '--others', '--exclude-standard'])).thenAnswer((_) async => mockProcessResult(0, 'untracked_file.txt', ''));
      when(mockGitDir.runCommand(['rev-list', '--count', '--left-right', 'HEAD...@{u}'])).thenAnswer((_) async => mockProcessResult(0, '1\t2', '')); // 1 behind, 2 ahead
      when(mockGitDir.runCommand(argThat(contains('log')))).thenAnswer((_) async => mockProcessResult(0, commitJson, ''));

      // Act
      final status = await gitService.getRepoStatus(mockRepoPath);

      // Assert
      expect(status['currentBranch'], 'main');
      expect(status['hasUncommittedChanges'], isTrue);
      expect(status['hasUntrackedFiles'], isTrue);
      expect(status['behind'], 1);
      expect(status['ahead'], 2);
      expect(status['lastCommit'], isA<Map<String, dynamic>>());
      expect(status['lastCommit']['hash'], commitData['hash']);
      expect(status['lastCommit']['message'], commitData['message']);

      verify(mockGitDir.runCommand(['branch', '--show-current'])).called(1);
    });

    test('handles missing upstream for ahead/behind counts', () async {
      // Arrange
      when(mockGitDir.runCommand(['branch', '--show-current'])).thenAnswer((_) async => mockProcessResult(0, 'main', ''));
      when(mockGitDir.runCommand(['status', '--porcelain'])).thenAnswer((_) async => mockProcessResult(0, '', ''));
      when(mockGitDir.runCommand(['ls-files', '--others', '--exclude-standard'])).thenAnswer((_) async => mockProcessResult(0, '', ''));
      when(mockGitDir.runCommand(['rev-list', '--count', '--left-right', 'HEAD...@{u}'])).thenThrow(Exception("No upstream"));
      when(mockGitDir.runCommand(argThat(contains('log')))).thenAnswer((_) async => mockProcessResult(0, '{}', ''));

      // Act
      final status = await gitService.getRepoStatus(mockRepoPath);

      // Assert
      expect(status['ahead'], 0);
      expect(status['behind'], 0);
    });

    test('handles error parsing last commit JSON', () async {
      // Arrange
      when(mockGitDir.runCommand(['branch', '--show-current'])).thenAnswer((_) async => mockProcessResult(0, 'main', ''));
      when(mockGitDir.runCommand(['status', '--porcelain'])).thenAnswer((_) async => mockProcessResult(0, '', ''));
      when(mockGitDir.runCommand(['ls-files', '--others', '--exclude-standard'])).thenAnswer((_) async => mockProcessResult(0, '', ''));
      when(mockGitDir.runCommand(['rev-list', '--count', '--left-right', 'HEAD...@{u}'])).thenAnswer((_) async => mockProcessResult(0, '0\t0', ''));
      when(mockGitDir.runCommand(argThat(contains('log')))).thenAnswer((_) async => mockProcessResult(0, 'invalid json', ''));

      // Act
      final status = await gitService.getRepoStatus(mockRepoPath);

      // Assert
      expect(status['lastCommit'], isEmpty);
    });
  });

  group('createBranch', () {
    setUp(() {
      memoryFileSystem.directory(mockRepoPath).createSync(recursive: true);
    });
    test('successfully creates a new branch', () async {
      // Arrange
      const newBranchName = 'feature/new-idea';
      when(mockGitDir.runCommand(['checkout', '-b', newBranchName])).thenAnswer((_) async => mockProcessResult(0, '', ''));

      // Act
      await gitService.createBranch(mockRepoPath, newBranchName);

      // Assert
      verify(mockGitDir.runCommand(['checkout', '-b', newBranchName])).called(1);
    });

    test('throws exception on createBranch failure', () async {
      // Arrange
      const newBranchName = 'feature/new-idea';
      final gitErrorMessage = 'Create branch failed from mock';
      final simulatedGitError = GitError(gitErrorMessage);
      when(mockGitDir.runCommand(['checkout', '-b', newBranchName]))
          .thenThrow(simulatedGitError);

      //Act
      final future = gitService.createBranch(mockRepoPath, newBranchName);

      await expectLater(
        future,
        throwsA(isA<Exception>().having(
              (e) => e.toString(),
          'message',
          contains('Failed to create branch: $gitErrorMessage'),
        )),
      );
    });
  });

  group('switchBranch', () {
    setUp(() {
      memoryFileSystem.directory(mockRepoPath).createSync(recursive: true);
    });
    test('successfully switches to an existing branch', () async {
      // Arrange
      const targetBranchName = 'main';
      when(mockGitDir.runCommand(['checkout', targetBranchName])).thenAnswer((_) async => mockProcessResult(0, '', ''));

      // Act
      await gitService.switchBranch(mockRepoPath, targetBranchName);

      // Assert
      verify(mockGitDir.runCommand(['checkout', targetBranchName])).called(1);
    });

    test('throws exception on switchBranch failure', () async {
      // Arrange
      const targetBranchName = 'non-existent-branch';
      final gitErrorMessage = 'Switch branch failed from mock';
      final simulatedGitError = GitError(gitErrorMessage);
      when(mockGitDir.runCommand(['checkout', targetBranchName])).thenThrow(simulatedGitError);

      // Act
      final future = gitService.switchBranch(mockRepoPath, targetBranchName);

      await expectLater(
        future,
        throwsA(isA<Exception>().having(
              (e) => e.toString(),
          'message',
          contains('Failed to switch branch: $gitErrorMessage'),
        )),
      );
    });
  });
}


