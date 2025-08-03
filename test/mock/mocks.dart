import 'package:file/file.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mockito/mockito.dart';
import 'package:pass/core/utils/pgp_provider.dart';

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {

}

class MockPGPProvider extends Mock implements PGPProvider {

}

class MockFileSystem extends Mock implements FileSystem {

}

class MockFile extends Mock implements File {

}