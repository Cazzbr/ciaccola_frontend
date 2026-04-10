import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:ciaccola_frontend/models/chat_message.dart';
import 'package:ciaccola_frontend/models/contact.dart';
import 'package:ciaccola_frontend/screens/chat_screen.dart';
import 'package:ciaccola_frontend/services/auth_service.dart';
import 'package:ciaccola_frontend/services/connection_manager.dart';
import 'package:ciaccola_frontend/services/contact_service.dart';
import 'package:ciaccola_frontend/services/database_service.dart';

class ChatsScreen extends StatefulWidget {
  final String token;
  const ChatsScreen({super.key, required this.token});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  final _authService = AuthService();
  final _contactService = ContactService();
  final _db = DatabaseService();
  final _manager = ConnectionManager();

  final _searchController = TextEditingController();

  bool _loading = true;
  String? _error;

  List<Contact> _allContacts = [];
  List<Contact> _chats = [];
  List<Contact> _filteredChats = [];
  List<Contact> _invites = [];
  final Map<String, ChatMessage> _lastMessages = {};

  String _currentUserId = 'me';
  StreamSubscription? _eventSub;
  Timer? _heartbeat;

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(_filter);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _eventSub?.cancel();
    _heartbeat?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      _currentUserId = _extractUserId(widget.token) ?? 'me';
      _allContacts = await _contactService.fetchContacts(widget.token);
      try {
        final profile = await _authService.getProfile(widget.token);
        _manager.isPremium = profile.role == 'premium';
      } catch (_) {}
      final accepted = _allContacts.where((c) => c.status == 'accepted').toList();
      await _manager.start(
        currentUserId: _currentUserId,
        token: widget.token,
        contacts: accepted,
      );

      await _refreshChats();
      _updateInvites();

      _eventSub = _manager.events.listen((event) {
        if (event is IncomingMessageEvent || event is MessagesDeliveredEvent) {
          _refreshChats();
        } else if (event is MessageDeletedEvent) {
          _refreshChats();
        } else if (event is ChannelStateChangedEvent ||
            event is PeerStateChangedEvent ||
            event is ContactOfflineEvent) {
          if (mounted) setState(() {});
        } else if (event is ContactInviteReceivedEvent) {
          _reloadContacts();
        } else if (event is ContactAcceptedEvent) {
          _reloadContacts();
        }
      });

      _heartbeat = Timer.periodic(const Duration(seconds: 8), (_) {
        if (mounted) setState(() {});
      });

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _reloadContacts() async {
    _allContacts = await _contactService.fetchContacts(widget.token);
    final accepted = _allContacts.where((c) => c.status == 'accepted').toList();
    for (final c in accepted) {
      _manager.addContact(c);
    }
    _updateInvites();
    await _refreshChats();
  }

  Future<void> _refreshChats() async {
    final chatContactIds = await _db.getChatContactIds();
    final chats = _allContacts
        .where((c) => c.status == 'accepted' && chatContactIds.contains(c.id))
        .toList();

    final resolved = <String, ChatMessage>{};
    for (final c in chats) {
      final msg = await _db.getLastMessage(c.id);
      if (msg != null) resolved[c.id] = msg;
    }

    chats.sort((a, b) {
      final ta = resolved[a.id]?.timestamp ?? 0;
      final tb = resolved[b.id]?.timestamp ?? 0;
      return tb.compareTo(ta);
    });

    if (!mounted) return;
    final q = _searchController.text.toLowerCase();
    setState(() {
      _chats = chats;
      _filteredChats = q.isEmpty ? chats : chats.where((c) => c.name.toLowerCase().contains(q)).toList();
      _lastMessages..clear()..addAll(resolved);
    });
  }

  void _filter() {
    final q = _searchController.text.toLowerCase();
    setState(() {
      _filteredChats = _chats
          .where((c) => c.name.toLowerCase().contains(q))
          .toList();
    });
  }

  void _updateInvites() {
    final invites = _allContacts.where((c) => c.status == 'invited').toList();
    if (mounted) setState(() => _invites = invites);
  }

  Future<void> _acceptInvite(Contact contact) async {
    try {
      await _contactService.acceptInvite(widget.token, contact.username);
      _manager.addContact(contact);
      await _reloadContacts();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to accept invite: $e')),
        );
      }
    }
  }

  void _dismissInvite(Contact contact) {
    if (mounted) setState(() => _invites.removeWhere((c) => c.id == contact.id));
  }
  String? _extractUserId(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (payload is Map<String, dynamic>) {
        return payload['userId']?.toString() ?? payload['sub']?.toString();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static const _avatarPalette = [
    Color(0xFF1E40AF), Color(0xFF065F46), Color(0xFF7C3AED),
    Color(0xFFB45309), Color(0xFF9D174D), Color(0xFF0E7490),
    Color(0xFF374151), Color(0xFF991B1B),
  ];

  Color _avatarColor(String id) =>
      _avatarPalette[id.hashCode.abs() % _avatarPalette.length];

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  Color _statusDotColor(Contact contact) {
    return _manager.isChannelReady(contact.id)
        ? const Color(0xFF22C55E)
        : const Color(0xFF6B7280);
  }

  DateTime? _parseLastSeen(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final dt = DateTime.tryParse(raw);
    if (dt != null) return dt.toLocal();
    final n = int.tryParse(raw);
    if (n != null) return DateTime.fromMillisecondsSinceEpoch(n > 1e12 ? n : n * 1000);
    return null;
  }

  String _formatLastSeen(String? raw) {
    final dt = _parseLastSeen(raw);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24)   return '${diff.inHours}h ago';
    if (diff.inDays < 7)     return '${diff.inDays}d ago';
    if (diff.inDays < 30)    return '${(diff.inDays / 7).floor()}w ago';
    if (diff.inDays < 365)   return '${(diff.inDays / 30).floor()}mo ago';
    return '${(diff.inDays / 365).floor()}y ago';
  }

  String _formatMessageTime(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(dt.year, dt.month, dt.day);
    if (msgDay == today) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    if (today.difference(msgDay).inDays < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[dt.weekday - 1];
    }
    return '${dt.day}/${dt.month}';
  }

  String _presenceLine(Contact contact) {
    if (_manager.isChannelReady(contact.id)) return 'Online';
    final seen = _formatLastSeen(contact.lastSeen);
    return seen.isNotEmpty ? 'Last seen $seen' : 'Offline';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search chats...',
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: const Color(0xFF1C2447),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(vertical: 0),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _invites.isEmpty && _chats.isEmpty
                          ? const Center(
                              child: Text(
                                'No chats yet.\nStart a conversation from Contacts.',
                                textAlign: TextAlign.center,
                              ),
                            )
                          : _filteredChats.isEmpty && _invites.isEmpty
                              ? const Center(child: Text('No chats found.'))
                              : ListView(
                                  children: [
                                    // Pinned invite cards
                                    ..._invites.map((contact) => _InviteCard(
                                          contact: contact,
                                          onAccept: () => _acceptInvite(contact),
                                          onIgnore: () => _dismissInvite(contact),
                                        )),
                                    ..._filteredChats.map((contact) => _ChatTile(
                                          contact: contact,
                                          lastMessage: _lastMessages[contact.id],
                                          avatarColor: _avatarColor(contact.id),
                                          initials: _initials(contact.name),
                                          statusDotColor: _statusDotColor(contact),
                                          presenceLine: _presenceLine(contact),
                                          formatTime: _formatMessageTime,
                                          onTap: () async {
                                            await Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) => ChatScreen(
                                                  token: widget.token,
                                                  currentUserId: _currentUserId,
                                                  contact: contact,
                                                ),
                                              ),
                                            );
                                            _refreshChats();
                                          },
                                        )),
                                  ],
                                ),
                    ),
                  ],
                ),
    );
  }
}

class _InviteCard extends StatelessWidget {
  final Contact contact;
  final VoidCallback onAccept;
  final VoidCallback onIgnore;

  const _InviteCard({
    required this.contact,
    required this.onAccept,
    required this.onIgnore,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.secondary.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.person_add, color: theme.colorScheme.secondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contact.username,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'wants to connect with you',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade400),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: onIgnore,
              style: TextButton.styleFrom(foregroundColor: Colors.grey),
              child: const Text('Ignore'),
            ),
            FilledButton(
              onPressed: onAccept,
              child: const Text('Accept'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  final Contact contact;
  final ChatMessage? lastMessage;
  final Color avatarColor;
  final String initials;
  final Color statusDotColor;
  final String presenceLine;
  final String Function(int) formatTime;
  final VoidCallback onTap;

  const _ChatTile({
    required this.contact,
    required this.lastMessage,
    required this.avatarColor,
    required this.initials,
    required this.statusDotColor,
    required this.presenceLine,
    required this.formatTime,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final last = lastMessage;
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: avatarColor,
                  child: Text(
                    initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      color: statusDotColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: theme.scaffoldBackgroundColor,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          contact.name,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (last != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          formatTime(last.timestamp),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  if (last != null)
                    Row(
                      children: [
                        if (last.isSentByMe)
                          Text(
                            'You: ',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade500,
                            ),
                          ),
                        if (last.isQueued)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(Icons.access_time, size: 13, color: Colors.grey.shade500),
                          ),
                        Expanded(
                          child: Text(
                            last.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade400,
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      presenceLine,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: presenceLine == 'Online'
                            ? const Color(0xFF22C55E)
                            : Colors.grey.shade500,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
