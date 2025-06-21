import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:git/git.dart';
import '../logic/secure_storage.dart';
import '../models/git_repository_model.dart';

class GitService {
  static const String _gitConfigName = 'Pass App';
  static const String _gitConfigEmail = 'pass@app.local';
  GitDir? _repository;

  GitService();

  /// Gets or initializes a Git repository
  Future<GitDir> _getRepository(String repoPath) async {
    if (_repository != null) return _repository!;
    
    final dir = Directory(repoPath);
    if (!await dir.exists()) {
      throw Exception('Repository directory does not exist');
    }
    
    _repository = await GitDir.fromExisting(repoPath);
    return _repository!;
  }

  /// Clones a Git repository to a local directory
  Future<String> cloneRepository(GitRepository repository, String profileId) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final reposDir = Directory(path.join(appDir.path, 'repos'));
      if (!await reposDir.exists()) {
        await reposDir.create(recursive: true);
      }
      
      final repoDir = Directory(path.join(reposDir.path, repository.name));
      if (await repoDir.exists()) {
        return repoDir.path;
      }

      // Get credentials from secure storage
      final token = await secureStorage.read(key: 'profile_${profileId}_access_token');
      if (token == null) {
        throw Exception('No access token found');
      }

      // Construct authenticated URL
      final authUrl = repository.htmlUrl
          .replaceFirst('https://', 'https://oauth2:$token@');

      // Clone repository using git command
      final result = await Process.run(
        'git',
        ['clone', authUrl, repository.name],
        workingDirectory: reposDir.path,
      );

      if (result.exitCode != 0) {
        throw Exception('Failed to clone repository: ${result.stderr}');
      }

      // Load the repository
      _repository = await GitDir.fromExisting(repoDir.path);
      
      // Configure git user
      await _repository!.runCommand(['config', 'user.name', _gitConfigName]);
      await _repository!.runCommand(['config', 'user.email', _gitConfigEmail]);

      return repoDir.path;
    } catch (e) {
      throw Exception('Failed to clone repository: $e');
    }
  }

  /// Pulls the latest changes from the remote repository
  Future<void> pullChanges(String repoPath) async {
    try {
      final repo = await _getRepository(repoPath);
      await repo.runCommand(['pull']);
    } catch (e) {
      throw Exception('Failed to pull changes: $e');
    }
  }

  /// Commits and pushes changes to the remote repository
  Future<void> pushChanges(String repoPath, String commitMessage) async {
    try {
      final repo = await _getRepository(repoPath);
      
      // Add all changes
      await repo.runCommand(['add', '.']);
      
      // Check if there are any changes to commit
      final statusOutput = await repo.runCommand(['status', '--porcelain']);
      if (statusOutput.stdout.trim().isEmpty) {
        return; // No changes to commit
      }
      
      // Commit changes
      await repo.runCommand(['commit', '-m', commitMessage]);
      
      // Push changes to the remote repository
      final pushResult = await repo.runCommand(['push', 'origin', 'HEAD']);
      
      if (pushResult.exitCode != 0) {
        throw Exception('Failed to push changes: ${pushResult.stderr}');
      }
    } on GitError catch (e) {
      throw Exception('Git operation failed: ${e.message}');
    } catch (e) {
      throw Exception('Failed to push changes: $e');
    }
  }

  /// Gets the current status of the repository
  /// Returns a map containing:
  /// - currentBranch: The name of the current branch
  /// - hasUncommittedChanges: Boolean indicating if there are uncommitted changes
  /// - hasUntrackedFiles: Boolean indicating if there are untracked files
  /// - ahead: Number of commits ahead of remote
  /// - behind: Number of commits behind remote
  /// - lastCommit: Information about the most recent commit
  Future<Map<String, dynamic>> getRepoStatus(String repoPath) async {
    try {
      final repo = await _getRepository(repoPath);
      
      // Get current branch
      final branchResult = await repo.runCommand(['branch', '--show-current']);
      final currentBranch = branchResult.stdout.toString().trim();
      
      // Check for uncommitted changes
      final statusResult = await repo.runCommand(['status', '--porcelain']);
      final hasUncommittedChanges = statusResult.stdout.toString().trim().isNotEmpty;
      
      // Check for untracked files
      final untrackedResult = await repo.runCommand(['ls-files', '--others', '--exclude-standard']);
      final hasUntrackedFiles = untrackedResult.stdout.toString().trim().isNotEmpty;
      
      // Get ahead/behind information
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
        // If there's no upstream branch, we'll get an error which we can ignore
      }
      
      // Get last commit info
      final lastCommitResult = await repo.runCommand([
        'log',
        '-1',
        '--pretty=format:{"hash":"%H","author":"%an <%ae>","date":"%ad","message":"%s"}',
        '--date=iso'
      ]);
      
      Map<String, dynamic> lastCommit = {};
      try {
        lastCommit = Map<String, dynamic>.from(
          Map.castFrom<dynamic, dynamic, String, dynamic>(
            const JsonDecoder().convert(lastCommitResult.stdout.toString().trim())
          )
        );
      } catch (e) {
        // If we can't parse the commit info, continue without it
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
      throw Exception('Git operation failed: ${e.message}');
    } catch (e) {
      throw Exception('Failed to get repository status: $e');
    }
  }

  /// Creates a new branch
  Future<void> createBranch(String repoPath, String branchName) async {
    try {
      final repo = await _getRepository(repoPath);
      await repo.runCommand(['checkout', '-b', branchName]);
    } catch (e) {
      throw Exception('Failed to create branch: $e');
    }
  }

  /// Switches to an existing branch
  Future<void> switchBranch(String repoPath, String branchName) async {
    try {
      final repo = await _getRepository(repoPath);
      await repo.runCommand(['checkout', branchName]);
    } catch (e) {
      throw Exception('Failed to switch branch: $e');
    }
  }


}
