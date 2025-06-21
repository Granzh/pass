import 'dart:async';
import 'dart:io';
import 'package:openpgp/openpgp.dart';

import '../logic/secure_storage.dart';
import '../models/gpg_key.dart';

class GPGService {

  // Key Management
  Future<void> saveKeyForProfileById(String profileId, GPGKey key) async {
    await secureStorage.write(key: 'gpg_${profileId}_public', value: key.publicKey);
    await secureStorage.write(key: 'gpg_${profileId}_private', value: key.privateKey);
    await secureStorage.write(key: 'gpg_${profileId}_passphrase', value: key.passphrase);
  }

  Future<GPGKey?> getKeyForProfileById(String profileId) async {
    final public = await secureStorage.read(key: 'gpg_${profileId}_public');
    final private = await secureStorage.read(key: 'gpg_${profileId}_private');
    final passphrase = await secureStorage.read(key: 'gpg_${profileId}_passphrase');

    if (public != null && private != null && passphrase != null) {
      return GPGKey(
        profileId: profileId,
        publicKey: public,
        privateKey: private,
        passphrase: passphrase,
      );
    }
    return null;
  }

  Future<bool> hasKeyForProfileById(String profileId) async {
    return await getKeyForProfileById(profileId) != null;
  }

  Future<void> deleteKeyForProfileById(String profileId) async {
    await secureStorage.delete(key: 'gpg_${profileId}_public');
    await secureStorage.delete(key: 'gpg_${profileId}_private');
    await secureStorage.delete(key: 'gpg_${profileId}_passphrase');
  }

  // GPG Operations
  Future<String> encryptPassword(String password, String recipientPublicKey) async {
    try {
      // Encrypt the message
      final encrypted = await OpenPGP.encrypt(
        password,
        recipientPublicKey,
      );
      return encrypted;
    } catch (e) {
      throw Exception('Failed to encrypt password: $e');
    }
  }

  Future<String> decryptPassword(String encryptedData, String privateKey, String passphrase) async {
    try {
      // Decrypt the message
      final decrypted = await OpenPGP.decrypt(
        encryptedData,
        privateKey,
        passphrase,
      );
      return decrypted;
    } catch (e) {
      throw Exception('Failed to decrypt password: $e');
    }
  }

  // Key Generation and Management
  Future<GPGKey> generateKeyPair(String userId, String passphrase) async {
    try {
      // Configure key options
      final keyOptions = KeyOptions()
        ..rsaBits = 4096
        ..algorithm = Algorithm.RSA
        ..hash = Hash.SHA256
        ..cipher = Cipher.AES256;

      // Generate key pair
      final keyPair = await OpenPGP.generate(
        options: Options()
          ..name = userId
          ..email = '$userId@pass.app'
          ..passphrase = passphrase
          ..keyOptions = keyOptions,
      );

      return GPGKey(
        profileId: userId,
        publicKey: keyPair.publicKey,
        privateKey: keyPair.privateKey,
        passphrase: passphrase,
      );
    } catch (e) {
      throw Exception('Failed to generate key pair: $e');
    }
  }

  // File Operations
  Future<void> encryptFile(
    String inputFilePath,
    String outputFilePath,
    String recipientPublicKey,
  ) async {
    try {
      // Read the file content
      final inputFile = File(inputFilePath);
      final fileContent = await inputFile.readAsString();

      // Encrypt the file content
      final encrypted = await OpenPGP.encrypt(
        fileContent,
        recipientPublicKey,
      );

      // Write the encrypted content to output file
      final outputFile = File(outputFilePath);
      await outputFile.writeAsString(encrypted);
    } catch (e) {
      throw Exception('Failed to encrypt file: $e');
    }
  }

  Future<void> decryptFile(
    String inputFilePath,
    String outputFilePath,
    String privateKey,
    String passphrase,
  ) async {
    try {
      // Read the encrypted file
      final inputFile = File(inputFilePath);
      final encryptedData = await inputFile.readAsString();

      // Decrypt the file content
      final decrypted = await OpenPGP.decrypt(
        encryptedData,
        privateKey,
        passphrase,
      );

      // Write the decrypted content to output file
      final outputFile = File(outputFilePath);
      await outputFile.writeAsString(decrypted);
    } catch (e) {
      throw Exception('Failed to decrypt file: $e');
    }
  }

  // Sign and Verify
  Future<String> signMessage(String message, String privateKey, String passphrase) async {
    try {
      final signature = await OpenPGP.sign(
        message,
        privateKey,
        passphrase,
      );
      return signature;
    } catch (e) {
      throw Exception('Failed to sign message: $e');
    }
  }

  Future<bool> verifySignature(
    String message,
    String signature,
    String publicKey,
  ) async {
    try {
      final verified = await OpenPGP.verify(
        message,
        signature,
        publicKey,
      );
      return verified;
    } catch (e) {
      throw Exception('Failed to verify signature: $e');
    }
  }
}