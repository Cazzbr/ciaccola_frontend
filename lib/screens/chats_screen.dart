import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:ciaccola_frontend/models/contact.dart';
import 'package:ciaccola_frontend/screens/chat_screen.dart';
import 'package:ciaccola_frontend/services/contact_service.dart';
import 'package:ciaccola_frontend/services/database_service.dart';
import 'package:ciaccola_frontend/services/socket_signaling_service.dart';

class ChatsScreen extends StatefulWidget {
  final String token;
  const ChatsScreen({super.key, required this.token});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  final _contactService = ContactService();
  final _db = DatabaseService();
  bool _loading = true;
  String? _error;
  List<Contact> _chats = [];
  String _currentUserId = 'me';

  @override
  void initState() {
    super.initState();
    SocketSignalingService().connect(token: widget.token);
    _load();
  }

  Future<void> _load() async {
    try {
      _currentUserId = _extractUserId(widget.token) ?? 'me';
      final allContacts = await _contactService.fetchContacts(widget.token);
      final chatContactIds = await _db.getChatContactIds();
      final chats = allContacts.where((contact) => chatContactIds.contains(contact.id)).toList();

      setState(() {
        _chats = chats;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _chats.isEmpty
                  ? const Center(
                      child: Text(
                        'No chats yet. Start a conversation from Contacts.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.separated(
                      itemCount: _chats.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final contact = _chats[index];
                        return ListTile(
                          title: Text(contact.name),
                          subtitle: Text("Status: ${contact.status}${contact.lastSeen != null ? ' • Last seen: ${contact.lastSeen}' : ''}"),
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