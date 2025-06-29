import 'dart:async';
import 'dart:convert';

import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:http/http.dart' as http;
import 'package:pass/core/utils/secure_storage.dart';
import 'package:pass/models/git_repository_model.dart';

/// Service for handling OAuth2 authentication with Git providers

final FlutterAppAuth _appAuth = FlutterAppAuth();

/// Enum representing supported Git providers
enum GitProvider {
  github,
  gitlab;
  
  @override
  String toString() => this == GitProvider.github ? 'github' : 'gitlab';
  
  static GitProvider? fromString(String value) {
    return GitProvider.values.firstWhere(
      (e) => e.toString() == value.toLowerCase(),
      orElse: () => throw ArgumentError('Invalid GitProvider: $value'),
    );
  }
}

/// Exception thrown when authentication fails
class AuthenticationException implements Exception {
  final String message;
  final dynamic error;
  
  AuthenticationException(this.message, [this.error]);
  
  @override
  String toString() => 'AuthenticationException: $message${error != null ? ' - $error' : ''}';
}

class OAuthConfig {
  final String clientId;
  final String? clientSecret;
  final String authorizationEndpoint;
  final String tokenEndpoint;
  final List<String> scopes;

  OAuthConfig({
    required this.clientId,
    this.clientSecret,
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    required this.scopes,
  });
}

final githubOAuth = OAuthConfig(
  clientId: 'Ov23lizcUU0QjeJqNfN9',
  clientSecret: '897cbd8ea4ebf22da6f3910477abb7aa1a450694',
  authorizationEndpoint: 'https://github.com/login/oauth/authorize',
  tokenEndpoint: 'https://github.com/login/oauth/access_token',
  scopes: ['repo'],
);

final gitlabOAuth = OAuthConfig(
  clientId: 'a3631d06693d0cac7826f507945c2ff9b33a9d89c5ce0ac7dd87fea1921f0a17',
  clientSecret: 'gloas-6563e3dffa44f70642bc8d775e41fbc101a4de3dc16cc1fc9c2ef368414f53ea',
  authorizationEndpoint: 'https://gitlab.com/oauth/authorize',
  tokenEndpoint: 'https://gitlab.com/oauth/token',
  scopes: ['api'],
);

/// Authenticates with the specified Git provider
/// Returns true if authentication was successful, false otherwise
Future<bool> loginWith(GitProvider provider, String profileId) async {
  final config = provider == GitProvider.github ? githubOAuth : gitlabOAuth;
  final redirectUrl = 'com.pass.app://auth/callback';

  try {
    // First, try to refresh the token if we have a refresh token
    final refreshToken = await secureStorage.read(key: 'profile_${profileId}_refresh_token');
    if (refreshToken != null) {
      try {
        final refreshed = await _refreshToken(profileId, refreshToken, provider);
        if (refreshed) return true;
      } catch (e) {
        throw Exception('Token refresh failed, proceeding with new login: $e');
      }
    }

    // If no refresh token or refresh failed, do a full login
    final result = await _appAuth.authorizeAndExchangeCode(
      AuthorizationTokenRequest(
        config.clientId,
        redirectUrl,
        serviceConfiguration: AuthorizationServiceConfiguration(
          authorizationEndpoint: config.authorizationEndpoint,
          tokenEndpoint: config.tokenEndpoint,
        ),
        scopes: config.scopes,
        clientSecret: config.clientSecret,
        promptValues: ['login'],
      ),
    );

    if (result.accessToken == null) {
      throw AuthenticationException('Access token not received');
    }

    // Save tokens securely
    await Future.wait([
      secureStorage.write(key: 'profile_${profileId}_access_token', value: result.accessToken),
      if (result.refreshToken != null)
        secureStorage.write(key: 'profile_${profileId}_refresh_token', value: result.refreshToken),
      secureStorage.write(key: 'profile_${profileId}_provider', value: provider.toString()),
    ]);

    return true;
  } catch (e, stackTrace) {
    throw AuthenticationException('Authentication error: $e\n$stackTrace');
  }
}

/// Refreshes the access token using the refresh token
Future<bool> _refreshToken(String profileId, String refreshToken, GitProvider provider) async {
  try {
    final config = provider == GitProvider.github ? githubOAuth : gitlabOAuth;
    final tokenResponse = await _appAuth.token(
      TokenRequest(
        config.clientId,
        'com.pass.app://auth/callback',
        serviceConfiguration: AuthorizationServiceConfiguration(
          authorizationEndpoint: config.authorizationEndpoint,
          tokenEndpoint: config.tokenEndpoint,
        ),
        refreshToken: refreshToken,
        clientSecret: config.clientSecret,
      ),
    );

    if (tokenResponse.accessToken == null) return false;

    await Future.wait([
      secureStorage.write(key: 'profile_${profileId}_access_token', value: tokenResponse.accessToken),
      if (tokenResponse.refreshToken != null)
        secureStorage.write(key: 'profile_${profileId}_refresh_token', value: tokenResponse.refreshToken),
    ]);

    return true;
  } catch (e) {
    return false;
  }
}

/// Checks if the user is authenticated with any provider
Future<bool> isAuthenticated(String profileId) async {
  try {
    final token = await secureStorage.read(key: 'profile_${profileId}_access_token');
    final provider = await secureStorage.read(key: 'profile_${profileId}_provider');
    return token != null && provider != null;
  } catch (e) {
    return false;
  }
}

/// Logs out the user by removing all stored tokens
Future<void> logout(String profileId) async {
  await Future.wait([
    secureStorage.delete(key: 'profile_${profileId}_access_token'),
    secureStorage.delete(key: 'profile_${profileId}_refresh_token'),
    secureStorage.delete(key: 'profile_${profileId}_provider'),
  ]);
}

/// Fetches user data from the authenticated provider
/// Returns a map containing user information
Future<Map<String, dynamic>> fetchUserData(String profileId) async {
  final token = await _getAccessToken(profileId);
  final provider = await _getProvider(profileId);

  final baseUrl = provider == GitProvider.github
      ? 'https://api.github.com'
      : 'https://gitlab.com/api/v4';

  final response = await http.get(
    Uri.parse('$baseUrl/user'),
    headers: _getAuthHeaders(provider, token),
  );

  if (response.statusCode == 200) {
    return json.decode(utf8.decode(response.bodyBytes));
  } else if (response.statusCode == 401) {
    // Token might be expired, try to refresh
    final refreshed = await _refreshTokenIfPossible(profileId);
    if (refreshed) {
      return fetchUserData(profileId); // Retry with new token
    }
    throw AuthenticationException('Authentication failed', response.body);
  } else {
    throw Exception('Failed to load user data: ${response.statusCode}');
  }
}

/// Fetches user repositories from the authenticated provider
/// Returns a list of GitRepository objects
Future<List<GitRepository>> fetchUserRepositories(String profileId) async {
  final token = await _getAccessToken(profileId);
  final provider = await _getProvider(profileId);

  final String url = provider == GitProvider.github
      ? 'https://api.github.com/user/repos?type=all&sort=updated&per_page=100'
      : 'https://gitlab.com/api/v4/projects?membership=true&order_by=last_activity_at&per_page=100';

  try {
    final response = await http.get(
      Uri.parse(url),
      headers: _getAuthHeaders(provider, token),
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
      return data.map((repoJson) => GitRepository.fromJson(repoJson, provider.toString())).toList();
    } else if (response.statusCode == 401) {
      // Token might be expired, try to refresh
      final refreshed = await _refreshTokenIfPossible(profileId);
      if (refreshed) {
        return fetchUserRepositories(profileId); // Retry with new token
      }
      throw AuthenticationException('Authentication failed', response.body);
    } else {
      throw Exception('Failed to load repositories: ${response.statusCode}');
    }
  } catch (e) {
    throw Exception('Error fetching repositories: $e');
  }
}

/// Helper method to get authentication headers
Map<String, String> _getAuthHeaders(GitProvider provider, String token) {
  return {
    'Authorization': '${provider == GitProvider.github ? 'token' : 'Bearer'} $token',
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };
}

/// Helper method to get access token with error handling
Future<String> _getAccessToken(String profileId) async {
  final token = await secureStorage.read(key: 'profile_${profileId}_access_token');
  if (token == null) {
    throw AuthenticationException('Not authenticated');
  }
  return token;
}

/// Helper method to get provider with error handling
Future<GitProvider> _getProvider(String profileId) async {
  final providerStr = await secureStorage.read(key: 'profile_${profileId}_provider');
  if (providerStr == null) {
    throw AuthenticationException('No provider found');
  }
  final provider = GitProvider.fromString(providerStr);
  if (provider == null) {
    throw AuthenticationException('Invalid provider string');
  }
  return provider;
}

/// Refreshes the token if possible
Future<bool> _refreshTokenIfPossible(String profileId) async {
  try {
    final refreshToken = await secureStorage.read(key: 'profile_${profileId}_refresh_token');
    final providerStr = await secureStorage.read(key: 'profile_${profileId}_provider');
    
    if (refreshToken == null || providerStr == null) {
      return false;
    }

    final provider = GitProvider.fromString(providerStr);
    if (provider == null) {
      return false;
    }
    return await _refreshToken(profileId, refreshToken, provider);
  } catch (e) {
    return false;
  }
}