import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import '../../core/utils/enums.dart';
import 'app_oauth_service.dart';

class SecureGitAuth {
  final FlutterSecureStorage _secureStorage;
  final DeviceInfoPlugin _deviceInfo;
  final http.Client _httpClient;

  static final _log = Logger('SecureGitAuth');

  SecureGitAuth({
    required FlutterSecureStorage secureStorage,
    required DeviceInfoPlugin deviceInfo,
    http.Client? httpClient,
  })  : _secureStorage = secureStorage,
        _deviceInfo = deviceInfo,
        _httpClient = httpClient ?? http.Client();


  static String _getTokenKey(GitProvider provider) => 'git_token_${provider.name}';
  static String _getRefreshTokenKey(GitProvider provider) => 'git_refresh_token_${provider.name}';
  static String _getTokenHashKey(GitProvider provider) => 'git_token_hash_${provider.name}';
  static String _getDeviceIdKey() => 'device_id';

  static String _createTokenHash(String token, String deviceId) {
    final combined = '$token-$deviceId';
    return sha256.convert(utf8.encode(combined)).toString();
  }


  Future<String> _getDeviceId() async {
    String? deviceId = await _secureStorage.read(key: _getDeviceIdKey());

    if (deviceId == null) {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        deviceId = androidInfo.id;
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        deviceId = iosInfo.identifierForVendor ?? 'unknown_ios_device';
      } else {
        deviceId = 'unknown_platform_device';
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final combined = '$deviceId-$timestamp';
      deviceId = sha256.convert(utf8.encode(combined)).toString().substring(0, 16);

      await _secureStorage.write(key: _getDeviceIdKey(), value: deviceId);
    }
    return deviceId;
  }

  Future<Map<String, String>> authenticateGitHubWithPkce({
    required String clientId,
    required String code,
    required String redirectUri,
    required String codeVerifier,
    List<String> scopes = const ['repo'],
  }) async {
    try {
      final deviceId = await _getDeviceId();

      final response = await _httpClient.post(
        Uri.parse('https://github.com/login/oauth/access_token'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'client_id': clientId,
          'code': code,
          'redirect_uri': redirectUri,
          'grant_type': 'authorization_code',
          'code_verifier': codeVerifier,
        },
      );

      if (response.statusCode != 200) {
        _log.severe('GitHub PKCE token exchange failed. Status: ${response.statusCode}, Body: ${response.body}');
        throw Exception('Failed to authenticate with GitHub (PKCE): ${response.statusCode}');
      }

      final data = json.decode(response.body);
      final accessToken = data['access_token'] as String?;
      final refreshToken = data['refresh_token'] as String?;

      if (accessToken == null) {
        _log.severe('GitHub PKCE: No access token received. Data: $data');
        throw Exception('No access token received from GitHub (PKCE)');
      }

      final tokenHash = _createTokenHash(accessToken, deviceId);

      await _secureStorage.write(key: _getTokenKey(GitProvider.github), value: accessToken);
      await _secureStorage.write(key: _getTokenHashKey(GitProvider.github), value: tokenHash);

      if (refreshToken != null && refreshToken.isNotEmpty) {
        await _secureStorage.write(key: _getRefreshTokenKey(GitProvider.github), value: refreshToken);
      } else {
        await _secureStorage.delete(key: _getRefreshTokenKey(GitProvider.github));
      }

      return {
        'access_token': accessToken,
        'refresh_token': refreshToken ?? '',
        'provider': GitProvider.github.name,
      };
    } catch (e) {
      _log.severe('GitHub PKCE authentication failed: $e');
      throw Exception('GitHub PKCE authentication process failed: $e');
    }
  }

  Future<Map<String, String>> authenticateGitLabWithPkce({
    required String clientId,
    required String code,
    required String redirectUri,
    required String codeVerifier,
    String baseUrl = 'https://gitlab.com',
    List<String> scopes = const ['api', 'read_user'],
  }) async {
    try {
      final deviceId = await _getDeviceId();

      final response = await _httpClient.post(
        Uri.parse('$baseUrl/oauth/token'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'client_id': clientId,
          'code': code,
          'grant_type': 'authorization_code',
          'redirect_uri': redirectUri,
          'code_verifier': codeVerifier,
        },
      );

      if (response.statusCode != 200) {
        _log.severe('GitLab PKCE token exchange failed. Status: ${response.statusCode}, Body: ${response.body}');
        throw Exception('Failed to authenticate with GitLab (PKCE): ${response.statusCode}');
      }

      final data = json.decode(response.body);
      final accessToken = data['access_token'] as String?;
      final refreshToken = data['refresh_token'] as String?;

      if (accessToken == null) {
        _log.severe('GitLab PKCE: No access token received. Data: $data');
        throw Exception('No access token received from GitLab (PKCE)');
      }

      final tokenHash = _createTokenHash(accessToken, deviceId);

      await _secureStorage.write(key: _getTokenKey(GitProvider.gitlab), value: accessToken);
      await _secureStorage.write(key: _getTokenHashKey(GitProvider.gitlab), value: tokenHash);

      if (refreshToken != null && refreshToken.isNotEmpty) {
        await _secureStorage.write(key: _getRefreshTokenKey(GitProvider.gitlab), value: refreshToken);
      } else {
        await _secureStorage.delete(key: _getRefreshTokenKey(GitProvider.gitlab));
      }

      return {
        'access_token': accessToken,
        'refresh_token': refreshToken ?? '',
        'provider': GitProvider.gitlab.name,
      };
    } catch (e) {
      _log.severe('GitLab PKCE authentication failed: $e');
      throw Exception('GitLab PKCE authentication process failed: $e');
    }
  }

  Future<bool> authenticateWithPAT({
    required GitProvider provider,
    required String token,
    String? baseUrl,
  }) async {
    try {
      final deviceId = await _getDeviceId();
      final isValid = await _validateToken(provider, token, baseUrl);

      if (!isValid) {
        throw Exception('Invalid token');
      }

      final tokenHash = _createTokenHash(token, deviceId);

      await _secureStorage.write(key: _getTokenKey(provider), value: token);
      await _secureStorage.write(key: _getTokenHashKey(provider), value: tokenHash);
      return true;
    } catch (e) {
      _log.warning('PAT authentication for ${provider.name} failed: $e');
      return false;
    }
  }

  Future<bool> _validateToken(GitProvider provider, String token, String? baseUrl) async {
    try {
      String url;
      Map<String, String> headers;

      if (provider == GitProvider.github) {
        url = 'https://api.github.com/user';
        headers = _getAuthHeadersLogic(provider, token);
      } else { // GitLab
        final effectiveBaseUrl = baseUrl ?? 'https://gitlab.com';
        url = '$effectiveBaseUrl/api/v4/user';
        headers = _getAuthHeadersLogic(provider, token);
      }

      final response = await _httpClient.get(Uri.parse(url), headers: headers);
      if (response.statusCode != 200) {
        _log.warning('Token validation failed for ${provider.name}. Status: ${response.statusCode}, Body: ${response.body}');
      }
      return response.statusCode == 200;
    } catch (e) {
      _log.severe('Error validating token for ${provider.name}: $e');
      return false;
    }
  }

  Future<String?> getToken(GitProvider provider) async {
    try {
      final token = await _secureStorage.read(key: _getTokenKey(provider));
      final savedHash = await _secureStorage.read(key: _getTokenHashKey(provider));

      if (token == null || savedHash == null) {
        _log.fine('No token or hash found in storage for ${provider.name}.');
        return null;
      }

      final deviceId = await _getDeviceId();
      final currentHash = _createTokenHash(token, deviceId);

      if (currentHash != savedHash) {
        _log.warning('Token hash mismatch for ${provider.name}. Clearing tokens.');
        await clearTokens(provider);
        return null;
      }
      _log.fine('Valid token retrieved from storage for ${provider.name}.');
      return token;
    } catch (e) {
      _log.severe('Error getting token for ${provider.name}: $e');
      return null;
    }
  }

  Future<String?> refreshToken(GitProvider provider, {
    required String clientId,
    String? clientSecret,
    String? baseUrl,
  }) async {
    try {
      final storedRefreshToken = await _secureStorage.read(key: _getRefreshTokenKey(provider));

      if (storedRefreshToken == null) {
        _log.warning('No refresh token found for provider ${provider.name} to refresh.');
        return null;
      }

      String url;
      Map<String, String> body;
      final effectiveBaseUrl = baseUrl ?? (provider == GitProvider.gitlab ? 'https://gitlab.com' : 'https://github.com');


      if (provider == GitProvider.github) {
        url = '$effectiveBaseUrl/login/oauth/access_token';
        body = {
          'client_id': clientId,
          'grant_type': 'refresh_token',
          'refresh_token': storedRefreshToken,
        };
      } else { // GitLab
        url = '$effectiveBaseUrl/oauth/token';
        body = {
          'client_id': clientId,
          'grant_type': 'refresh_token',
          'refresh_token': storedRefreshToken,
          'redirect_uri': gitlabRedirectUri,
        };
        if (clientSecret != null && clientSecret.isNotEmpty) {
          body['client_secret'] = clientSecret;
        }
      }

      _log.info('Attempting to refresh token for ${provider.name}');
      final response = await _httpClient.post(
        Uri.parse(url),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: body,
      );

      if (response.statusCode != 200) {
        _log.severe('Failed to refresh token for ${provider.name}. Status: ${response.statusCode}, Body: ${response.body}');
        if (response.statusCode == 400 || response.statusCode == 401) {
          _log.warning('Refresh token for ${provider.name} might be invalid. Clearing stored tokens.');
          await clearTokens(provider);
        }
        return null;
      }

      final data = json.decode(response.body);
      final newAccessToken = data['access_token'] as String?;
      final newRefreshToken = data['refresh_token'] as String?;

      if (newAccessToken != null) {
        final deviceId = await _getDeviceId();
        final tokenHash = _createTokenHash(newAccessToken, deviceId);

        await _secureStorage.write(key: _getTokenKey(provider), value: newAccessToken);
        await _secureStorage.write(key: _getTokenHashKey(provider), value: tokenHash);
        _log.fine('Successfully refreshed access token for ${provider.name}.');

        if (newRefreshToken != null && newRefreshToken.isNotEmpty) {
          await _secureStorage.write(key: _getRefreshTokenKey(provider), value: newRefreshToken);
          _log.fine('Updated refresh token for ${provider.name}.');
        } else {
          _log.fine('No new refresh token received for ${provider.name}, old one remains if it was valid.');
        }
        return newAccessToken;
      } else {
        _log.warning('No new access token received after refresh attempt for ${provider.name}. Data: $data');
        return null;
      }
    } catch (e, s) {
      _log.severe('Error refreshing token for ${provider.name}: $e', e, s);
      return null;
    }
  }

  Future<bool> isAuthenticated(GitProvider provider) async {
    final token = await getToken(provider);
    return token != null;
  }

  Future<void> clearTokens(GitProvider provider) async {
    await _secureStorage.delete(key: _getTokenKey(provider));
    await _secureStorage.delete(key: _getRefreshTokenKey(provider));
    await _secureStorage.delete(key: _getTokenHashKey(provider));
    _log.info('Cleared tokens for ${provider.name}.');
  }

  Future<void> clearAllTokens() async {
    for (final provider in GitProvider.values) {
      await clearTokens(provider);
    }
    await _secureStorage.delete(key: _getDeviceIdKey());
    _log.info('Cleared all tokens and device ID.');
  }

  static Map<String, String> _getAuthHeadersLogic(GitProvider provider, String token) {
    if (provider == GitProvider.github) {
      return {
        'Authorization': 'token $token',
        'Accept': 'application/vnd.github.v3+json',
      };
    } else { // GitLab
      return {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };
    }
  }

  Future<Map<String, String>?> getAuthHeaders(GitProvider provider) async {
    final token = await getToken(provider);
    if (token == null) {
      return null;
    }
    return _getAuthHeadersLogic(provider, token);
  }


  Future<Map<String, String>?> getValidAuthHeaders(
      GitProvider provider, {
        required String clientId,
        String? clientSecret,
        String? baseUrl,
      }) async {
    final token = await getToken(provider);

    if (token == null) {
      _log.fine('No token found by getToken for ${provider.name}. Attempting refresh if possible.');
      final newToken = await refreshToken(
          provider,
          clientId: clientId,
          clientSecret: clientSecret,
          baseUrl: baseUrl
      );
      if (newToken != null) {
        _log.fine('Token refreshed successfully for ${provider.name} during getValidAuthHeaders.');
        return _getAuthHeadersLogic(provider, newToken);
      }
      _log.warning('No valid token and failed to refresh for ${provider.name}.');
      return null;
    }

    final isValid = await _validateToken(provider, token, baseUrl);

    if (!isValid) {
      _log.warning('Token for ${provider.name} is invalid. Attempting to refresh.');
      final newToken = await refreshToken(
          provider,
          clientId: clientId,
          clientSecret: clientSecret,
          baseUrl: baseUrl
      );
      if (newToken != null) {
        _log.fine('Token refreshed successfully for ${provider.name} after validation failed.');
        return _getAuthHeadersLogic(provider, newToken);
      }
      _log.warning('Failed to refresh invalid token for ${provider.name}. Clearing tokens.');
      await clearTokens(provider);
      return null;
    }

    _log.fine('Token for ${provider.name} is valid.');
    return _getAuthHeadersLogic(provider, token);
  }
}
