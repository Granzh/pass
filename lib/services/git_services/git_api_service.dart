import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:pass/services/auth_services/git_auth.dart';

import '../../core/utils/enums.dart';
import '../../models/git_repository_model.dart';

class GitApiException implements Exception {
  final String message;
  final int? statusCode;
  GitApiException(this.message, {this.statusCode});

  @override
  String toString() {
    return 'GitApiException: $message (Status Code: $statusCode)';
  }
}

class GitApiService {
  static final _log = Logger('GitApiService');

  final String gitLabBaseUrl;

  final SecureGitAuth _secureGitAuth;
  final http.Client _httpClient;

  late final String githubClientId = dotenv.env['GITHUB_CLIENT_ID']!;
  late final String gitlabClientSecret = dotenv.env['GITLAB_CLIENT_SECRET']!;
  late final String gitlabClientId = dotenv.env['GITLAB_CLIENT_ID']!;


  GitApiService({this.gitLabBaseUrl = 'https://gitlab.com',
    required SecureGitAuth secureGitAuth,
    required http.Client httpClient,}): _secureGitAuth = secureGitAuth,
        _httpClient = httpClient;

  Future<List<GitRepository>> getRepositories(GitProvider provider) async {
    _log.info('Fetching repositories for provider: ${provider.name}');

    final String currentClientId = provider == GitProvider.github ? githubClientId : gitlabClientId;
    final String? currentClientSecret = provider == GitProvider.gitlab ? (gitlabClientSecret.isNotEmpty ? gitlabClientSecret : null) : null;


    final headers = await _secureGitAuth.getValidAuthHeaders(
      provider,
      clientId: currentClientId,
      clientSecret: currentClientSecret,
      baseUrl: provider == GitProvider.gitlab ? gitLabBaseUrl : null,
    );

    if (headers == null) {
      _log.warning('No valid auth headers for ${provider.name}. User might not be authenticated or token expired.');
      throw GitApiException('Authentication required or token is invalid for ${provider.name}.', statusCode: 401);
    }

    String url;
    if (provider == GitProvider.github) {
      url = 'https://api.github.com/user/repos?type=owner&sort=pushed&per_page=100';
    } else { // GitLab
      url = '$gitLabBaseUrl/api/v4/projects?membership=true&order_by=last_activity_at&per_page=100';
    }

    try {
      final response = await _httpClient.get(Uri.parse(url), headers: headers);

      if (response.statusCode == 200) {
        final List<dynamic> jsonData = json.decode(response.body);
        final repositories = jsonData
            .map((item) => GitRepository.fromJson(item as Map<String, dynamic>, provider.name))
            .toList();
        _log.info('Successfully fetched ${repositories.length} repositories for ${provider.name}');
        return repositories;
      } else {
        _log.severe('Failed to fetch repositories for ${provider.name}. Status: ${response.statusCode}, Body: ${response.body}');
        throw GitApiException(
          'Failed to fetch repositories from ${provider.name}: ${response.reasonPhrase ?? "Unknown error"}',
          statusCode: response.statusCode,
        );
      }
    } catch (e, s) {
      _log.severe('Error fetching repositories for ${provider.name}: $e', e, s);
      if (e is GitApiException) rethrow;
      throw GitApiException('An unexpected error occurred while fetching repositories: $e');
    }
  }

  Future<GitRepository> getRepositoryDetails(GitProvider provider, String repoIdOrFullName) async {
    _log.info('Fetching details for repository: $repoIdOrFullName, provider: ${provider.name}');
    final String currentClientId = provider == GitProvider.github ? githubClientId : gitlabClientId;
    final String? currentClientSecret = provider == GitProvider.gitlab ? (gitlabClientSecret.isNotEmpty ? gitlabClientSecret : null) : null;

    final headers = await _secureGitAuth.getValidAuthHeaders(
      provider,
      clientId: currentClientId,
      clientSecret: currentClientSecret,
      baseUrl: provider == GitProvider.gitlab ? gitLabBaseUrl : null,
    );

    if (headers == null) {
      throw GitApiException('Authentication required or token is invalid for ${provider.name}.', statusCode: 401);
    }

    String url;
    if (provider == GitProvider.github) {
      url = 'https://api.github.com/repos/$repoIdOrFullName';
    } else { // GitLab
      url = '$gitLabBaseUrl/api/v4/projects/${Uri.encodeComponent(repoIdOrFullName)}';
    }

    try {
      final response = await _httpClient.get(Uri.parse(url), headers: headers);
      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonData = json.decode(response.body);
        final repository = GitRepository.fromJson(jsonData, provider.name);
        _log.info('Successfully fetched details for repository: ${repository.name}');
        return repository;
      } else {
        _log.severe('Failed to fetch repository details for ${provider.name}. Status: ${response.statusCode}, Body: ${response.body}');
        throw GitApiException(
          'Failed to fetch repository details from ${provider.name}: ${response.reasonPhrase ?? "Unknown error"}',
          statusCode: response.statusCode,
        );
      }
    } catch (e, s) {
      _log.severe('Error fetching repository details for ${provider.name}: $e', e, s);
      if (e is GitApiException) rethrow;
      throw GitApiException('An unexpected error occurred while fetching repository details: $e');
    }
  }
}