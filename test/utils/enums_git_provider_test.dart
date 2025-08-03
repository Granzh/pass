import 'package:flutter_test/flutter_test.dart';
import 'package:pass/core/utils/enums.dart';


void main() {
  group('GitProvider', () {
    group('toString() override', () {
      test('should return correct string representation', () {
        expect(GitProvider.github.toString(), 'github');
        expect(GitProvider.gitlab.toString(), 'gitlab');
      });
    });

    group('name getter', () {
      test('should return correct display name', () {
        expect(GitProvider.github.name, 'github');
        expect(GitProvider.gitlab.name, 'gitlab');
      });
    });

    group('fromString static method', () {
      test('should convert valid string to correct GitProvider (case-insensitive)', () {
        expect(GitProvider.fromString('github'), GitProvider.github);
        expect(GitProvider.fromString('GitHub'), GitProvider.github);
        expect(GitProvider.fromString('GITLAB'), GitProvider.gitlab);
        expect(GitProvider.fromString('gitlab'), GitProvider.gitlab);
      });

      test('should throw ArgumentError for invalid string', () {
        expect(
              () => GitProvider.fromString('invalid_provider'),
          throwsA(isA<ArgumentError>().having(
                  (e) => e.message, 'message', 'Invalid GitProvider: invalid_provider')),
        );
      });

      test('should throw ArgumentError for empty string', () {
        expect(
              () => GitProvider.fromString(''),
          throwsA(isA<ArgumentError>().having(
                  (e) => e.message, 'message', 'Invalid GitProvider: ')),
        );
      });
    });
  });
}
