import 'package:flutter_test/flutter_test.dart';
import 'package:pass/models/gpg_key.dart';

void main() {
  group('GPGKey', () {
    const testProfileId = 'profile-123';
    const testPublicKey = '-----BEGIN PGP PUBLIC KEY BLOCK-----...';
    const testPrivateKey = '-----BEGIN PGP PRIVATE KEY BLOCK-----...';
    const testPassphrase = 'supersecret';

    final gpgKeyDataMap = {
      'publicKey': testPublicKey,
      'privateKey': testPrivateKey,
      'passphrase': testPassphrase,
    };

    test('Constructor should correctly initialize fields', () {
      final gpgKey = GPGKey(
        profileId: testProfileId,
        publicKey: testPublicKey,
        privateKey: testPrivateKey,
        passphrase: testPassphrase,
      );

      expect(gpgKey.profileId, testProfileId);
      expect(gpgKey.publicKey, testPublicKey);
      expect(gpgKey.privateKey, testPrivateKey);
      expect(gpgKey.passphrase, testPassphrase);
    });

    group('toJson()', () {
      test('should return a map with correct key-value pairs and exclude profileId', () {
        final gpgKey = GPGKey(
          profileId: testProfileId,
          publicKey: testPublicKey,
          privateKey: testPrivateKey,
          passphrase: testPassphrase,
        );
        final json = gpgKey.toJson();

        expect(json, equals(gpgKeyDataMap));
        expect(json.containsKey('profileId'), isFalse);
      });
    });

    group('fromJson() factory', () {
      test('should correctly create a GPGKey object from profileId and map', () {
        final gpgKey = GPGKey.fromJson(testProfileId, gpgKeyDataMap);

        expect(gpgKey.profileId, testProfileId);
        expect(gpgKey.publicKey, testPublicKey);
        expect(gpgKey.privateKey, testPrivateKey);
        expect(gpgKey.passphrase, testPassphrase);
      });

      test('should throw an error if publicKey is missing', () {
        final incompleteJson = Map<String, dynamic>.from(gpgKeyDataMap)..remove('publicKey');
        expect(
              () => GPGKey.fromJson(testProfileId, incompleteJson),
          throwsA(isA<TypeError>()),
        );
      });

      test('should throw an error if privateKey is missing', () {
        final incompleteJson = Map<String, dynamic>.from(gpgKeyDataMap)..remove('privateKey');
        expect(
              () => GPGKey.fromJson(testProfileId, incompleteJson),
          throwsA(isA<TypeError>()),
        );
      });

      test('should throw an error if passphrase is missing', () {
        final incompleteJson = Map<String, dynamic>.from(gpgKeyDataMap)..remove('passphrase');
        expect(
              () => GPGKey.fromJson(testProfileId, incompleteJson),
          throwsA(isA<TypeError>()),
        );
      });
    });
  });
}
