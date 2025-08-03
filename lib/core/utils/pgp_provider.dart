import 'package:openpgp/openpgp.dart' as pgp;

typedef PGPKeyOptions = pgp.KeyOptions;
typedef PGPOptions = pgp.Options;
typedef PGPKeyPair = pgp.KeyPair;


abstract class PGPProvider {
  Future<String> encrypt(String text, String publicKey);
  Future<String> decrypt(String encryptedText, String privateKey, String passphrase);
  Future<PGPKeyPair> generate({required PGPOptions options});
  Future<String> sign(String text, String privateKey, String passphrase);
  Future<bool> verify(String text, String signature, String publicKey);
}


class DefaultPGPProvider implements PGPProvider {
  @override
  Future<String> encrypt(String text, String publicKey) {
    return pgp.OpenPGP.encrypt(text, publicKey);
  }

  @override
  Future<String> decrypt(String encryptedText, String privateKey, String passphrase) {
    return pgp.OpenPGP.decrypt(encryptedText, privateKey, passphrase);
  }

  @override
  Future<PGPKeyPair> generate({required PGPOptions options}) {
    return pgp.OpenPGP.generate(options: options);
  }

  @override
  Future<String> sign(String text, String privateKey, String passphrase) {
    return pgp.OpenPGP.sign(text, privateKey, passphrase);
  }

  @override
  Future<bool> verify(String text, String signature, String publicKey) {
    return pgp.OpenPGP.verify(text, signature, publicKey);
  }
}