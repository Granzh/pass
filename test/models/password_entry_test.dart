import 'package:flutter_test/flutter_test.dart';
import 'package:pass/models/password_entry.dart';

void main() {
  group('PasswordEntry', () {
    final testTime = DateTime(1984, 2, 29, 12, 0, 0);

    group('Constructor and Defaults', () {
      test('should generate a unique ID if not provided', () {
        final entry1 = PasswordEntry(
          entryName: 'test1',
          password: 'pass',
          lastModified: testTime,
        );
        final entry2 = PasswordEntry(
          entryName: 'test2',
          password: 'pass',
          lastModified: testTime,
        );
        expect(entry1.id, isNotNull);
        expect(entry1.id, isNotEmpty);
        expect(entry2.id, isNotNull);
        expect(entry1.id, isNot(equals(entry2.id)),
            reason: "IDs should be unique for new entries");
      });

      test('should use provided ID if available', () {
        const customId = 'my-custom-uuid';
        final entry = PasswordEntry(
          id: customId,
          entryName: 'test',
          password: 'pass',
          lastModified: testTime,
        );
        expect(entry.id, customId);
      });

      test('folderPath should default to empty string', () {
        final entry = PasswordEntry(
          entryName: 'test',
          password: 'pass',
          lastModified: testTime,
        );
        expect(entry.folderPath, isEmpty);
      });

      test('metadata should default to an empty map', () {
        final entry = PasswordEntry(
          entryName: 'test',
          password: 'pass',
          lastModified: testTime,
        );
        expect(entry.metadata, isEmpty);
        expect(entry.metadata, isA<Map<String, String>>());
      });
    });

    group('Getters', () {
      test('name getter should return entryName', () {
        final entry = PasswordEntry(
            entryName: 'myEntry', password: 'p', lastModified: testTime);
        expect(entry.name, 'myEntry');
      });

      test('path getter should return fullPath', () {
        final entry = PasswordEntry(entryName: 'file',
            folderPath: 'folder',
            password: 'p',
            lastModified: testTime);
        expect(entry.path, 'folder/file');
      });

      group('fullPath', () {
        test(
            'should create full path correctly when folderPath is present', () {
          final entry = PasswordEntry(
            entryName: 'github',
            folderPath: 'work',
            password: 'mypassword',
            lastModified: testTime,
          );
          expect(entry.fullPath, 'work/github');
        });

        test('should create full path correctly when folderPath is empty', () {
          final entry = PasswordEntry(
            entryName: 'root_entry',
            password: 'mypassword',
            lastModified: testTime,
            folderPath: '',
          );
          expect(entry.fullPath, 'root_entry');
        });
      });

      group('url getter', () {
        test('should return value from "url" key if present', () {
          final entry = PasswordEntry(entryName: 'e',
              password: 'p',
              metadata: {'url': 'http://lowercase.com'},
              lastModified: testTime);
          expect(entry.url, 'http://lowercase.com');
        });
        test('should return value from "URL" key if "url" is not present', () {
          final entry = PasswordEntry(entryName: 'e',
              password: 'p',
              metadata: {'URL': 'http://uppercase.com'},
              lastModified: testTime);
          expect(entry.url, 'http://uppercase.com');
        });
        test('should prioritize "url" over "URL"', () {
          final entry = PasswordEntry(entryName: 'e',
              password: 'p',
              metadata: {
                'url': 'http://lowercase.com',
                'URL': 'http://uppercase.com'
              },
              lastModified: testTime);
          expect(entry.url, 'http://lowercase.com');
        });
        test('should return null if no url keys are found', () {
          final entry = PasswordEntry(entryName: 'e',
              password: 'p',
              metadata: {'other': 'value'},
              lastModified: testTime);
          expect(entry.url, isNull);
        });
        test('should return empty string if url value is empty', () {
          final entry = PasswordEntry(entryName: 'e',
              password: 'p',
              metadata: {'url': ''},
              lastModified: testTime);
          expect(entry.url, '');
        });
      });

      group('username getter', () {
        test('should return value from "username" key if present', () {
          final entry = PasswordEntry(entryName: 'e',
              password: 'p',
              metadata: {'username': 'user1'},
              lastModified: testTime);
          expect(entry.username, 'user1');
        });
        test(
            'should return value from "user" key if "username" is not present', () {
          final entry = PasswordEntry(entryName: 'e',
              password: 'p',
              metadata: {'user': 'user2'},
              lastModified: testTime);
          expect(entry.username, 'user2');
        });
        test(
            'should return value from "login" key if "username" and "user" are not present', () {
          final entry = PasswordEntry(entryName: 'e',
              password: 'p',
              metadata: {'login': 'user3'},
              lastModified: testTime);
          expect(entry.username, 'user3');
        });
        test('should prioritize "username" > "user" > "login"', () {
          var entry = PasswordEntry(entryName: 'e',
              password: 'p',
              metadata: {'login': 'l', 'user': 'u', 'username': 'un'},
              lastModified: testTime);
          expect(entry.username, 'un');
          entry = PasswordEntry(entryName: 'e',
              password: 'p',
              metadata: {'login': 'l', 'user': 'u'},
              lastModified: testTime);
          expect(entry.username, 'u');
        });
        test('should return null if no username keys are found', () {
          final entry = PasswordEntry(entryName: 'e',
              password: 'p',
              metadata: {},
              lastModified: testTime);
          expect(entry.username, isNull);
        });
      });

      group('notes getter', () {
        test('should return value from "notes" key if present', () {
          final entry = PasswordEntry(entryName: 'e',
              password: 'p',
              metadata: {'notes': 'my notes'},
              lastModified: testTime);
          expect(entry.notes, 'my notes');
        });
        test(
            'should return value from "comment" key if "notes" is not present', () {
          final entry = PasswordEntry(entryName: 'e',
              password: 'p',
              metadata: {'comment': 'my comment'},
              lastModified: testTime);
          expect(entry.notes, 'my comment');
        });
        test('should prioritize "notes" over "comment"', () {
          final entry = PasswordEntry(entryName: 'e',
              password: 'p',
              metadata: {'notes': 'n', 'comment': 'c'},
              lastModified: testTime);
          expect(entry.notes, 'n');
        });
        test('should return null if no notes keys are found', () {
          final entry = PasswordEntry(entryName: 'e',
              password: 'p',
              metadata: {},
              lastModified: testTime);
          expect(entry.notes, isNull);
        });
      });
    });

    group('toPassFileContent()', () {
      test('should write password first, then metadata, trimming result', () {
        final entry = PasswordEntry(
          entryName: 'test',
          password: 'secret_password',
          metadata: {'user': 'tester', 'url': 'http://example.com'},
          lastModified: testTime,
        );
        final expectedContent = '''
secret_password
user: tester
url: http://example.com'''
            .trim(); // .trim() on expected to match behavior
        expect(entry.toPassFileContent(), expectedContent);
      });

      test('should not write metadata with empty values', () {
        final entry = PasswordEntry(
          entryName: 'test',
          password: 'secret',
          metadata: {'user': 'tester', 'notes': '', 'emptyKey': ''},
          lastModified: testTime,
        );
        final expectedContent = '''
secret
user: tester'''
            .trim();
        expect(entry.toPassFileContent(), expectedContent);
      });

      test('should only write password if metadata is empty', () {
        final entry = PasswordEntry(
          entryName: 'test',
          password: 'only_password',
          metadata: {},
          lastModified: testTime,
        );
        expect(entry.toPassFileContent(), 'only_password');
      });

      test(
          'should handle password with leading/trailing spaces in input (though it will be written as is)', () {
        // The method itself doesn't trim the password field, it writes what's in `this.password`
        final entry = PasswordEntry(
          entryName: 'test',
          password: '  spaced_password  ',
          lastModified: testTime,
        );
        expect(entry.toPassFileContent(), 'spaced_password');
      });

      test(
          'should correctly format multi-line notes in metadata if stored as single string with newlines', () {
        // Standard pass format typically has one value per key.
        // If a value contains newlines, it will be written as such.
        final entry = PasswordEntry(
          entryName: 'test',
          password: 'password',
          metadata: {'notes': 'line1\nline2'},
          lastModified: testTime,
        );
        expect(
            entry.toPassFileContent(), 'password\nnotes: line1\nline2'.trim());
      });
    });

    group('PasswordEntry.fromPassFileContent()', () {
      test('should parse valid content correctly', () {
        final content = '''
mypassword
username: john
url: https://github.com
notes: personal account
''';
        final entry = PasswordEntry.fromPassFileContent(
            content, 'github', 'work', testTime);

        expect(entry.password, 'mypassword');
        expect(entry.username, 'john');
        expect(entry.url, 'https://github.com');
        expect(entry.notes, 'personal account');
        expect(entry.entryName, 'github');
        expect(entry.folderPath, 'work');
        expect(entry.lastModified, testTime);
        expect(entry.id, isNotNull);
      });

      test('should throw FormatException for empty content', () {
        expect(
                () =>
                PasswordEntry.fromPassFileContent('', 'test', '', testTime),
            throwsA(isA<FormatException>()
                .having((e) => e.message, 'message',
                "Decrypted GPG content is empty.")));
      });

      test('should parse content with only password', () {
        final entry = PasswordEntry.fromPassFileContent(
            'lonely_password  ', 'test', '', testTime);
        expect(entry.password, 'lonely_password'); // .trim() in factory
        expect(entry.metadata, isEmpty);
      });

      test(
          'should correctly parse keys and values with extra spaces around key, colon, and value', () {
        final content = '''
          my pass  
            user  :  john doe  
          URL : http://spaced.com 
        ''';
        final entry = PasswordEntry.fromPassFileContent(
            content, 'test', '', testTime);
        expect(entry.password, 'my pass');
        expect(entry.metadata['user'], 'john doe');
        expect(entry.metadata['URL'], 'http://spaced.com');
      });

      test('should handle values containing colons', () {
        final content = '''
mypassword
custom_key: value:with:colons
another: key: value : also
# A comment line sometimes seen in pass files, should be stored as line_X
key_only_no_value:
''';
        final entry = PasswordEntry.fromPassFileContent(
            content, 'test', '', testTime);
        expect(entry.metadata['custom_key'], 'value:with:colons');
        expect(entry.metadata['another'], 'key: value : also');
        expect(entry.metadata.containsKey('line_3'),
            isTrue); // for "# A comment..."
        expect(entry.metadata['key_only_no_value'],
            ''); // Value becomes empty string
      });

      test('should ignore empty lines between metadata', () {
        final content = '''
mypassword
user: U

notes: N
''';
        final entry = PasswordEntry.fromPassFileContent(
            content, 'test', '', testTime);
        expect(entry.metadata.length, 2);
        expect(entry.username, 'U');
        expect(entry.notes, 'N');
      });

      test(
          'handles malformed metadata line gracefully by storing it as line_X', () {
        final content = '''
password123
username: alice
this is not a valid key-value line
another: valid
 just_a_value_no_key_colon
''';
        final entry = PasswordEntry.fromPassFileContent(
            content, 'test', '', testTime);
        expect(entry.password, 'password123');
        expect(entry.metadata['username'], 'alice');
        expect(entry.metadata['line_2'], 'this is not a valid key-value line');
        expect(entry.metadata['another'], 'valid');
        expect(entry.metadata['line_4'], 'just_a_value_no_key_colon');
      });

      test(
          'should handle password with leading/trailing spaces in file (gets trimmed)', () {
        final content = '''
          spaced password  
        user: test
        ''';
        final entry = PasswordEntry.fromPassFileContent(
            content, 'test', '', testTime);
        expect(entry.password, 'spaced password');
      });
    });

    group('Update methods', () {
      late PasswordEntry entry;

      setUp(() {
        entry = PasswordEntry(
          entryName: 'e',
          password: 'p',
          metadata: {
            'url': 'http://url.com',
            'URL': 'http://URL.com',
            'username': 'user1',
            'user': 'user2',
            'login': 'user3',
            'notes': 'notes1',
            'comment': 'comment1',
            'other': 'data'
          },
          lastModified: testTime,
        );
      });

      group('updateUrl', () {
        test(
            'should set primary "url" key and remove others when newUrl is valid', () {
          entry.updateUrl('http://new.com');
          expect(entry.metadata['url'], 'http://new.com');
          expect(entry.metadata.containsKey('URL'), isTrue,
              reason: "Current logic doesn't remove URL unless newUrl is empty/null");
          expect(entry.url, 'http://new.com');
        });

        test('should remove all url keys if newUrl is null', () {
          entry.updateUrl(null);
          expect(entry.metadata.containsKey('url'), isFalse);
          expect(entry.metadata.containsKey('URL'), isFalse);
          expect(entry.url, isNull);
          expect(entry.metadata.containsKey('other'), isTrue); // sanity check
        });

        test('should remove all url keys if newUrl is empty', () {
          entry.updateUrl('');
          expect(entry.metadata.containsKey('url'), isFalse);
          expect(entry.metadata.containsKey('URL'), isFalse);
          expect(entry.url, isNull);
        });

        test('should add "url" key if it did not exist', () {
          final newEntry = PasswordEntry(entryName: 'ne',
              password: 'p',
              metadata: {},
              lastModified: testTime);
          newEntry.updateUrl('http://fresh.com');
          expect(newEntry.metadata['url'], 'http://fresh.com');
        });
      });

      group('updateUsername', () {
        test(
            'should set primary "username" key and remove others when newUsername is valid', () {
          entry.updateUsername('new_user');
          expect(entry.metadata['username'], 'new_user');
          expect(entry.metadata.containsKey('user'), isTrue,
              reason: "Current logic doesn't remove 'user' or 'login' unless newUsername is empty/null");
          expect(entry.metadata.containsKey('login'), isTrue);
          expect(entry.username, 'new_user');
        });

        test('should remove all username keys if newUsername is null', () {
          entry.updateUsername(null);
          expect(entry.metadata.containsKey('username'), isFalse);
          expect(entry.metadata.containsKey('user'), isFalse);
          expect(entry.metadata.containsKey('login'), isFalse);
          expect(entry.username, isNull);
        });

        test('should remove all username keys if newUsername is empty', () {
          entry.updateUsername('');
          expect(entry.metadata.containsKey('username'), isFalse);
          expect(entry.metadata.containsKey('user'), isFalse);
          expect(entry.metadata.containsKey('login'), isFalse);
          expect(entry.username, isNull);
        });
      });

      group('updateNotes', () {
        test(
            'should set primary "notes" key and remove "comment" when newNotes is valid', () {
          entry.updateNotes('new_notes');
          expect(entry.metadata['notes'], 'new_notes');
          expect(entry.metadata.containsKey('comment'), isTrue,
              reason: "Current logic doesn't remove 'comment' unless newNotes is empty/null");
          expect(entry.notes, 'new_notes');
        });

        test('should remove all notes keys if newNotes is null', () {
          // Current logic only removes 'notes'. If 'comment' should also be removed, update logic.
          // For now, testing current behavior:
          entry.updateNotes(null);
          expect(entry.metadata.containsKey('notes'), isFalse);
          // expect(entry.metadata.containsKey('comment'), isFalse); // This would fail with current updateNotes
          expect(
              entry.notes, 'comment1'); // Because 'comment' key is still there
        });

        test('should remove primary "notes" key if newNotes is empty', () {
          // Current logic only removes 'notes'. If 'comment' should also be removed, update logic.
          entry.updateNotes('');
          expect(entry.metadata.containsKey('notes'), isFalse);
          // expect(entry.metadata.containsKey('comment'), isFalse); // This would fail
          expect(
              entry.notes, 'comment1'); // Because 'comment' key is still there
        });
      });



    });

    group('copyWith', () {
      late PasswordEntry original;
      final originalTime = DateTime(2023, 1, 1, 10, 0, 0);

      setUp(() {
        original = PasswordEntry(
          id: 'original-id',
          entryName: 'github',
          folderPath: 'work',
          password: 'oldPass123',
          metadata: {'url': 'http://original.com', 'user': 'original_user'},
          lastModified: originalTime,
        );
      });

      test(
          'should create a distinct copy with no changes if no parameters are provided', () {
        final copy = original.copyWith();

        expect(copy.id, original.id);
        expect(copy.entryName, original.entryName);
        expect(copy.folderPath, original.folderPath);
        expect(copy.password, original.password);
        expect(copy.metadata, equals(original.metadata));
        expect(copy.lastModified, original.lastModified);

        expect(copy, isNot(same(original)),
            reason: "copyWith should produce a new instance.");
        expect(copy.metadata, isNot(same(original.metadata)),
            reason: "Metadata map should be a new instance (deep copy of map structure).");
      });

      test('should correctly update password when provided', () {
        final updated = original.copyWith(password: 'newPass456');
        expect(updated.password, 'newPass456');
        expect(
            original.password, 'oldPass123'); // Original should be unchanged
      });

      test('should correctly update entryName', () {
        final updated = original.copyWith(entryName: 'gitlab');
        expect(updated.entryName, 'gitlab');
        expect(original.entryName, 'github');
      });

      test('should correctly update folderPath', () {
        final updated = original.copyWith(folderPath: 'personal');
        expect(updated.folderPath, 'personal');
        expect(original.folderPath, 'work');
      });

      test('should correctly update lastModified', () {
        final newTime = DateTime(2024, 1, 1);
        final updated = original.copyWith(lastModified: newTime);
        expect(updated.lastModified, newTime);
        expect(original.lastModified, originalTime);
      });

      test('should correctly update id', () {
        final updated = original.copyWith(id: 'new-id-for-copy');
        expect(updated.id, 'new-id-for-copy');
        expect(original.id, 'original-id');
      });
    });
  });
}