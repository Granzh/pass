import 'dart:io';

import 'package:logging/logging.dart';
import 'package:pass/models/git_repository_model.dart';
import 'package:pass/models/password_repository_profile.dart';
import 'package:pass/services/profile_services/repository_profile_manager.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../core/utils/enums.dart';
import 'git_service.dart';

class GitOrchestrator {
  final RepositoryProfileManager _profileManager;
  final GitService _gitService;
  static final _log = Logger('GitOrchestrator');

  GitOrchestrator({
    required RepositoryProfileManager profileManager,
    required GitService gitService,
  })  : _profileManager = profileManager,
        _gitService = gitService;

  Future<void> initializeRepositoryForProfile({
    required PasswordRepositoryProfile profile,
    GitRepository? gitRepoInfo,
    String? explicitLocalFolderPath,
  }) async {
    _log.info('Initializing repository for profile ${profile.id} (${profile.profileName})');

    if (profile.type == PasswordSourceType.localFolder) {
      String localPath = explicitLocalFolderPath ?? await _getDefaultLocalFolderPath(profile.id, profile.profileName);
      final repoDir = Directory(localPath);

      if (await repoDir.exists()) {
        _log.info('Local folder directory already exists at $localPath. Skipping creation.');
      } else {
        _log.info('Creating local folder: $localPath');
        await repoDir.create(recursive: true);
      }
      if (profile.localPath != localPath) {
        final updatedProfile = profile.copyWith(localPath: localPath);
        await _profileManager.updateProfile(profile.id, updatedProfile);
        _log.fine('Updated profile ${profile.id} with localPath: $localPath');
      }
      return;
    }

    if (profile.type == PasswordSourceType.github || profile.type == PasswordSourceType.gitlab) {
      final GitRepository repoToClone;

      if (gitRepoInfo != null) {
        repoToClone = gitRepoInfo;
      } else {
        if (profile.repositoryCloneUrl == null || profile.repositoryCloneUrl!.isEmpty) {
          _log.severe('Profile ${profile.id} is missing repositoryCloneUrl for cloning.');
          throw ArgumentError('Profile is missing repositoryCloneUrl.');
        }
        if (profile.repositoryShortName == null || profile.repositoryShortName!.isEmpty) {
          _log.severe('Profile ${profile.id} is missing repositoryShortName for folder naming during cloning.');
          throw ArgumentError('Profile is missing repositoryShortName.');
        }

        repoToClone = GitRepository(
          name: profile.repositoryShortName!,
          htmlUrl: profile.repositoryCloneUrl!,
          id: profile.repositoryId!,
          description: profile.repositoryDescription!,
          isPrivate: profile.isPrivateRepository!,
          defaultBranch: profile.defaultBranch!,
          providerName: profile.gitProviderName!,
        );
      }


      if (repoToClone.htmlUrl.isEmpty) {
        _log.severe('GitRepository.htmlUrl (clone URL) cannot be empty for profile ${profile.id}');
        throw ArgumentError('GitRepository.htmlUrl (clone URL) cannot be empty.');
      }
      if (repoToClone.name.isEmpty) {
        _log.severe('GitRepository.name (for folder naming) cannot be empty for profile ${profile.id}');
        throw ArgumentError('GitRepository.name (for folder naming) cannot be empty.');
      }

      try {
        _log.info('Attempting to clone Git repository for profile ${profile.id} from ${repoToClone.htmlUrl} into folder ${repoToClone.name}');
        final actualClonedPath = await _gitService.cloneRepository(repoToClone, profile.id);
        _log.info('Repository cloned/found by GitService at $actualClonedPath for profile ${profile.id}.');
        PasswordRepositoryProfile updatedProfileFields = profile.copyWith(localPath: actualClonedPath);

        if (profile.localPath != actualClonedPath) {
          await _profileManager.updateProfile(profile.id, updatedProfileFields);
          _log.fine('Updated profile ${profile.id} with actual clonedPath: $actualClonedPath');
        }
      } catch (e, s) {
        _log.severe('Error during GitService.cloneRepository for profile ${profile.id}: $e', e, s);
        rethrow;
      }
    } else {
      _log.warning('Unsupported profile type for repository initialization: ${profile.type}');
      throw UnimplementedError('Repository initialization for type ${profile.type} is not implemented.');
    }
  }

  Future<String> _getDefaultLocalFolderPath(String profileId, String profileFolderNameForPath) async {
    final appDir = await getApplicationDocumentsDirectory();
    return path.join(appDir.path, 'repositories', profileFolderNameForPath.replaceAll(RegExp(r'[^\w\.-]'), '_'));
  }

  Future<void> syncRepository(String profileId) async {
    final profile = _profileManager.getProfile(profileId);
    if (profile == null) {
      _log.warning('Profile $profileId not found for sync.');
      throw Exception('Profile not found: $profileId');
    }
    _log.info('Syncing repository for profile ${profile.id} (${profile.profileName})');

    final String? repoPath = profile.localPath;
    if (repoPath == null) {
      _log.warning('Repository path (localPath) is null for profile ${profile.id}. Cannot sync. Attempting re-initialization.');
      if ((profile.type == PasswordSourceType.github || profile.type == PasswordSourceType.gitlab) &&
          profile.repositoryCloneUrl != null && profile.repositoryCloneUrl!.isNotEmpty &&
          profile.repositoryShortName != null && profile.repositoryShortName!.isNotEmpty) {
        _log.info('Attempting to re-initialize profile ${profile.id} due to missing localPath.');
        await initializeRepositoryForProfile(profile: profile);
        final updatedProfile = _profileManager.getProfile(profileId);
        if (updatedProfile?.localPath != null) {
          _log.info('Re-initialized profile ${profile.id}, now pulling changes.');
          await _gitService.pullChanges(updatedProfile!.localPath!);
          return;
        } else {
          _log.warning('Failed to re-initialize or set localPath for profile ${profile.id} after attempting clone. Sync failed.');
          throw Exception('Failed to set repository path after re-initialization for profile ${profile.id}.');
        }
      } else {
        _log.severe('Cannot re-initialize profile ${profile.id}: localPath is null and profile lacks necessary details for cloning (clone URL or short name).');
        throw Exception('Repository path for profile ${profile.id} is not set and cannot re-initialize due to missing details.');
      }
    }

    if (profile.type == PasswordSourceType.localFolder) {
      _log.info('Profile ${profile.id} is a local folder. Checking existence at $repoPath.');
      final dir = Directory(repoPath);
      if (!await dir.exists()) {
        _log.warning('Local folder for profile ${profile.id} not found at $repoPath. Creating it.');
        await dir.create(recursive: true);
      }
      return;
    }

    if (profile.type == PasswordSourceType.github || profile.type == PasswordSourceType.gitlab) {
      final dir = Directory(repoPath);
      if (!await dir.exists() || !await Directory(path.join(repoPath, '.git')).exists()) {
        _log.warning('Git repository for profile ${profile.id} not found at $repoPath or .git folder missing. Attempting to re-initialize.');
        if (profile.repositoryCloneUrl != null && profile.repositoryCloneUrl!.isNotEmpty &&
            profile.repositoryShortName != null && profile.repositoryShortName!.isNotEmpty) {
          await initializeRepositoryForProfile(profile: profile);
          final updatedProfile = _profileManager.getProfile(profileId);
          if (updatedProfile?.localPath != null) {
            _log.info('Re-initialized Git repository for profile ${profile.id}, now pulling changes.');
            await _gitService.pullChanges(updatedProfile!.localPath!);
            return;
          } else {
            _log.warning('Failed to re-initialize or set localPath for Git profile ${profile.id} after clone attempt. Sync failed.');
            throw Exception('Failed to set repository path after re-initializing Git profile ${profile.id}.');
          }
        } else {
          _log.severe('Cannot re-initialize Git repository for profile ${profile.id}: .git folder missing and profile lacks cloning details.');
          throw Exception('Cannot re-initialize Git repository: .git folder missing and profile lacks cloning details.');
        }
      }

      _log.info('Pulling changes for Git repository of profile ${profile.id} at $repoPath');
      try {
        await _gitService.pullChanges(repoPath);
        _log.info('Successfully pulled changes for profile ${profile.id}.');
      } catch (e, s) {
        _log.severe('Error pulling changes for profile ${profile.id}: $e', e, s);
        rethrow;
      }
    } else {
      _log.warning('Unsupported profile type for repository sync: ${profile.type}');
    }
  }

  Future<Map<String, dynamic>> getRepositoryStatus(String profileId) async {
    final profile = _profileManager.getProfile(profileId);
    if (profile == null) {
      _log.warning('Profile $profileId not found for getRepositoryStatus.');
      return {'status': 'error', 'message': 'Profile not found.'};
    }
    final String? repoPath = profile.localPath;
    if (repoPath == null) {
      _log.warning('Repository path is null for profile ${profile.id}. Cannot get status.');
      return {'status': 'error', 'message': 'Repository path not set in profile.'};
    }
    if (profile.type == PasswordSourceType.localFolder) {
      return {'status': 'local', 'message': 'This is a local folder, no remote status.'};
    }
    if (profile.type == PasswordSourceType.github || profile.type == PasswordSourceType.gitlab) {
      final dir = Directory(repoPath);
      if (!await dir.exists() || !await Directory(path.join(repoPath, '.git')).exists()) {
        _log.warning('Git repository or .git folder not found at $repoPath for profile ${profile.id}.');
        return {'status': 'missing', 'message': 'Repository directory or .git folder not found.'};
      }
      try {
        _log.fine('Getting repository status for profile ${profile.id} at $repoPath.');
        return await _gitService.getRepoStatus(repoPath);
      } catch (e, s) {
        _log.severe('Error getting repository status for profile ${profile.id}: $e', e, s);
        return {'status': 'error', 'message': 'Failed to get repository status: ${e.toString()}'};
      }
    } else {
      _log.warning('Unsupported profile type for getRepositoryStatus: ${profile.type}');
      return {'status': 'unsupported', 'message': 'Repository status not supported for this profile type.'};
    }
  }

  Future<void> commitAndPushChanges({
    required String profileId,
    String? relativeFilePath,
    required String commitMessage,
  }) async {
    final profile = _profileManager.getProfile(profileId);
    if (profile == null) {
      _log.warning('Profile $profileId not found for commitAndPushChanges.');
      throw Exception('Profile not found: $profileId');
    }
    final String? repoPath = profile.localPath;
    if (repoPath == null) {
      _log.warning('Repository path is null for profile ${profile.id}. Cannot commit/push.');
      throw Exception('Repository path not set in profile.');
    }
    if (profile.type == PasswordSourceType.localFolder) {
      _log.info('Profile ${profile.id} is a local folder. No commit/push needed.');
      return;
    }
    if (profile.type == PasswordSourceType.github || profile.type == PasswordSourceType.gitlab) {
      _log.info('Committing and pushing changes for profile ${profile.id} in $repoPath. Message: "$commitMessage"');
      if (relativeFilePath != null) {
        _log.warning("relativeFilePath was provided, but current GitService.pushChanges might add ALL unstaged files.");
      }
      try {
        await _gitService.pushChanges(repoPath, commitMessage);
        _log.info('Successfully committed and pushed changes for profile ${profile.id}.');
      } catch (e, s) {
        _log.severe('Error committing and pushing changes for profile ${profile.id}: $e', e, s);
        rethrow;
      }
    } else {
      _log.warning('Unsupported profile type for commit/push: ${profile.type}');
    }
  }

  Future<void> reCloneRepository({
    required String profileId,
    required GitRepository newGitRepoInfo,
  }) async {
    final profile = _profileManager.getProfile(profileId);
    if (profile == null) {
      _log.warning('Profile $profileId not found for reCloneRepository.');
      throw Exception('Profile not found: $profileId');
    }
    _log.info('Re-cloning repository for profile ${profile.id}. New URL: ${newGitRepoInfo.htmlUrl}');

    if (profile.type != PasswordSourceType.github && profile.type != PasswordSourceType.gitlab) {
      _log.severe('reCloneRepository is only applicable for Git-based profile types.');
      throw ArgumentError('reCloneRepository is only applicable for Git-based profile types.');
    }
    if (newGitRepoInfo.htmlUrl.isEmpty || newGitRepoInfo.name.isEmpty) {
      _log.severe('newGitRepoInfo must have a valid htmlUrl and name.');
      throw ArgumentError('newGitRepoInfo must have a valid htmlUrl and name.');
    }


    final String? oldRepoPath = profile.localPath;
    if (oldRepoPath != null) {
      final oldRepoDir = Directory(oldRepoPath);
      if (await oldRepoDir.exists()) {
        _log.info('Deleting existing repository directory: $oldRepoPath before re-cloning for profile ${profile.id}.');
        try {
          await oldRepoDir.delete(recursive: true);
        } catch (e, s) {
          _log.warning('Error deleting old repository directory $oldRepoPath for profile ${profile.id}: $e. Proceeding with clone attempt.', e, s);
        }
      }
    } else {
      _log.info('No old repository path found in profile ${profile.id} to delete before re-cloning.');
    }


    try {
      final actualClonedPath = await _gitService.cloneRepository(newGitRepoInfo, profile.id);
      _log.info('Repository re-cloned successfully by GitService at $actualClonedPath for profile ${profile.id}.');

      final updatedProfile = profile.copyWith(
        localPath: actualClonedPath,
        repositoryFullName: newGitRepoInfo.name,
        repositoryShortName: newGitRepoInfo.name,
        repositoryCloneUrl: newGitRepoInfo.htmlUrl,
        repositoryId: newGitRepoInfo.id.toString(),
        repositoryDescription: newGitRepoInfo.description,
        isPrivateRepository: newGitRepoInfo.isPrivate,
        defaultBranch: newGitRepoInfo.defaultBranch,
      );
      await _profileManager.updateProfile(profile.id, updatedProfile);
      _log.fine('Updated profile ${profile.id} after re-cloning with new path and repo info.');

    } catch (e, s) {
      _log.severe('Error re-cloning repository for profile ${profile.id}: $e', e, s);
      rethrow;
    }
  }
}