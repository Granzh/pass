import 'package:flutter_test/flutter_test.dart';
import 'package:pass/core/utils/enums.dart';


void main() {
  group('PasswordSourceType', () {
    group('displayName getter', () {
      test('should return correct display name for each type', () {
        expect(PasswordSourceType.github.displayName, 'github');
        expect(PasswordSourceType.gitlab.displayName, 'gitlab');
        expect(PasswordSourceType.localFolder.displayName, 'localFolder');
        expect(PasswordSourceType.gitSsh.displayName, 'gitSsh');
        expect(PasswordSourceType.unknown.displayName, 'unknown');
      });
    });

    group('isGitType getter', () {
      test('should correctly identify Git types', () {
        expect(PasswordSourceType.github.isGitType, isTrue);
        expect(PasswordSourceType.gitlab.isGitType, isTrue);
        expect(PasswordSourceType.gitSsh.isGitType, isTrue);
      });

      test('should correctly identify non-Git types', () {
        expect(PasswordSourceType.localFolder.isGitType, isFalse);
        expect(PasswordSourceType.unknown.isGitType, isFalse);
      });
    });

    group('toGitProvider getter', () {
      test('should return correct GitProvider for Git types', () {
        expect(PasswordSourceType.github.toGitProvider, GitProvider.github);
        expect(PasswordSourceType.gitlab.toGitProvider, GitProvider.gitlab);
      });

      test('should return null for non-convertible types', () {
        expect(PasswordSourceType.localFolder.toGitProvider, isNull);
        expect(PasswordSourceType.gitSsh.toGitProvider, isNull);
        expect(PasswordSourceType.unknown.toGitProvider, isNull);
      });
    });

    group('passwordSourceTypeToString static method', () {
      test('should convert PasswordSourceType to correct string', () {
        expect(PasswordSourceType.passwordSourceTypeToString(PasswordSourceType.github), 'github');
        expect(PasswordSourceType.passwordSourceTypeToString(PasswordSourceType.gitlab), 'gitlab');
        expect(PasswordSourceType.passwordSourceTypeToString(PasswordSourceType.localFolder), 'localFolder');
        expect(PasswordSourceType.passwordSourceTypeToString(PasswordSourceType.gitSsh), 'gitSsh');
        expect(PasswordSourceType.passwordSourceTypeToString(PasswordSourceType.unknown), 'unknown');
      });
    });

    group('passwordSourceTypeFromString static method', () {
      test('should convert valid string to correct PasswordSourceType', () {
        expect(PasswordSourceType.passwordSourceTypeFromString('github'), PasswordSourceType.github);
        expect(PasswordSourceType.passwordSourceTypeFromString('gitlab'), PasswordSourceType.gitlab);
        expect(PasswordSourceType.passwordSourceTypeFromString('localFolder'), PasswordSourceType.localFolder);
        expect(PasswordSourceType.passwordSourceTypeFromString('gitSsh'), PasswordSourceType.gitSsh);
      });

      test('should convert "unknown" string to PasswordSourceType.unknown', () {
        expect(PasswordSourceType.passwordSourceTypeFromString('unknown'), PasswordSourceType.unknown);
      });

      test('should return PasswordSourceType.unknown for invalid string', () {
        expect(PasswordSourceType.passwordSourceTypeFromString('invalid_type'), PasswordSourceType.unknown);
        expect(PasswordSourceType.passwordSourceTypeFromString(''), PasswordSourceType.unknown);
      });
    });
  });
}
