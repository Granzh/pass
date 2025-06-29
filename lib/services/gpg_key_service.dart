import 'dart:async';
import 'dart:io';
import 'package:openpgp/openpgp.dart';

import '../core/utils/secure_storage.dart';
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

  Future<void> importPrivateKeyForProfile({
    required String profileId,
    required String privateKeyArmored,
    required String passphraseForImportedKey, // Парольная фраза ИМПОРТИРУЕМОГО ключа
    String? publicKeyArmored,
  }) async {
    try {
      // Пытаемся проверить ключ и парольную фразу, например, дешифровав что-то
      // или если библиотека позволяет получить публичный ключ из приватного с парольной фразой.
      // OpenPGP.dart не имеет прямого метода для извлечения public key из private c passphrase,
      // но при дешифровке он использует passphrase для доступа к private key.

      String finalPublicKey = publicKeyArmored ?? '';
      if (finalPublicKey.isEmpty) {
        // Попытка извлечь публичный ключ (может быть сложно или невозможно без доп. инструментов/логики)
        // В OpenPGP.dart нет простого `OpenPGP.getPublicKeyFromPrivateKey(privateKeyArmored, passphraseForImportedKey)`
        // Поэтому, если публичный ключ не предоставлен, шифрование для этого профиля может быть невозможно.
        // Можно попробовать "разблокировать" приватный ключ с помощью фразы, чтобы убедиться, что она верна.
        // Например, попытаться подписать тестовые данные.
        print("Warning: Importing private key for profile $profileId without a public key. Encryption may rely on the private key itself or fail.");
      }

      GPGKey key = GPGKey(profileId: profileId, publicKey: publicKeyArmored ?? '', privateKey: privateKeyArmored, passphrase: passphraseForImportedKey);
      // Сохраняем компоненты. Парольная фраза здесь - это та, что нужна для использования импортированного приватного ключа.
      await saveKeyForProfileById(
        profileId,
        key
      );
    } catch (e) {
      throw Exception('Failed to import GPG private key: $e');
    }
  }

  // Key Generation and Management
  Future<GPGKey> generateNewKeyForProfile({required String profileId, required String passphrase,required String? userName,required String? userEmail}) async {
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
          ..name = userName ?? profileId
          ..email = userEmail ?? '$profileId@pass.app'
          ..passphrase = passphrase
          ..keyOptions = keyOptions,
      );

      GPGKey gpgKey = GPGKey(
        profileId: profileId,
        publicKey: keyPair.publicKey,
        privateKey: keyPair.privateKey,
        passphrase: passphrase,
      );

      saveKeyForProfileById(profileId, gpgKey);

      return gpgKey;
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

  Future<String> encryptDataForProfile(String data, String profileId) async {
    final gpgKey = await getKeyForProfileById(profileId);
    if (gpgKey == null || gpgKey.publicKey.isEmpty) {
      // Если публичного ключа нет (например, был импортирован только приватный без публичного),
      // то шифрование стандартным способом (для получателя) невозможно.
      // Некоторые GPG реализации позволяют "шифровать для себя" используя только приватный ключ,
      // но это не типичное использование для обмена данными.
      // Для `pass`, вам нужен публичный ключ получателей (обычно это ваш собственный публичный ключ).
      throw Exception('Public GPG key not found or is empty for profile $profileId. Cannot encrypt data.');
    }
    try {
      // Шифруем данные, используя публичный ключ профиля.
      return await OpenPGP.encrypt(data, gpgKey.publicKey);
    } catch (e) {
      throw Exception('Failed to encrypt data for profile $profileId: $e');
    }
  }

  Future<String> decryptDataForProfile(
      String encryptedData,
      String profileId,
      String userProvidedPassphrase, // Парольная фраза, которую пользователь вводит для доступа к профилю/дешифровки
      ) async {
    final gpgKey = await getKeyForProfileById(profileId);
    if (gpgKey == null) {
      throw Exception('GPG key not found for profile $profileId. Cannot decrypt data.');
    }

    // `userProvidedPassphrase` используется библиотекой OpenPGP для "разблокировки"
    // `gpgKey.privateKey`, если этот приватный ключ был зашифрован.
    // `gpgKey.passphrase` (сохраненная с ключом) должна совпадать с `userProvidedPassphrase`
    // для успешной операции, если приватный ключ защищен.
    // Если приватный ключ не был зашифрован парольной фразой при его создании/импорте,
    // то `userProvidedPassphrase` может быть проигнорирована библиотекой (или должна быть пустой).
    try {
      return await OpenPGP.decrypt(encryptedData, gpgKey.privateKey, userProvidedPassphrase);
    } catch (e) {
      if (e.toString().toLowerCase().contains('bad passphrase') ||
          e.toString().toLowerCase().contains('incorrect pass') ||
          e.toString().toLowerCase().contains('decryption failed')) { // OpenPGP.dart может кидать разные ошибки
        throw Exception('Failed to decrypt data: Incorrect passphrase or corrupted data.');
      }
      throw Exception('Failed to decrypt data for profile: $e');
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
        key.privateKey,
        passphrase,
      );
      
      // If we get here, the passphrase is correct
      return true;
    } catch (e) {
      // If there's an error (like wrong passphrase), return false
      return false;
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