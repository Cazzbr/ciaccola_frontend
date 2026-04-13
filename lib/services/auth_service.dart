import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:ciaccola_frontend/configs/api_config.dart';
import 'package:ciaccola_frontend/services/secure_storage_service.dart';
import 'package:ciaccola_frontend/models/user.dart';
import 'package:ciaccola_frontend/utils/jwt_utils.dart';

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

  Future<String> register({required String username, required String password, String? email}) async {
    final body = {
      'username': username,
      'password': password,
      if (email != null && email.isNotEmpty) 'email': email,
    };

    final response = await http.post(
      Uri.parse('${ApiConfig.baseHttpUrl}${ApiConfig.registerPath}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Registration failed: ${response.statusCode} - ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final token = data['token']?.toString();
    if (token == null || token.isEmpty) {
      throw Exception('Token missing in registration response');
    }

    await SecureStorageService.saveToken(token);
    return token;
  }

  Future<bool> isStoredTokenValid() async {
    final token = await SecureStorageService.getToken();
    if (token == null || token.isEmpty) return false;

    final exp = JwtUtils.extractExpiration(token);
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

  Future<void> logout() async {
    await SecureStorageService.deleteToken();
  }

  Future<User> getProfile(String token) async {
    final response = await http.get(
      Uri.parse('${ApiConfig.baseHttpUrl}${ApiConfig.profilePath}'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to get profile: ${response.statusCode} - ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return User.fromJson(data);
  }

  Future<User> updateProfile(String token, {
    String? username,
    String? email,
    String? password,
    String? role,
  }) async {
    final body = <String, dynamic>{};
    if (username != null) body['username'] = username;
    if (email != null) body['email'] = email;
    if (password != null) body['password'] = password;
    if (role != null) body['role'] = role;

    final response = await http.put(
      Uri.parse('${ApiConfig.baseHttpUrl}${ApiConfig.profilePath}'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to update profile: ${response.statusCode} - ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return User.fromJson(data);
  }

  Future<String> uploadPhoto(String token, Uint8List bytes, String filename) async {
    final lower = filename.toLowerCase();
    final subtype = lower.endsWith('.png')
        ? 'png'
        : lower.endsWith('.webp')
            ? 'webp'
            : 'jpeg';

    final request = http.MultipartRequest(
      'PUT',
      Uri.parse('${ApiConfig.baseHttpUrl}${ApiConfig.uploadPhotoPath}'),
    );
    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(
      http.MultipartFile.fromBytes(
        'photo',
        bytes,
        filename: filename,
        contentType: MediaType('image', subtype),
      ),
    );

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to upload photo: ${response.statusCode} - ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final photo = data['photo']?.toString();
    if (photo == null || photo.isEmpty) {
      throw Exception('No photo in upload response');
    }
    return photo;
  }

  Future<void> deleteProfile(String token) async {
    final response = await http.delete(
      Uri.parse('${ApiConfig.baseHttpUrl}${ApiConfig.profilePath}'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to delete profile: ${response.statusCode} - ${response.body}');
    }
  }
}
