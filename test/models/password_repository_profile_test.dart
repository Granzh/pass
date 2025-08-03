import 'package:flutter_test/flutter_test.dart';
import 'package:pass/models/git_repository_model.dart';


void main() {
  group('GitRepository', () {
    const githubProviderName = 'github'; // GitProvider.github.name;
    const gitlabProviderName = 'gitlab'; // GitProvider.gitlab.name;

    final githubJson = {
      'id': 12345,
      'full_name': 'octocat/Hello-World',
      'description': 'My first repository on GitHub!',
      'html_url': 'https://github.com/octocat/Hello-World',
      'private': false,
      'default_branch': 'master',
    };

    final gitlabJson = {
      'id': 67890,
      'path_with_namespace': 'gitlab-org/gitlab-test',
      'description': 'A test project for GitLab.',
      'web_url': 'https://gitlab.com/gitlab-org/gitlab-test',
      'visibility': 'public', // "public", "internal", "private"
      'default_branch': 'main',
    };

    final storedJson = {
      'id': 'stored-id-1',
      'name': 'Stored Repo',
      'description': 'Stored description',
      'htmlUrl': 'http://example.com/stored',
      'isPrivate': true,
      'defaultBranch': 'develop',
      'providerName': githubProviderName,
    };


    group('Constructor', () {
      test('should correctly initialize fields', () {
        final repo = GitRepository(
          id: '1', name: 'Repo1', description: 'Desc1', htmlUrl: 'url1',
          isPrivate: false, defaultBranch: 'main', providerName: githubProviderName,
        );
        expect(repo.id, '1');
        expect(repo.name, 'Repo1');
        expect(repo.description, 'Desc1');
        expect(repo.htmlUrl, 'url1');
        expect(repo.isPrivate, false);
        expect(repo.defaultBranch, 'main');
        expect(repo.providerName, githubProviderName);
      });
    });

    group('fromJson factory', () {
      group('GitHub provider', () {
        test('should correctly parse GitHub JSON', () {
          final repo = GitRepository.fromJson(githubJson, githubProviderName);
          expect(repo.id, '12345');
          expect(repo.name, 'octocat/Hello-World');
          expect(repo.description, 'My first repository on GitHub!');
          expect(repo.htmlUrl, 'https://github.com/octocat/Hello-World');
          expect(repo.isPrivate, false);
          expect(repo.defaultBranch, 'master');
          expect(repo.providerName, githubProviderName);
        });

        test('should handle null description from GitHub JSON', () {
          final Map<String, dynamic> jsonWithNullDesc = Map.from(githubJson)..['description'] = null;
          final repo = GitRepository.fromJson(jsonWithNullDesc, githubProviderName);
          expect(repo.description, '');
        });
      });

      group('GitLab provider', () {
        test('should correctly parse GitLab JSON with path_with_namespace', () {
          final repo = GitRepository.fromJson(gitlabJson, gitlabProviderName);
          expect(repo.id, '67890');
          expect(repo.name, 'gitlab-org/gitlab-test');
          expect(repo.description, 'A test project for GitLab.');
          expect(repo.htmlUrl, 'https://gitlab.com/gitlab-org/gitlab-test');
          expect(repo.isPrivate, false); // from visibility: 'public'
          expect(repo.defaultBranch, 'main');
          expect(repo.providerName, gitlabProviderName);
        });

        test('should use "Unnamed GitLab Repo" if name fields are missing', () {
          final Map<String, dynamic> jsonNoName = Map.from(gitlabJson)
            ..remove('path_with_namespace')
            ..remove('name_with_namespace');
          final repo = GitRepository.fromJson(jsonNoName, gitlabProviderName);
          expect(repo.name, 'Unnamed GitLab Repo');
        });

        test('should correctly parse private GitLab repo', () {
          final Map<String, dynamic> privateGitlabJson = Map.from(gitlabJson)..['visibility'] = 'private';
          final repo = GitRepository.fromJson(privateGitlabJson, gitlabProviderName);
          expect(repo.isPrivate, isTrue);
        });

        test('should use "main" for defaultBranch if missing in GitLab JSON', () {
          final Map<String, dynamic> jsonNoBranch = Map.from(gitlabJson)..remove('default_branch');
          final repo = GitRepository.fromJson(jsonNoBranch, gitlabProviderName);
          expect(repo.defaultBranch, 'main');
        });

        test('should handle null description from GitLab JSON', () {
          final Map<String, dynamic> jsonNullDesc = Map.from(gitlabJson)..['description'] = null;
          final repo = GitRepository.fromJson(jsonNullDesc, gitlabProviderName);
          expect(repo.description, '');
        });
        test('should handle null web_url from GitLab JSON', () {
          final Map<String, dynamic> jsonNullUrl = Map.from(gitlabJson)..['web_url'] = null;
          final repo = GitRepository.fromJson(jsonNullUrl, gitlabProviderName);
          expect(repo.htmlUrl, '');
        });
      });

      test('should throw ArgumentError for unknown provider', () {
        expect(
              () => GitRepository.fromJson(githubJson, 'unknown_provider'),
          throwsA(isA<ArgumentError>().having(
                  (e) => e.message, 'message', 'Unknown provider in GitRepository.fromJson')),
        );
      });

      test('should use "Unnamed GitHub Repo" if "full_name" is missing for GitHub', () {
        final Map<String, dynamic> incompleteJson = Map.from(githubJson)..remove('full_name');
        final repo = GitRepository.fromJson(incompleteJson, githubProviderName);
        expect(repo.name, 'Unnamed GitHub Repo');
        expect(repo.isPrivate, false);
        expect(repo.defaultBranch, 'master');
        expect(repo.providerName, githubProviderName);
        expect(repo.description, 'My first repository on GitHub!');
      });

    });

    group('fromStoredJson factory', () {
      test('should correctly parse stored JSON', () {
        final repo = GitRepository.fromStoredJson(storedJson);
        expect(repo.id, 'stored-id-1');
        expect(repo.name, 'Stored Repo');
        expect(repo.description, 'Stored description');
        expect(repo.htmlUrl, 'http://example.com/stored');
        expect(repo.isPrivate, true);
        expect(repo.defaultBranch, 'develop');
        expect(repo.providerName, githubProviderName);
      });

      test('should throw TypeError if required field "name" is missing', () {
        final Map<String, dynamic> incompleteJson = Map.from(storedJson)..remove('name');
        expect(
                () => GitRepository.fromStoredJson(incompleteJson),
            throwsA(isA<TypeError>())
        );
      });
    });

    group('copyWith()', () {
      late GitRepository originalRepo;
      setUp(() {
        originalRepo = GitRepository(
          id: '1', name: 'Original', description: 'OrigDesc', htmlUrl: 'orig_url',
          isPrivate: false, defaultBranch: 'main', providerName: githubProviderName,
        );
      });

      test('should create an exact copy if no parameters provided', () {
        final copy = originalRepo.copyWith();
        expect(copy, equals(originalRepo));
        expect(identical(copy, originalRepo), isFalse);
      });

      test('should update only the name field', () {
        final updated = originalRepo.copyWith(name: 'Updated Name');
        expect(updated.name, 'Updated Name');
        expect(updated.id, originalRepo.id);
        expect(updated.description, originalRepo.description);
      });
    });

    group('toString()', () {
      test('should return a string in the expected format', () {
        final repo = GitRepository(
          id: 'id1', name: 'RepoName', description: '', htmlUrl: '',
          isPrivate: true, defaultBranch: 'dev', providerName: gitlabProviderName,
        );
        expect(repo.toString(), 'GitRepository{id: id1, name: RepoName, isPrivate: true, defaultBranch: dev}');
      });
    });

    group('Equality (== and hashCode)', () {
      final repo1 = GitRepository(id: '1', name: 'Repo', description: '', htmlUrl: '', isPrivate: false, defaultBranch: 'main', providerName: githubProviderName);
      final repo1Copy = GitRepository(id: '1', name: 'Repo', description: 'desc2', htmlUrl: 'url2', isPrivate: true, defaultBranch: 'dev', providerName: githubProviderName);
      final repo2 = GitRepository(id: '2', name: 'Repo', description: '', htmlUrl: '', isPrivate: false, defaultBranch: 'main', providerName: githubProviderName); // Different ID
      final repo3 = GitRepository(id: '1', name: 'AnotherRepo', description: '', htmlUrl: '', isPrivate: false, defaultBranch: 'main', providerName: githubProviderName); // Different name
      final repo4 = GitRepository(id: '1', name: 'Repo', description: '', htmlUrl: '', isPrivate: false, defaultBranch: 'main', providerName: gitlabProviderName); // Different provider

      test('instances with same id, name, providerName should be equal', () {
        expect(repo1, equals(repo1Copy));
      });

      test('instances with different id should not be equal', () {
        expect(repo1, isNot(equals(repo2)));
      });

      test('instances with different name should not be equal', () {
        expect(repo1, isNot(equals(repo3)));
      });

      test('instances with different providerName should not be equal', () {
        expect(repo1, isNot(equals(repo4)));
      });

      test('instance should be equal to itself', () {
        expect(repo1, equals(repo1));
      });

      test('instance should not be equal to null', () {
        expect(repo1, isNot(equals(null)));
      });

      test('instance should not be equal to an object of a different type', () {
        // ignore: unrelated_type_equality_checks
        expect(repo1 == 'a string', isFalse);
      });

      test('hashCode should be the same for equal objects', () {
        expect(repo1.hashCode, equals(repo1Copy.hashCode));
      });

      test('hashCode should (usually) be different for non-equal objects', () {
        expect(repo1.hashCode, isNot(equals(repo2.hashCode)));
        expect(repo1.hashCode, isNot(equals(repo3.hashCode)));
        expect(repo1.hashCode, isNot(equals(repo4.hashCode)));
      });
    });
  });
}
