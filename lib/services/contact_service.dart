import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:ciaccola_frontend/models/contact.dart';
import 'package:ciaccola_frontend/configs/api_config.dart';

class ContactService {
  Future<List<Contact>> fetchContacts(String token) async {
    final response = await http.get(
      Uri.parse('${ApiConfig.baseHttpUrl}${ApiConfig.contactsPath}'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load contacts: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .map((item) => Contact.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}
