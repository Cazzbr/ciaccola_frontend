import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:ciaccola_frontend/models/contact.dart';
import 'package:ciaccola_frontend/configs/api_config.dart';

class ContactService {
  Future<List<Contact>> fetchContacts(String token) async {
    final response = await http.get(
      Uri.parse('${ApiConfig.baseHttpUrl}${ApiConfig.profilePath}'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load contacts: ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic>) {
      throw Exception('Unexpected response format');
    }
    
    final contactsList = List<dynamic>.from(data['contacts'] ?? []);
    return contactsList
        .map((item) => Contact.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<Contact>> searchUsers(String token, String term, {int limit = 10}) async {
    final uri = Uri.parse(
      '${ApiConfig.baseHttpUrl}/api/users/search/${Uri.encodeComponent(term)}',
    ).replace(queryParameters: {'limit': limit.toString()});

    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to search users: ${response.statusCode} - ${response.body}');
    }

    final data = jsonDecode(response.body);
    if (data is Map<String, dynamic>) {
      final users = data['users'] ?? data['results'] ?? data['contacts'] ?? [];
      final userList = List<dynamic>.from(users);
      return userList.map((item) => Contact.fromJson(item as Map<String, dynamic>)).toList();
    }

    if (data is List) {
      return data.map((item) => Contact.fromJson(item as Map<String, dynamic>)).toList();
    }

    throw Exception('Unexpected response format');
  }

  Future<Contact> addContact(String token, String contactUsername) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseHttpUrl}/api/users/contacts'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'contact_username': contactUsername}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to add contact: ${response.statusCode} - ${response.body}');
    }

    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic>) {
      throw Exception('Unexpected response format');
    }

    return Contact.fromJson(data);
  }
}
