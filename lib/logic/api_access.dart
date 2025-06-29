import 'package:http/http.dart' as http;
import 'package:pass/core/utils/secure_storage.dart';


final Future<String?> token = secureStorage.read(key: 'access_token');
final Future<String?> provider = secureStorage.read(key: 'provider');

final baseUrl = 'github' == provider
? 'https://api.github.com'
    : 'https://gitlab.com/api/v4';

final response = http.get(
Uri.parse('$baseUrl/user'),
headers: {'Authorization': 'Bearer $token'},
);
