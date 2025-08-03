import 'dart:io';

import 'package:logging/logging.dart';
import 'package:pass/services/GPG_services/gpg_key_service.dart';
import 'package:pass/services/profile_services/repository_profile_manager.dart';
import 'package:path/path.dart' as path_utils;

import '../../core/utils/enums.dart';
import '../../models/password_entry.dart';
import '../../models/password_repository_profile.dart';
import '../git_services/git_service.dart';

class PasswordEntryService {
  static final _log = Logger('PasswordEntryService');

  final GitService _gitService;
  final RepositoryProfileManager _profileManager;
  final GPGService _gpgService;

  PasswordEntryService({required GitService gitService,
    required RepositoryProfileManager profileManager,
    required GPGService gpgService,}) : _gitService = gitService,
        _profileManager = profileManager,
        _gpgService = gpgService;

  Future<List<PasswordEntry>> getAllEntries(String profileId, String userGpgPassphrase) async {
    final repoPath = _profileManager.getProfile(profileId)?.localPath;
    if (repoPath == null) {
      return [];
    }
    final rootDir = Directory(repoPath);
    if (!await rootDir.exists()) {
      return [];
    }

    final List<PasswordEntry> entries = [];

    final List<FileSystemEntity> files = await rootDir.list(recursive: true, followLinks: false).toList();

    for (final entity in files) {
      if (entity is File && entity.path.endsWith('.gpg')) {
        final relativePathWithFile = path_utils.relative(entity.path, from: repoPath);
        final entryNameWithExt = path_utils.basename(relativePathWithFile);
        final entryName = entryNameWithExt.substring(0, entryNameWithExt.length - '.gpg'.length);

        String folderPath = path_utils.dirname(relativePathWithFile);
        if (folderPath == '.' || folderPath == repoPath) {
          folderPath = '';
        }

        try {
          final PasswordEntry? entry = await getEntry(profileId, entryName, folderPath, userGpgPassphrase);
          if (entry != null) {
            entries.add(entry);
          }
        } on Exception catch (e) {
          if (e.toString().contains('Incorrect GPG passphrase')) {
            rethrow;
          }
          _log.warning('Error processing entry $entryName in $folderPath for profile $profileId. Skipping');
        }
      }
    }

    entries.sort((a, b) => a.entryName.compareTo(b.entryName));
    return entries;
  }

  Future<PasswordEntry?> getEntry(String profileId, String entryName, String folderPath, String userGpgPassphrase) async {
    final repoPath = _profileManager.getProfile(profileId)?.localPath;
    if (repoPath == null) {
      return null;
    }
    final String passwordFilePath = path_utils.join(repoPath, folderPath, '$entryName.gpg');
    final passwordFile = File(passwordFilePath);

    if (!await passwordFile.exists()) {
      return null;
    }

    try {
      final encryptedContent = await passwordFile.readAsString();
      final decryptedContent = await _gpgService.decryptDataForProfile(encryptedContent, profileId, userGpgPassphrase);
      final fileStat = await passwordFile.stat();

      return PasswordEntry.fromPassFileContent(decryptedContent, entryName, folderPath, fileStat.modified);
    } catch (e) {
      if (e.toString().contains('Incorrect GPG passphrase') ) {
        throw Exception('Incorrect GPG passphrase');
      }
      throw Exception('Failed to get entry: $entryName');
    }
  }

  Future<void> saveEntry(String profileId, PasswordEntry entry, String userGpgPassphrase) async {
    final PasswordRepositoryProfile? profile = _profileManager.getProfile(profileId);

    if (profile == null) {
      throw Exception('Profile not found with ID: $profileId');
    }
    if (profile.localPath == null) {
      throw Exception('Repository path for profile $profileId is not set.');
    }

    final String repoPath = profile.localPath!;
    final String fullEntryPathInRepo = path_utils.join(repoPath, entry.folderPath, '${entry.entryName}.gpg');
    final String passwordFilePathAbsolute = path_utils.join(repoPath, fullEntryPathInRepo);
    final passwordFile = File(passwordFilePathAbsolute);

    if (!await passwordFile.parent.exists()) {
      await passwordFile.parent.create(recursive: true);
    }

    final fileContentToEncrypt = entry.toPassFileContent();

    final encryptedContent = await _gpgService.encryptDataForProfile(fileContentToEncrypt, profileId);

    await passwordFile.writeAsString(encryptedContent);

    if (profile.type != PasswordSourceType.localFolder) {
      final commitMessage = 'Update password: ${entry.fullPath}';
      try {
        await _gitService.pushChanges(
          repoPath,
          commitMessage,
        );
      } catch (e) {
        throw Exception('Failed to push changes: $e');
      }
    }
  }

  Future<void> deleteEntry(String profileId, String entryName, String folderPath) async {
    final PasswordRepositoryProfile? profile = _profileManager.getProfile(profileId);
    if (profile == null) {
      throw Exception('Profile not found with ID: $profileId');
    }
    if (profile.localPath == null) {
      throw Exception('Repository path for profile $profileId is not set.');
    }

    final String repoPath = profile.localPath!;
    final String fullEntryPathForDisplay = folderPath.isEmpty ? entryName : path_utils.join(folderPath, entryName);
    final String relativeFilePathToDelete = path_utils.join(folderPath, '$entryName.gpg');
    final String passwordFilePathAbsolute = path_utils.join(repoPath, relativeFilePathToDelete);
    final passwordFile = File(passwordFilePathAbsolute);

    if (!await passwordFile.exists()) {
      return;
    }

    await passwordFile.delete();

    if (profile.type != PasswordSourceType.localFolder) {
      final commitMessage = 'Delete password: $fullEntryPathForDisplay';
      try {
        await _gitService.pushChanges(repoPath, commitMessage);
      } catch (e) {
        throw Exception('Failed to push changes: $e');
      }
    }
  }

}