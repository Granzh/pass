import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logging/logging.dart';
import 'dart:math';

import 'package:url_launcher/url_launcher.dart';

import '../../core/utils/enums.dart';
import '../../core/utils/pkce_util.dart';
import 'git_auth.dart';

const String githubRedirectUri = 'passapp://auth/callback';

const String gitlabRedirectUri = 'myapp://gitlab-oauth';
const String gitlabBaseUrl = 'https://gitlab.com';


class OAuthResult {
  final Map<String, String> authTokens;
  OAuthResult({required this.authTokens});
}

class AppOAuthService {
  static final _log = Logger('AppOAuthService');
  StreamSubscription? _linkSubscription;
  String? _lastGeneratedState;
  String? _currentCodeVerifier;

  final AppLinks _appLinks;
  final SecureGitAuth _secureGitAuth;

  late final githubClientId = dotenv.env['GITHUB_CLIENT_ID']!;
  late final gitlabClientId = dotenv.env['GITLAB_CLIENT_ID']!;


  AppOAuthService({
    required AppLinks appLinks,
    required SecureGitAuth secureGitAuth
  }):
        _appLinks = appLinks,
        _secureGitAuth = secureGitAuth;




  Future<OAuthResult> authenticate(PasswordSourceType sourceType) async {
    final completer = Completer<OAuthResult>();
    String? authorizationCode;

    String authUrl;
    String expectedRedirectScheme;
    List<String> scopes;

    _lastGeneratedState = _generateState();
    _currentCodeVerifier = PkceUtil.generateCodeVerifier();
    final codeChallenge = PkceUtil.generateCodeChallengeS256(_currentCodeVerifier!);

    if (sourceType == PasswordSourceType.github) {
      scopes = ['repo', 'user:email'];
      authUrl = 'https://github.com/login/oauth/authorize'
          '?client_id=$githubClientId'
          '&redirect_uri=${Uri.encodeComponent(githubRedirectUri)}'
          '&scope=${Uri.encodeComponent(scopes.join(' '))}'
          '&response_type=code'
          '&state=$_lastGeneratedState'
          '&code_challenge=$codeChallenge'
          '&code_challenge_method=${PkceUtil.codeChallengeMethodS256}';
      expectedRedirectScheme = Uri.parse(githubRedirectUri).scheme;
    } else if (sourceType == PasswordSourceType.gitlab) {
      scopes = ['api', 'read_user', 'read_repository', 'write_repository', 'openid', 'profile', 'email'];
      authUrl = '$gitlabBaseUrl/oauth/authorize'
          '?client_id=$gitlabClientId'
          '&redirect_uri=${Uri.encodeComponent(gitlabRedirectUri)}'
          '&response_type=code'
          '&scope=${Uri.encodeComponent(scopes.join(' '))}'
          '&state=$_lastGeneratedState'
          '&code_challenge=$codeChallenge'
          '&code_challenge_method=${PkceUtil.codeChallengeMethodS256}';
      expectedRedirectScheme = Uri.parse(gitlabRedirectUri).scheme;
    } else {
      completer.completeError(ArgumentError('Unsupported source type for OAuth: $sourceType'));
      return completer.future;
    }

    _linkSubscription?.cancel();

    bool initialLinkHandled = false;

    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _log.info('Handling initial link: $initialUri');
        await _handleRedirectUri(initialUri, expectedRedirectScheme, completer, authorizationCode, sourceType, scopes);
        if (completer.isCompleted) initialLinkHandled = true;
      }
    } catch (e) {
      _log.warning('Failed to get initialAppLink or not a valid URI: $e');
    }

    if (initialLinkHandled) {
      _log.info('Initial link handled, not subscribing to uriLinkStream for this auth attempt.');
      return completer.future;
    }

    _linkSubscription = _appLinks.uriLinkStream.listen((Uri? uri) async {
      if (completer.isCompleted) {
        _log.info('uriLinkStream event received, but completer is already completed. URI: $uri');
        _linkSubscription?.cancel();
        _linkSubscription = null;
        return;
      }
      await _handleRedirectUri(uri, expectedRedirectScheme, completer, authorizationCode, sourceType, scopes);
    }, onError: (err) {
      _log.severe('Error listening to uni_links: $err');
      _linkSubscription?.cancel();
      _linkSubscription = null;
      _currentCodeVerifier = null;
      _lastGeneratedState = null;
      completer.completeError('Failed to listen for OAuth callback: $err');
    });

    _log.info('Launching PKCE OAuth URL: $authUrl');
    if (await canLaunchUrl(Uri.parse(authUrl))) {
      await launchUrl(
        Uri.parse(authUrl),
        mode: LaunchMode.externalApplication,
      );
    } else {
      _linkSubscription?.cancel();
      _linkSubscription = null;
      _currentCodeVerifier = null;
      _lastGeneratedState = null;
      completer.completeError('Could not launch OAuth URL: $authUrl');
    }

    return completer.future;
  }

  Future<void> _handleRedirectUri(Uri? uri, String expectedRedirectScheme, Completer<OAuthResult> completer, String? authorizationCode, PasswordSourceType sourceType, List<String> scopes) async {
    if (uri != null && uri.scheme == expectedRedirectScheme) {
      _log.info('Received redirect URI: $uri');
      _linkSubscription?.cancel();
      _linkSubscription = null;

      final queryParams = uri.queryParameters;


      if (queryParams['state'] == null || queryParams['state'] != _lastGeneratedState) {
        _log.severe('OAuth Error: State mismatch. Possible CSRF attack.');
        completer.completeError('OAuth Error: State mismatch. Please try again.');
        return;
      }
      _lastGeneratedState = null;

      if (queryParams.containsKey('code')) {
        authorizationCode = queryParams['code'];
        _log.finer('Authorization code received: $authorizationCode');

        if (_currentCodeVerifier == null) {
          _log.severe('OAuth Error: Code verifier is missing for token exchange.');
          completer.completeError('OAuth Error: Internal error (missing code verifier).');
          return;
        }

        try {
          Map<String, String> tokens;
          // GitProvider provider = sourceType == PasswordSourceType.github ? GitProvider.github : GitProvider.gitlab;

          if (sourceType == PasswordSourceType.github) { //GiHub
            tokens = await _secureGitAuth.authenticateGitHubWithPkce(
              clientId: githubClientId,
              code: authorizationCode!,
              redirectUri: githubRedirectUri,
              codeVerifier: _currentCodeVerifier!,
              scopes: scopes,
            );
          } else { // GitLab
            tokens = await _secureGitAuth.authenticateGitLabWithPkce(
              clientId: gitlabClientId,
              code: authorizationCode!,
              redirectUri: gitlabRedirectUri,
              codeVerifier: _currentCodeVerifier!,
              baseUrl: gitlabBaseUrl,
              scopes: scopes,
            );
          }
          _currentCodeVerifier = null;
          completer.complete(OAuthResult(authTokens: tokens));
        } catch (e) {
          _log.severe('Error exchanging code for token with PKCE: $e');
          _currentCodeVerifier = null;
          completer.completeError('Failed to exchange authorization code: $e');
        }
      } else if (queryParams.containsKey('error')) {
        _log.warning('OAuth error from provider: ${queryParams['error_description'] ?? queryParams['error']}');
        completer.completeError('OAuth error: ${queryParams['error_description'] ?? queryParams['error']}');
      } else {
        completer.completeError('OAuth callback did not contain code or error.');
      }
    }
  }

  String _generateState() {
    return List<int>.generate(16, (_) => Random.secure().nextInt(256))
        .map((i) => i.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  void dispose() {
    _linkSubscription?.cancel();
    _linkSubscription = null;
    _currentCodeVerifier = null;
    _lastGeneratedState = null;
  }
}