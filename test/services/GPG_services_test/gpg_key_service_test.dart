import 'package:file/file.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:pass/core/utils/pgp_provider.dart';
import 'package:pass/models/gpg_key.dart';
import 'package:pass/services/GPG_services/gpg_key_service.dart';
import 'package:pass/services/GPG_services/gpg_key_service_exception.dart';

import 'gpg_key_service_test.mocks.dart';

@GenerateMocks([
  FlutterSecureStorage,
  PGPProvider,
  FileSystem,
  File,
])

void main() {
  late GPGService gpgService;
  late MockFlutterSecureStorage mockSecureStorage;
  late MockPGPProvider mockPgpProvider;
  late MockFileSystem mockFileSystem;

  const String testProfileId = 'test_profile';
  const String testPublicKey = '-----BEGIN PGP PUBLIC KEY BLOCK-----\ntest_public_key\n-----END PGP PUBLIC KEY BLOCK-----';
  const String testPrivateKey = '-----BEGIN PGP PRIVATE KEY BLOCK-----\ntest_private_key\n-----END PGP PRIVATE KEY BLOCK-----';
  const String testPassphrase = 'test_passphrase';
  const String testMessage = 'test message';
  const String testEncryptedData = 'encrypted_data';
  const String testSignature = 'test_signature';

  setUp(() {
    mockSecureStorage = MockFlutterSecureStorage();
    mockPgpProvider = MockPGPProvider();
    mockFileSystem = MockFileSystem();
    gpgService = GPGService(
      secureStorage: mockSecureStorage,
      pgpProvider: mockPgpProvider,
      fileSystem: mockFileSystem,
    );
  });

  group('Key Management', () {
    test('saveKeyForProfileById should save all key components', () async {
      // Arrange
      final gpgKey = GPGKey(
        profileId: testProfileId,
        publicKey: testPublicKey,
        privateKey: testPrivateKey,
        passphrase: testPassphrase,
      );

      when(mockSecureStorage.write(key: anyNamed('key'), value: anyNamed('value')))
          .thenAnswer((_) async {});

      // Act
      await gpgService.saveKeyForProfileById(testProfileId, gpgKey);

      // Assert
      verify(mockSecureStorage.write(key: 'gpg_${testProfileId}_public', value: testPublicKey)).called(1);
      verify(mockSecureStorage.write(key: 'gpg_${testProfileId}_private', value: testPrivateKey)).called(1);
      verify(mockSecureStorage.write(key: 'gpg_${testProfileId}_passphrase', value: testPassphrase)).called(1);
    });

    test('getKeyForProfileById should return GPGKey when all components exist', () async {
      // Arrange
      when(mockSecureStorage.read(key: 'gpg_${testProfileId}_public'))
          .thenAnswer((_) async => testPublicKey);
      when(mockSecureStorage.read(key: 'gpg_${testProfileId}_private'))
          .thenAnswer((_) async => testPrivateKey);
      when(mockSecureStorage.read(key: 'gpg_${testProfileId}_passphrase'))
          .thenAnswer((_) async => testPassphrase);

      // Act
      final result = await gpgService.getKeyForProfileById(testProfileId);

      // Assert
      expect(result, isNotNull);
      expect(result!.profileId, equals(testProfileId));
      expect(result.publicKey, equals(testPublicKey));
      expect(result.privateKey, equals(testPrivateKey));
      expect(result.passphrase, equals(testPassphrase));
    });

    test('getKeyForProfileById should return null when components missing', () async {
      // Arrange
      when(mockSecureStorage.read(key: 'gpg_${testProfileId}_public'))
          .thenAnswer((_) async => null);
      when(mockSecureStorage.read(key: 'gpg_${testProfileId}_private'))
          .thenAnswer((_) async => null);
      when(mockSecureStorage.read(key: 'gpg_${testProfileId}_passphrase'))
          .thenAnswer((_) async => null);

      // Act
      final result = await gpgService.getKeyForProfileById(testProfileId);

      // Assert
      expect(result, isNull);
    });

    test('hasKeyForProfileById should return true when key exists', () async {
      // Arrange
      when(mockSecureStorage.read(key: 'gpg_${testProfileId}_public'))
          .thenAnswer((_) async => testPublicKey);
      when(mockSecureStorage.read(key: 'gpg_${testProfileId}_private'))
          .thenAnswer((_) async => testPrivateKey);
      when(mockSecureStorage.read(key: 'gpg_${testProfileId}_passphrase'))
          .thenAnswer((_) async => testPassphrase);

      // Act
      final result = await gpgService.hasKeyForProfileById(testProfileId);

      // Assert
      expect(result, isTrue);
    });

    test('hasKeyForProfileById should return false when key does not exist', () async {
      // Arrange
      when(mockSecureStorage.read(key: anyNamed('key')))
          .thenAnswer((_) async => null);

      // Act
      final result = await gpgService.hasKeyForProfileById(testProfileId);

      // Assert
      expect(result, isFalse);
    });

    test('deleteKeyForProfileById should delete all key components', () async {
      // Arrange
      when(mockSecureStorage.delete(key: anyNamed('key')))
          .thenAnswer((_) async {});

      // Act
      await gpgService.deleteKeyForProfileById(testProfileId);

      // Assert
      verify(mockSecureStorage.delete(key: 'gpg_${testProfileId}_public')).called(1);
      verify(mockSecureStorage.delete(key: 'gpg_${testProfileId}_private')).called(1);
      verify(mockSecureStorage.delete(key: 'gpg_${testProfileId}_passphrase')).called(1);
    });
  });

  group('GPG Operations', () {
    test('encryptPassword should return encrypted data', () async {
      // Arrange
      when(mockPgpProvider.encrypt(testMessage, testPublicKey))
          .thenAnswer((_) async => testEncryptedData);

      // Act
      final result = await gpgService.encryptPassword(testMessage, testPublicKey);

      // Assert
      expect(result, equals(testEncryptedData));
      verify(mockPgpProvider.encrypt(testMessage, testPublicKey)).called(1);
    });

    test('encryptPassword should throw GPGEncryptionException on error', () async {
      // Arrange
      when(mockPgpProvider.encrypt(testMessage, testPublicKey))
          .thenThrow(Exception('Encryption failed'));

      // Act & Assert
      expect(
            () => gpgService.encryptPassword(testMessage, testPublicKey),
        throwsA(isA<GPGEncryptionException>()),
      );
    });

    test('decryptPassword should return decrypted data', () async {
      // Arrange
      when(mockPgpProvider.decrypt(testEncryptedData, testPrivateKey, testPassphrase))
          .thenAnswer((_) async => testMessage);

      // Act
      final result = await gpgService.decryptPassword(testEncryptedData, testPrivateKey, testPassphrase);

      // Assert
      expect(result, equals(testMessage));
      verify(mockPgpProvider.decrypt(testEncryptedData, testPrivateKey, testPassphrase)).called(1);
    });

    test('decryptPassword should throw GPGDecryptionException with passphrase error flag', () async {
      // Arrange
      when(mockPgpProvider.decrypt(testEncryptedData, testPrivateKey, testPassphrase))
          .thenThrow(Exception('bad passphrase'));

      // Act & Assert
      try {
        await gpgService.decryptPassword(testEncryptedData, testPrivateKey, testPassphrase);
        fail('Expected GPGDecryptionException');
      } catch (e) {
        expect(e, isA<GPGDecryptionException>());
        expect((e as GPGDecryptionException).isPassphraseError, isTrue);
      }
    });

    test('decryptPassword should throw GPGDecryptionException without passphrase error flag', () async {
      // Arrange
      when(mockPgpProvider.decrypt(testEncryptedData, testPrivateKey, testPassphrase))
          .thenThrow(Exception('other error'));

      // Act & Assert
      try {
        await gpgService.decryptPassword(testEncryptedData, testPrivateKey, testPassphrase);
        fail('Expected GPGDecryptionException');
      } catch (e) {
        expect(e, isA<GPGDecryptionException>());
        expect((e as GPGDecryptionException).isPassphraseError, isFalse);
      }
    });
  });

  group('Key Import and Generation', () {
    test('importPrivateKeyForProfile should save imported key', () async {
      // Arrange
      when(mockSecureStorage.write(key: anyNamed('key'), value: anyNamed('value')))
          .thenAnswer((_) async {});

      // Act
      await gpgService.importPrivateKeyForProfile(
        profileId: testProfileId,
        privateKeyArmored: testPrivateKey,
        passphraseForImportedKey: testPassphrase,
        publicKeyArmored: testPublicKey,
      );

      // Assert
      verify(mockSecureStorage.write(key: 'gpg_${testProfileId}_public', value: testPublicKey)).called(1);
      verify(mockSecureStorage.write(key: 'gpg_${testProfileId}_private', value: testPrivateKey)).called(1);
      verify(mockSecureStorage.write(key: 'gpg_${testProfileId}_passphrase', value: testPassphrase)).called(1);
    });

    test('importPrivateKeyForProfile should handle missing public key', () async {
      // Arrange
      when(mockSecureStorage.write(key: anyNamed('key'), value: anyNamed('value')))
          .thenAnswer((_) async {});

      // Act
      await gpgService.importPrivateKeyForProfile(
        profileId: testProfileId,
        privateKeyArmored: testPrivateKey,
        passphraseForImportedKey: testPassphrase,
      );

      // Assert
      verify(mockSecureStorage.write(key: 'gpg_${testProfileId}_public', value: '')).called(1);
      verify(mockSecureStorage.write(key: 'gpg_${testProfileId}_private', value: testPrivateKey)).called(1);
      verify(mockSecureStorage.write(key: 'gpg_${testProfileId}_passphrase', value: testPassphrase)).called(1);
    });

    test('importPrivateKeyForProfile should throw GPGImportException on error', () async {
      // Arrange
      when(mockSecureStorage.write(key: anyNamed('key'), value: anyNamed('value')))
          .thenThrow(Exception('Storage error'));

      // Act & Assert
      expect(
            () => gpgService.importPrivateKeyForProfile(
          profileId: testProfileId,
          privateKeyArmored: testPrivateKey,
          passphraseForImportedKey: testPassphrase,
        ),
        throwsA(isA<GPGImportException>()),
      );
    });

    test('generateNewKeyForProfile should generate and save new key', () async {
      // Arrange
      final keyPair = PGPKeyPair(testPublicKey,testPrivateKey);
      when(mockPgpProvider.generate(options: anyNamed('options')))
          .thenAnswer((_) async => keyPair);
      when(mockSecureStorage.write(key: anyNamed('key'), value: anyNamed('value')))
          .thenAnswer((_) async {});

      // Act
      final result = await gpgService.generateNewKeyForProfile(
        profileId: testProfileId,
        passphrase: testPassphrase,
        userName: 'Test User',
        userEmail: 'test@example.com',
      );

      // Assert
      expect(result.profileId, equals(testProfileId));
      expect(result.publicKey, equals(testPublicKey));
      expect(result.privateKey, equals(testPrivateKey));
      expect(result.passphrase, equals(testPassphrase));

      verify(mockPgpProvider.generate(options: anyNamed('options'))).called(1);
    });

    test('generateNewKeyForProfile should use default values for name and email', () async {
      // Arrange
      final keyPair = PGPKeyPair(testPublicKey,testPrivateKey);
      when(mockPgpProvider.generate(options: anyNamed('options')))
          .thenAnswer((_) async => keyPair);
      when(mockSecureStorage.write(key: anyNamed('key'), value: anyNamed('value')))
          .thenAnswer((_) async {});

      // Act
      await gpgService.generateNewKeyForProfile(
        profileId: testProfileId,
        passphrase: testPassphrase,
        userName: null,
        userEmail: null,
      );

      // Assert
      verify(mockPgpProvider.generate(options: anyNamed('options'))).called(1);
    });

    test('generateNewKeyForProfile should throw GPGImportException on error', () async {
      // Arrange
      when(mockPgpProvider.generate(options: anyNamed('options')))
          .thenThrow(Exception('Generation failed'));

      // Act & Assert
      expect(
            () => gpgService.generateNewKeyForProfile(
          profileId: testProfileId,
          passphrase: testPassphrase,
          userName: 'Test User',
          userEmail: 'test@example.com',
        ),
        throwsA(isA<GPGImportException>()),
      );
    });
  });

  group('File Operations', () {
    const String inputPath = '/input/file.txt';
    const String outputPath = '/output/file.txt.gpg';
    const String fileContent = 'file content';

    test('encryptFile should encrypt file content successfully', () async {
      // Arrange
      final inputFile = MockFile();
      final outputFile = MockFile();

      when(mockFileSystem.file(inputPath)).thenReturn(inputFile);
      when(mockFileSystem.file(outputPath)).thenReturn(outputFile);
      when(inputFile.exists()).thenAnswer((_) async => true);
      when(inputFile.readAsString()).thenAnswer((_) async => fileContent);
      when(mockPgpProvider.encrypt(fileContent, testPublicKey))
          .thenAnswer((_) async => testEncryptedData);
      when(outputFile.create(recursive: true)).thenAnswer((_) async => outputFile);
      when(outputFile.writeAsString(testEncryptedData)).thenAnswer((_) async => outputFile);

      // Act
      await gpgService.encryptFile(inputPath, outputPath, testPublicKey);

      // Assert
      verify(inputFile.readAsString()).called(1);
      verify(mockPgpProvider.encrypt(fileContent, testPublicKey)).called(1);
      verify(outputFile.writeAsString(testEncryptedData)).called(1);
    });

    test('encryptFile should throw exception when input file does not exist', () async {
      // Arrange
      final inputFile = MockFile();
      when(mockFileSystem.file(inputPath)).thenReturn(inputFile);
      when(inputFile.exists()).thenAnswer((_) async => false);

      // Act & Assert
      expect(
            () => gpgService.encryptFile(inputPath, outputPath, testPublicKey),
        throwsException,
      );
    });

    test('encryptFile should throw GPGFileOperationException on FileSystemException', () async {
      // Arrange
      final inputFile = MockFile();
      when(mockFileSystem.file(inputPath)).thenReturn(inputFile);
      when(inputFile.exists()).thenAnswer((_) async => true);
      when(inputFile.readAsString()).thenThrow(FileSystemException('Read error', inputPath));

      // Act & Assert
      expect(
            () => gpgService.encryptFile(inputPath, outputPath, testPublicKey),
        throwsA(isA<GPGFileOperationException>()),
      );
    });

    test('encryptFile should throw GPGEncryptionException on encryption error', () async {
      // Arrange
      final inputFile = MockFile();
      when(mockFileSystem.file(inputPath)).thenReturn(inputFile);
      when(inputFile.exists()).thenAnswer((_) async => true);
      when(inputFile.readAsString()).thenAnswer((_) async => fileContent);
      when(mockPgpProvider.encrypt(fileContent, testPublicKey))
          .thenThrow(Exception('Encryption failed'));

      // Act & Assert
      expect(
            () => gpgService.encryptFile(inputPath, outputPath, testPublicKey),
        throwsA(isA<GPGEncryptionException>()),
      );
    });

    test('decryptFile should decrypt file content successfully', () async {
      // Arrange
      final inputFile = MockFile();
      final outputFile = MockFile();

      when(mockFileSystem.file(inputPath)).thenReturn(inputFile);
      when(mockFileSystem.file(outputPath)).thenReturn(outputFile);
      when(inputFile.exists()).thenAnswer((_) async => true);
      when(inputFile.readAsString()).thenAnswer((_) async => testEncryptedData);
      when(mockPgpProvider.decrypt(testEncryptedData, testPrivateKey, testPassphrase))
          .thenAnswer((_) async => fileContent);
      when(outputFile.create(recursive: true)).thenAnswer((_) async => outputFile);
      when(outputFile.writeAsString(fileContent)).thenAnswer((_) async => outputFile);

      // Act
      await gpgService.decryptFile(inputPath, outputPath, testPrivateKey, testPassphrase);

      // Assert
      verify(inputFile.readAsString()).called(1);
      verify(mockPgpProvider.decrypt(testEncryptedData, testPrivateKey, testPassphrase)).called(1);
      verify(outputFile.writeAsString(fileContent)).called(1);
    });


    test('decryptFile should throw GPGDecryptionException with passphrase error', () async {
      // Arrange
      final inputFile = MockFile();
      when(mockFileSystem.file(inputPath)).thenReturn(inputFile);
      when(inputFile.exists()).thenAnswer((_) async => true);
      when(inputFile.readAsString()).thenAnswer((_) async => testEncryptedData);
      when(mockPgpProvider.decrypt(testEncryptedData, testPrivateKey, testPassphrase))
          .thenThrow(Exception('bad passphrase'));

      // Act & Assert
      try {
        await gpgService.decryptFile(inputPath, outputPath, testPrivateKey, testPassphrase);
        fail('Expected GPGDecryptionException');
      } catch (e) {
        expect(e, isA<GPGDecryptionException>());
        expect((e as GPGDecryptionException).isPassphraseError, isTrue);
      }
    });
  });

  group('Profile Data Operations', () {
    test('encryptDataForProfile should encrypt data with profile public key', () async {
      // Arrange
      when(mockSecureStorage.read(key: 'gpg_${testProfileId}_public'))
          .thenAnswer((_) async => testPublicKey);
      when(mockSecureStorage.read(key: 'gpg_${testProfileId}_private'))
          .thenAnswer((_) async => testPrivateKey);
      when(mockSecureStorage.read(key: 'gpg_${testProfileId}_passphrase'))
          .thenAnswer((_) async => testPassphrase);
      when(mockPgpProvider.encrypt(testMessage, testPublicKey))
          .thenAnswer((_) async => testEncryptedData);

      // Act
      final result = await gpgService.encryptDataForProfile(testMessage, testProfileId);

      // Assert
      expect(result, equals(testEncryptedData));
      verify(mockPgpProvider.encrypt(testMessage, testPublicKey)).called(1);
    });

    test('encryptDataForProfile should throw exception when key not found', () async {
      // Arrange
      when(mockSecureStorage.read(key: anyNamed('key')))
          .thenAnswer((_) async => null);

      // Act & Assert
      expect(
            () => gpgService.encryptDataForProfile(testMessage, testProfileId),
        throwsException,
      );
    });

    test('encryptDataForProfile should throw exception when public key is empty', () async {
      // Arrange
      when(mockSecureStorage.read(key: 'gpg_${testProfileId}_public'))
          .thenAnswer((_) async => '');
      when(mockSecureStorage.read(key: 'gpg_${testProfileId}_private'))
          .thenAnswer((_) async => testPrivateKey);
      when(mockSecureStorage.read(key: 'gpg_${testProfileId}_passphrase'))
          .thenAnswer((_) async => testPassphrase);

      // Act & Assert
      expect(
            () => gpgService.encryptDataForProfile(testMessage, testProfileId),
        throwsException,
      );
    });

    test('decryptDataForProfile should decrypt data with profile private key', () async {
      // Arrange
      when(mockSecureStorage.read(key: 'gpg_${testProfileId}_public'))
          .thenAnswer((_) async => testPublicKey);
      when(mockSecureStorage.read(key: 'gpg_${testProfileId}_private'))
          .thenAnswer((_) async => testPrivateKey);
      when(mockSecureStorage.read(key: 'gpg_${testProfileId}_passphrase'))
          .thenAnswer((_) async => testPassphrase);
      when(mockPgpProvider.decrypt(testEncryptedData, testPrivateKey, testPassphrase))
          .thenAnswer((_) async => testMessage);

      // Act
      final result = await gpgService.decryptDataForProfile(
        testEncryptedData,
        testProfileId,
        testPassphrase,
      );

      // Assert
      expect(result, equals(testMessage));
      verify(mockPgpProvider.decrypt(testEncryptedData, testPrivateKey, testPassphrase)).called(1);
    });

    test('decryptDataForProfile should throw exception when key not found', () async {
      // Arrange
      when(mockSecureStorage.read(key: anyNamed('key')))
          .thenAnswer((_) async => null);

      // Act & Assert
      expect(
            () => gpgService.decryptDataForProfile(testEncryptedData, testProfileId, testPassphrase),
        throwsException,
      );
    });
  });

  group('Passphrase Verification', () {
    test('verifyPassphraseForProfile should return true for correct passphrase', () async {
      // Arrange
      when(mockSecureStorage.read(key: 'gpg_${testProfileId}_public'))
          .thenAnswer((_) async => testPublicKey);
      when(mockSecureStorage.read(key: 'gpg_${testProfileId}_private'))
          .thenAnswer((_) async => testPrivateKey);
      when(mockSecureStorage.read(key: 'gpg_${testProfileId}_passphrase'))
          .thenAnswer((_) async => testPassphrase);
      when(mockPgpProvider.sign(any, testPrivateKey, testPassphrase))
          .thenAnswer((_) async => testSignature);

      // Act
      final result = await gpgService.verifyPassphraseForProfile(testProfileId, testPassphrase);

      // Assert
      expect(result, isTrue);
    });

    test('verifyPassphraseForProfile should return false for incorrect passphrase', () async {
      // Arrange
      when(mockSecureStorage.read(key: 'gpg_${testProfileId}_public'))
          .thenAnswer((_) async => testPublicKey);
      when(mockSecureStorage.read(key: 'gpg_${testProfileId}_private'))
          .thenAnswer((_) async => testPrivateKey);
      when(mockSecureStorage.read(key: 'gpg_${testProfileId}_passphrase'))
          .thenAnswer((_) async => testPassphrase);
      when(mockPgpProvider.sign(any, testPrivateKey, 'wrong_passphrase'))
          .thenThrow(Exception('Bad passphrase'));

      // Act
      final result = await gpgService.verifyPassphraseForProfile(testProfileId, 'wrong_passphrase');

      // Assert
      expect(result, isFalse);
    });

    test('verifyPassphraseForProfile should throw exception when key not found', () async {
      // Arrange
      when(mockSecureStorage.read(key: anyNamed('key')))
          .thenAnswer((_) async => null);

      // Act & Assert
      final result = await gpgService.verifyPassphraseForProfile(testProfileId, testPassphrase);

      expect(result, isFalse);
    });
  });

  group('Sign and Verify', () {
    test('signMessage should sign message with profile key', () async {
      // Arrange
      when(mockSecureStorage.read(key: 'gpg_${testProfileId}_public'))
          .thenAnswer((_) async => testPublicKey);
      when(mockSecureStorage.read(key: 'gpg_${testProfileId}_private'))
          .thenAnswer((_) async => testPrivateKey);
      when(mockSecureStorage.read(key: 'gpg_${testProfileId}_passphrase'))
          .thenAnswer((_) async => testPassphrase);
      when(mockPgpProvider.sign(testMessage, testPrivateKey, testPassphrase))
          .thenAnswer((_) async => testSignature);

      // Act
      final result = await gpgService.signMessage(
        testMessage,
        testProfileId,
        testPrivateKey,
        testPassphrase,
      );

      // Assert
      expect(result, equals(testSignature));
      verify(mockPgpProvider.sign(testMessage, testPrivateKey, testPassphrase)).called(1);
    });

    test('signMessage should throw exception when key not found', () async {
      // Arrange
      when(mockSecureStorage.read(key: anyNamed('key')))
          .thenAnswer((_) async => null);

      // Act & Assert
      expect(
            () => gpgService.signMessage(testMessage, testProfileId, testPrivateKey, testPassphrase),
        throwsException,
      );
    });

    test('signMessage should throw GPGSigningException on signing error', () async {
      // Arrange
      when(mockSecureStorage.read(key: 'gpg_${testProfileId}_public'))
          .thenAnswer((_) async => testPublicKey);
      when(mockSecureStorage.read(key: 'gpg_${testProfileId}_private'))
          .thenAnswer((_) async => testPrivateKey);
      when(mockSecureStorage.read(key: 'gpg_${testProfileId}_passphrase'))
          .thenAnswer((_) async => testPassphrase);
      when(mockPgpProvider.sign(testMessage, testPrivateKey, testPassphrase))
          .thenThrow(Exception('Signing failed'));

      // Act & Assert
      expect(
            () => gpgService.signMessage(testMessage, testProfileId, testPrivateKey, testPassphrase),
        throwsA(isA<GPGSigningException>()),
      );
    });

    test('verifySignature should return true for valid signature', () async {
      // Arrange
      when(mockPgpProvider.verify(testMessage, testSignature, testPublicKey))
          .thenAnswer((_) async => true);

      // Act
      final result = await gpgService.verifySignature(testMessage, testSignature, testPublicKey);

      // Assert
      expect(result, isTrue);
      verify(mockPgpProvider.verify(testMessage, testSignature, testPublicKey)).called(1);
    });

    test('verifySignature should return false for invalid signature', () async {
      // Arrange
      when(mockPgpProvider.verify(testMessage, testSignature, testPublicKey))
          .thenAnswer((_) async => false);

      // Act
      final result = await gpgService.verifySignature(testMessage, testSignature, testPublicKey);

      // Assert
      expect(result, isFalse);
    });

    test('verifySignature should throw GPGVerificationException on error', () async {
      // Arrange
      when(mockPgpProvider.verify(testMessage, testSignature, testPublicKey))
          .thenThrow(Exception('Verification failed'));

      // Act & Assert
      expect(
            () => gpgService.verifySignature(testMessage, testSignature, testPublicKey),
        throwsA(isA<GPGVerificationException>()),
      );
    });
  });
}