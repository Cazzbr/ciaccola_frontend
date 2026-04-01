import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:ciaccola_frontend/configs/api_config.dart';
import 'package:ciaccola_frontend/services/secure_storage_service.dart';

class AuthService {
  Future<String> login({required String username, required String password}) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseHttpUrl}${ApiConfig.loginPath}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Login failed: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final token = data['token']?.toString();
    if (token == null || token.isEmpty) {
      throw Exception('Token missing in login response');
    }

    await SecureStorageService.saveToken(token);
    return token;
  }

  Future<bool> isStoredTokenValid() async {
    final token = await SecureStorageService.getToken();
    if (token == null || token.isEmpty) return false;

    final exp = _jwtExpiration(token);
    if (exp != null && DateTime.now().isAfter(exp)) {
      await logout();
      return false;
    }

    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseHttpUrl}${ApiConfig.validateTokenPath}'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return true;
      }
    } catch (_) {}

    return exp != null && DateTime.now().isBefore(exp);
  }

  DateTime? _jwtExpiration(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final normalized = base64Url.normalize(parts[1]);
      final payload = jsonDecode(utf8.decode(base64Url.decode(normalized))) as Map<String, dynamic>;
      final exp = payload['exp'];
      if (exp is int) return DateTime.fromMillisecondsSinceEpoch(exp * 1000);
      if (exp is String) return DateTime.fromMillisecondsSinceEpoch(int.parse(exp) * 1000);
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> logout() async {
    await SecureStorageService.deleteToken();
  }
}
