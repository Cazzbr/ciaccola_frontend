import 'dart:convert';

class JwtUtils {
  static Map<String, dynamic>? _decodePayload(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final normalized = base64Url.normalize(parts[1]);
      final decoded = jsonDecode(utf8.decode(base64Url.decode(normalized)));
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }

  static String? extractUserId(String token) {
    final payload = _decodePayload(token);
    return payload?['userId']?.toString() ?? payload?['sub']?.toString();
  }

  static DateTime? extractExpiration(String token) {
    final payload = _decodePayload(token);
    if (payload == null) return null;
    final exp = payload['exp'];
    if (exp is int) return DateTime.fromMillisecondsSinceEpoch(exp * 1000);
    if (exp is String) {
      return DateTime.fromMillisecondsSinceEpoch(int.parse(exp) * 1000);
    }
    return null;
  }
}
