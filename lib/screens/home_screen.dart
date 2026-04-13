import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ciaccola_frontend/models/contact.dart';
import 'package:ciaccola_frontend/screens/chat_screen.dart';
import 'package:ciaccola_frontend/screens/chats_screen.dart';
import 'package:ciaccola_frontend/screens/contacts_screen.dart';
import 'package:ciaccola_frontend/screens/profile_screen.dart';
import 'package:ciaccola_frontend/services/connection_manager.dart';
import 'package:ciaccola_frontend/widgets/notification_banner.dart';

class HomeScreen extends StatefulWidget {
  final String token;
  const HomeScreen({super.key, required this.token});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  late final List<Widget> _screens;

  final _manager = ConnectionManager();
  StreamSubscription? _eventSub;
  final Map<String, String> _contactNames = {};

  @override
  void initState() {
    super.initState();
    _screens = [
      ChatsScreen(
        token: widget.token,
        onContactsLoaded: (names) {
          if (mounted) setState(() => _contactNames.addAll(names));
        },
      ),
      ContactsScreen(token: widget.token),
      ProfileScreen(token: widget.token),
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) => _startListening());
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }

  void _startListening() {
    _eventSub = _manager.events.listen(_handleEvent);
  }

  void _handleEvent(ConnectionEvent event) {
    if (!mounted) return;

    if (event is IncomingMessageEvent) {
      final contactId = event.message.contactId;
      if (_manager.activeChatContactId == contactId) return;
      final name = _resolveContactName(contactId);
      if (!mounted) return;
      NotificationBanner.show(
        context,
        icon: Icons.message,
        iconColor: const Color(0xFF3B82F6),
        title: name,
        body: event.message.text,
        onTap: () => _openChat(contactId, name),
      );
    } else if (event is ContactInviteReceivedEvent) {
      if (!mounted) return;
      NotificationBanner.show(
        context,
        icon: Icons.person_add,
        iconColor: const Color(0xFF22C55E),
        title: 'New contact request',
        body: '${event.fromUsername} wants to connect with you.',
        onTap: () => _goToChats(),
      );
    }
  }

  String _resolveContactName(String contactId) {
    return _contactNames[contactId] ?? contactId;
  }

  void _openChat(String contactId, String name) {
    final contact = Contact(
      id: contactId,
      username: name,
      name: name,
      status: 'accepted',
    );
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatScreen(
        token: widget.token,
        currentUserId: _manager.currentUserId ?? '',
        contact: contact,
      ),
    ));
  }

  void _goToChats() {
    if (mounted) setState(() => _selectedIndex = 0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'Chats'),
          BottomNavigationBarItem(icon: Icon(Icons.contacts), label: 'Contacts'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
        currentIndex: _selectedIndex,
        onTap: (i) => setState(() => _selectedIndex = i),
      ),
    );
  }
}
