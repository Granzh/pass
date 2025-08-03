import 'dart:convert';
import 'dart:async';
import 'package:file/file.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pass/services/git_services/process_runner.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:git/git.dart';
import '../../models/git_repository_model.dart';
import 'package:logging/logging.dart';
import 'git_dir_factory.dart';

class GitService {
  static const String _gitConfigName = 'Pass App';
  static const String _gitConfigEmail = 'pass@app.local';

  static String get gitConfigName => _gitConfigName;
  static String get gitConfigEmail => _gitConfigEmail;

  static final _log = Logger('GitService');

  GitDir? _repository;

  final FlutterSecureStorage _secureStorage;
  final IProcessRunner _processRunner;
  final GitDirFactory _gitDirFactory;
  final FileSystem _fileSystem;

  GitService({
    required FlutterSecureStorage secureStorage,
    required FileSystem fileSystem,
    IProcessRunner? processRunner,
    GitDirFactory? gitDirFactory,
  })  : _secureStorage = secureStorage,
        _fileSystem = fileSystem,
        _processRunner = processRunner ?? ProcessRunner(),
        _gitDirFactory = gitDirFactory ?? defaultGitDirFactory;

  /// Gets or initializes a Git repository
  Future<GitDir> _getRepository(String repoPath) async {
    if (_repository != null) return _repository!;

    final dir = _fileSystem.directory(repoPath);
    if (!await dir.exists()) {
      _log.severe('Repository directory does not exist: $repoPath');
      throw Exception('Repository directory does not exist: $repoPath');
    }

    _repository = await _gitDirFactory(repoPath);
    return _repository!;
  }

  /// Clones a Git repository to a local directory
  Future<String> cloneRepository(GitRepository repository, String profileId) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();

      final reposDir = _fileSystem.directory(path.join(appDir.path, 'repos'));
      if (!await reposDir.exists()) {
        await reposDir.create(recursive: true);
      }

      final repoDir = _fileSystem.directory(path.join(reposDir.path, repository.name));
      if (await repoDir.exists()) {
        return repoDir.path;
      }

      final token = await _secureStorage.read(key: 'profile_${profileId}_access_token');
      if (token == null) {
        _log.severe('No access token found for profile $profileId');
        throw Exception('No access token found for profile $profileId');
      }

      final authUrl = repository.htmlUrl.replaceFirst('https://', 'https://oauth2:$token@');

      final result = await _processRunner.run(
        'git',
        ['clone', authUrl, repository.name],
        workingDirectory: reposDir.path,
      );

      if (result.exitCode != 0) {
        _log.severe('Failed to clone repository: ${result.stderr} (stdout: ${result.stdout})');
        throw Exception('Failed to clone repository: ${result.stderr} (stdout: ${result.stdout})');
      }

      _repository = await _gitDirFactory(repoDir.path);

      await _repository!.runCommand(['config', 'user.name', _gitConfigName]);
      await _repository!.runCommand(['config', 'user.email', _gitConfigEmail]);

      return repoDir.path;
    } catch (e) {
      _log.severe('Failed to clone repository: $e');
      throw Exception('Failed to clone repository (original error: $e)');
    }
  }

  Future<void> pullChanges(String repoPath) async {
    try {
      final repo = await _getRepository(repoPath);
      await repo.runCommand(['pull']);
    } catch (e) {
      _log.severe('Failed to pull changes: $e');
      throw Exception('Failed to pull changes: $e');
    }
  }

  Future<void> pushChanges(String repoPath, String commitMessage) async {
    try {
      final repo = await _getRepository(repoPath);
      await repo.runCommand(['add', '.']);
      final statusOutput = await repo.runCommand(['status', '--porcelain']);
      if (statusOutput.stdout.toString().trim().isEmpty) {
        return;
      }
      await repo.runCommand(['commit', '-m', commitMessage]);
      final pushResult = await repo.runCommand(['push', 'origin', 'HEAD']);
      if (pushResult.exitCode != 0) {
        throw Exception('Failed to push changes: ${pushResult.stderr}');
      }
    } on GitError catch (e) {
      _log.severe('Git operation failed: ${e.message}');
      throw Exception('Git operation failed: ${e.message}');
    } catch (e) {
      _log.severe('Failed to push changes: $e');
      throw Exception('Failed to push changes: $e');
    }
  }

  Future<Map<String, dynamic>> getRepoStatus(String repoPath) async {
    try {
      final repo = await _getRepository(repoPath);
      final branchResult = await repo.runCommand(['branch', '--show-current']);
      final currentBranch = branchResult.stdout.toString().trim();
      final statusResult = await repo.runCommand(['status', '--porcelain']);
      final hasUncommittedChanges = statusResult.stdout.toString().trim().isNotEmpty;
      final untrackedResult = await repo.runCommand(['ls-files', '--others', '--exclude-standard']);
      final hasUntrackedFiles = untrackedResult.stdout.toString().trim().isNotEmpty;

      int ahead = 0;
      int behind = 0;
      try {
        final trackingResult = await repo.runCommand(['rev-list', '--count', '--left-right', 'HEAD...@{u}']);
        final counts = trackingResult.stdout.toString().trim().split('\t');
        if (counts.length == 2) {
          behind = int.tryParse(counts[0]) ?? 0;
          ahead = int.tryParse(counts[1]) ?? 0;
        }
      } catch (e) {
        _log.severe('Failed to get tracking information: $e');
      }

      final lastCommitResult = await repo.runCommand([
        'log', '-1', '--pretty=format:{"hash":"%H","author":"%an <%ae>","date":"%ad","message":"%s"}', '--date=iso'
      ]);
      Map<String, dynamic> lastCommit = {};
      try {
        lastCommit = Map<String, dynamic>.from(
            json.decode(lastCommitResult.stdout.toString().trim()) as Map);
      } catch (e) {
        _log.severe('Failed to parse last commit information: $e');
      }

      return {
        'currentBranch': currentBranch,
        'hasUncommittedChanges': hasUncommittedChanges,
        'hasUntrackedFiles': hasUntrackedFiles,
        'ahead': ahead,
        'behind': behind,
        'lastCommit': lastCommit,
      };
    } on GitError catch (e) {
      _log.severe('Git operation failed: ${e.message}');
      throw Exception('Git operation failed: ${e.message}');
    } catch (e) {
      _log.severe('Failed to get repository status: $e');
      throw Exception('Failed to get repository status: $e');
    }
  }

  Future<void> createBranch(String repoPath, String branchName) async {
    try {
      final repo = await _getRepository(repoPath);
      await repo.runCommand(['checkout', '-b', branchName]);
    } catch (e) {
      _log.severe('Failed to create branch: $e');
      throw Exception('Failed to create branch: $e');
    }
  }

  Future<void> switchBranch(String repoPath, String branchName) async {
    try {
      final repo = await _getRepository(repoPath);
      await repo.runCommand(['checkout', branchName]);
    } catch (e) {
      _log.severe('Failed to switch branch: $e');
      throw Exception('Failed to switch branch: $e');
    }
  }
}
