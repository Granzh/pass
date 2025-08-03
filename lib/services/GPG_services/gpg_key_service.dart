import 'dart:async';
import 'package:file/file.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logging/logging.dart';
import 'package:pass/core/utils/pgp_provider.dart';
import 'package:openpgp/openpgp.dart' as openpgp;

import '../../models/gpg_key.dart';
import 'gpg_key_service_exception.dart';

class GPGService {
  final FlutterSecureStorage _secureStorage;
  final PGPProvider _pgpProvider;
  final FileSystem _fileSystem;

  GPGService({
    required FlutterSecureStorage secureStorage,
    required PGPProvider pgpProvider,
    required FileSystem fileSystem}):
    _secureStorage = secureStorage,
    _pgpProvider = pgpProvider,
    _fileSystem = fileSystem;


  static final _log = Logger('GPGService');

  // Key Management
  Future<void> saveKeyForProfileById(String profileId, GPGKey key) async {
    await _secureStorage.write(key: 'gpg_${profileId}_public', value: key.publicKey);
    await _secureStorage.write(key: 'gpg_${profileId}_private', value: key.privateKey);
    await _secureStorage.write(key: 'gpg_${profileId}_passphrase', value: key.passphrase);
  }

  Future<GPGKey?> getKeyForProfileById(String profileId) async {
    final public = await _secureStorage.read(key: 'gpg_${profileId}_public');
    final private = await _secureStorage.read(key: 'gpg_${profileId}_private');
    final passphrase = await _secureStorage.read(key: 'gpg_${profileId}_passphrase');

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
    await _secureStorage.delete(key: 'gpg_${profileId}_public');
    await _secureStorage.delete(key: 'gpg_${profileId}_private');
    await _secureStorage.delete(key: 'gpg_${profileId}_passphrase');
  }

  // GPG Operations
  Future<String> encryptPassword(String password, String recipientPublicKey) async {
    try {
      // Encrypt the message
      final encrypted = await _pgpProvider.encrypt(password, recipientPublicKey);
      return encrypted;
    } catch (e) {
      _log.severe('Failed to encrypt password: $e', e);
      throw GPGEncryptionException('Failed to encrypt password: $e');
    }
  }

  Future<String> decryptPassword(String encryptedData, String privateKey, String passphrase) async {
    try {
      // Decrypt the message
      final decrypted = await _pgpProvider.decrypt(
        encryptedData,
        privateKey,
        passphrase,
      );
      return decrypted;
    } catch (e, s) {
      _log.severe('Failed to decrypt password: $e', e, s);
      bool isPassphraseError = e.toString().toLowerCase().contains('bad passphrase') ||
          e.toString().toLowerCase().contains('incorrect pass') ||
          e.toString().toLowerCase().contains('decryption failed');
      throw GPGDecryptionException(
          'Could not decrypt password.',
          isPassphraseError: isPassphraseError,
          cause: e,
          stackTrace: s,
      );
    }
  }

  Future<void> importPrivateKeyForProfile({
    required String profileId,
    required String privateKeyArmored,
    required String passphraseForImportedKey, // passphrase of imported key
    String? publicKeyArmored,
  }) async {
    try {
      String finalPublicKey = publicKeyArmored ?? '';
      if (finalPublicKey.isEmpty) {
        _log.info("Warning: Importing private key for profile $profileId without a public key. Encryption may rely on the private key itself or fail.");
      }

      GPGKey key = GPGKey(profileId: profileId, publicKey: publicKeyArmored ?? '', privateKey: privateKeyArmored, passphrase: passphraseForImportedKey);
      await saveKeyForProfileById(
        profileId,
        key
      );
    } catch (e, s) {
      _log.severe('Failed to import GPG private key for profile $profileId: $e', e, s);
      throw GPGImportException('Could not import private key.', cause: e, stackTrace: s);
    }
  }

  // Key Generation and Management
  Future<GPGKey> generateNewKeyForProfile({required String profileId, required String passphrase,required String? userName,required String? userEmail}) async {
    try {
      final openpgp.Options pgpOptionsInstance = openpgp.Options();

      pgpOptionsInstance.name = userName ?? profileId;
      pgpOptionsInstance.email = userEmail ?? '$profileId@pass.app';
      pgpOptionsInstance.passphrase = passphrase;

      pgpOptionsInstance.keyOptions = openpgp.KeyOptions();
      pgpOptionsInstance.keyOptions!.rsaBits = 4096;
      pgpOptionsInstance.keyOptions!.algorithm = openpgp.Algorithm.RSA;
      pgpOptionsInstance.keyOptions!.hash = openpgp.Hash.SHA256;
      pgpOptionsInstance.keyOptions!.cipher = openpgp.Cipher.AES256;

      final keyPair = await _pgpProvider.generate(options: pgpOptionsInstance);

      GPGKey gpgKey = GPGKey(
        profileId: profileId,
        publicKey: keyPair.publicKey,
        privateKey: keyPair.privateKey,
        passphrase: passphrase,
      );

      saveKeyForProfileById(profileId, gpgKey);

      return gpgKey;
    } catch (e, s) {
      _log.severe('Failed to import GPG private key for profile $profileId: $e', e, s);
      throw GPGImportException('Could not import private key.', cause: e, stackTrace: s);
    }
  }

  // File Operations
  Future<void> encryptFile(
    String inputFilePath,
    String outputFilePath,
    String recipientPublicKey,
  ) async {
    try {
      final inputFile = _fileSystem.file(inputFilePath);
      if (!await inputFile.exists()) {
        throw Exception('Input file not found: $inputFilePath');
      }
      final fileContent = await inputFile.readAsString();
      final encrypted = await _pgpProvider.encrypt(fileContent, recipientPublicKey);
      final outputFile = _fileSystem.file(outputFilePath);
      await outputFile.create(recursive: true);
      await outputFile.writeAsString(encrypted);
      _log.info('Successfully encrypted file $inputFilePath to $outputFilePath');
    } catch (e, s) {
      _log.severe('Failed to encrypt file $inputFilePath: $e', e, s);
      if (e is GPGFileOperationException) rethrow;
      if (e is FileSystemException) {
        throw GPGFileOperationException('OS error during file encryption.', e.path ?? inputFilePath, cause: e, stackTrace: s);
      }
      throw GPGEncryptionException('Could not encrypt file content.', cause: e, stackTrace: s);
    }
  }

  Future<void> decryptFile(
    String inputFilePath,
    String outputFilePath,
    String privateKey,
    String passphrase,
  ) async {
    try {
      final inputFile = _fileSystem.file(inputFilePath);
      if (!await inputFile.exists()) {
        throw Exception('Input file not found: $inputFilePath');
      }
      final encryptedData = await inputFile.readAsString();
      final decrypted = await _pgpProvider.decrypt(encryptedData, privateKey, passphrase);
      final outputFile = _fileSystem.file(outputFilePath);
      await outputFile.create(recursive: true);
      await outputFile.writeAsString(decrypted);
      _log.info('Successfully decrypted file $inputFilePath to $outputFilePath');
    } catch (e, s) {
      _log.severe('Failed to decrypt file $inputFilePath: $e', e, s);
      if (e is GPGFileOperationException) rethrow;
      if (e is FileSystemException) {
        throw GPGFileOperationException('OS error during file decryption.', e.path ?? inputFilePath, cause: e, stackTrace: s);
      }
      bool isPassphraseError = e.toString().toLowerCase().contains('bad passphrase') ||
          e.toString().toLowerCase().contains('incorrect pass') ||
          e.toString().toLowerCase().contains('decryption failed');
      throw GPGDecryptionException(
        'Could not decrypt file content.',
        isPassphraseError: isPassphraseError,
        cause: e,
        stackTrace: s,
      );
    }
  }

  Future<String> encryptDataForProfile(String data, String profileId) async {
    final gpgKey = await getKeyForProfileById(profileId);
    if (gpgKey == null || gpgKey.publicKey.isEmpty) {
      _log.warning('Public GPG key not found or is empty for profile $profileId. Cannot encrypt data.');
      throw Exception('Public GPG key not found or is empty for profile $profileId. Cannot encrypt data.');
    }
    try {
      return await _pgpProvider.encrypt(data, gpgKey.publicKey);
    } catch (e, s) {
      _log.severe('Failed to encrypt data for profile $profileId: $e', e, s);
      throw GPGEncryptionException('Could not encrypt data for profile $profileId.', cause: e, stackTrace: s);
    }
  }

  Future<String> decryptDataForProfile(
      String encryptedData,
      String profileId,
      String userProvidedPassphrase,
      ) async {
    final gpgKey = await getKeyForProfileById(profileId);
    if (gpgKey == null) {
      _log.warning('GPG key not found for profile $profileId. Cannot decrypt data.');
      throw Exception('GPG key not found for profile $profileId. Cannot decrypt data.');
    }

    try {
      return await _pgpProvider.decrypt(encryptedData, gpgKey.privateKey, userProvidedPassphrase);
    } catch (e,s) {
      _log.severe('Failed to decrypt data for profile $profileId: $e', e, s);
      bool isPassphraseError = e.toString().toLowerCase().contains('bad passphrase') ||
          e.toString().toLowerCase().contains('incorrect pass') ||
          e.toString().toLowerCase().contains('decryption failed');
      throw GPGDecryptionException(
        'Could not decrypt data for profile $profileId.',
        isPassphraseError: isPassphraseError,
        cause: e,
        stackTrace: s,
      );
    }
  }
  /// Verifies if the provided passphrase is correct for the given profile's private key.
  /// 
  /// Returns `true` if the passphrase is correct, `false` otherwise.
  /// Throws an exception if the profile or key is not found.
  Future<bool> verifyPassphraseForProfile(String profileId, String passphrase) async {
    try {
      // Get the key for the profile
      final key = await getKeyForProfileById(profileId);
      if (key == null) {
        throw Exception('No GPG key found for profile $profileId');
      }

      // Try to sign a test message with the private key and passphrase
      // If the passphrase is wrong, this will throw an exception
      await signMessage(
        'passphrase_verification_${DateTime.now().millisecondsSinceEpoch}',
        profileId,
        key.privateKey,
        passphrase,
      );
      
      // If we get here, the passphrase is correct
      return true;
    } catch (e, s) {
      _log.severe('Unexpected error during passphrase verification for profile $profileId: $e', e, s);

      // If there's an error (like wrong passphrase), return false
      return false;
    }
  }

  Future<String> _signMessageInternal(String message, String privateKey, String passphrase) async {
    try {
      return await _pgpProvider.sign(message, privateKey, passphrase);
    } catch (e, s) {
      _log.severe('Failed to sign message internally: $e', e, s);
      throw GPGSigningException('Could not sign message.', cause: e, stackTrace: s);
    }
  }

  // Sign and Verify
  Future<String> signMessage(String message, String profileId, String privateKey, String passphrase) async {
    final key = await getKeyForProfileById(profileId);
    if (key == null) {
      throw Exception('No GPG key found for profile $profileId to sign message.');
    }
    return _signMessageInternal(message, key.privateKey, passphrase);
  }


  Future<bool> verifySignature(String message, String signature, String publicKey) async {
    try {
      final verified = await _pgpProvider.verify(message, signature, publicKey);
      _log.fine('Signature verification result: $verified');
      return verified;
    } catch (e, s) {
      _log.severe('Failed to verify signature: $e', e, s);
      throw GPGVerificationException('Could not verify signature.', cause: e, stackTrace: s);
    }
  }
}