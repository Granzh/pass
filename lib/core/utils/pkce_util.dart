import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

class PkceUtil {
  static const int _codeVerifierLength = 64;

  static String generateCodeVerifier() {
    final random = Random.secure();
    final bytes = List<int>.generate(_codeVerifierLength, (_) => random.nextInt(256));

    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String generateCodeChallengeS256(String codeVerifier) {
    final bytes = utf8.encode(codeVerifier);
    final digest = sha256.convert(bytes);

    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  static String get codeChallengeMethodS256 => 'S256';
}