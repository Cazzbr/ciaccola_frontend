import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:ciaccola_frontend/models/contact.dart';
import 'package:ciaccola_frontend/screens/chat_screen.dart';
import 'package:ciaccola_frontend/screens/login_screen.dart';
import 'package:ciaccola_frontend/services/auth_service.dart';
import 'package:ciaccola_frontend/services/contact_service.dart';

class ContactsScreen extends StatefulWidget {
  final String token;
  const ContactsScreen({super.key, required this.token});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final _contactService = ContactService();
  final _authService = AuthService();
  bool _loading = true;
  String? _error;
  List<Contact> _contacts = [];
  String _currentUserId = 'me';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _currentUserId = _extractUserId(widget.token) ?? 'me';
      final contacts = await _contactService.fetchContacts(widget.token);
      setState(() {
        _contacts = contacts;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String? _extractUserId(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      if (payload is Map<String, dynamic>) {
        return payload['userId']?.toString() ?? payload['sub']?.toString();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _logout() async {
    await _authService.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
        actions: [
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView.separated(
                  itemCount: _contacts.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final contact = _contacts[index];
                    return ListTile(
                      title: Text(contact.name),
                      subtitle: Text(contact.id),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(
                              token: widget.token,
                              currentUserId: _currentUserId,
                              contact: contact,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }
}
