import 'package:pass/services/git_service.dart';
import 'package:pass/services/gpg_service.dart';
import 'package:pass/services/password_repository_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A test-only extension to expose the private constructor of PasswordRepositoryService
extension TestPasswordRepositoryService on PasswordRepositoryService {
  /// Creates a test instance of PasswordRepositoryService with the provided mocks
  static PasswordRepositoryService createForTest({
    required FlutterSecureStorage secureStorage,
    required GPGService gpgService,
    required GitService gitService,
  }) {
    return PasswordRepositoryService._test(
      secureStorage: secureStorage,
      gpgService: gpgService,
      gitService: gitService,
    );
  }
}
