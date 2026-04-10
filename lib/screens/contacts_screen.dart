import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:ciaccola_frontend/models/contact.dart';
import 'package:ciaccola_frontend/screens/chat_screen.dart';
import 'package:ciaccola_frontend/services/contact_service.dart';

class ContactsScreen extends StatefulWidget {
  final String token;
  const ContactsScreen({super.key, required this.token});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final _contactService = ContactService();
  final _searchController = TextEditingController();
  bool _loading = true;
  String? _error;
  List<Contact> _contacts = [];
  List<Contact> _filtered = [];
  String _currentUserId = 'me';

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(_filter);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      _currentUserId = _extractUserId(widget.token) ?? 'me';
      final all = await _contactService.fetchContacts(widget.token);
      // Hide deleted contacts; show everything else (accepted, pending, blocked, invited).
      final visible = all.where((c) => c.status != 'deleted').toList();
      if (mounted) {
        setState(() {
          _contacts = visible;
          _filtered = visible;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _filter() {
    final q = _searchController.text.toLowerCase();
    setState(() {
      _filtered = _contacts.where((c) => c.name.toLowerCase().contains(q)).toList();
    });
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

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  Future<void> _acceptInvite(Contact contact) async {
    try {
      await _contactService.acceptInvite(widget.token, contact.username);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to accept invite: $e')),
        );
      }
    }
  }

  void _dismissInvite(Contact contact) {
    setState(() => _contacts.removeWhere((c) => c.id == contact.id));
    _filter();
  }

  Future<void> _toggleBlock(Contact contact) async {
    if (contact.subDocId.isEmpty) return;
    try {
      await _contactService.toggleBlock(widget.token, contact.subDocId);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  void _showAddContactDialog() {
    // Build a lookup of existing relationship statuses by contact ID.
    final existingStatus = { for (final c in _contacts) c.id: c.status };

    final contactController = TextEditingController();
    bool isSearching = false;
    bool isAdding = false;
    String? errorMessage;
    List<Contact> searchResults = [];

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, dialogSetState) {
          Future<void> performSearch() async {
            final term = contactController.text.trim();
            if (term.isEmpty) {
              if (dialogContext.mounted) dialogSetState(() => errorMessage = 'Enter a username to search');
              return;
            }
            if (dialogContext.mounted) dialogSetState(() { isSearching = true; errorMessage = null; searchResults = []; });
            try {
              final results = await _contactService.searchUsers(widget.token, term, limit: 12);
              if (!mounted || !dialogContext.mounted) return;
              // Filter out the logged-in user — they can't add themselves.
              final filtered = results.where((r) => r.id != _currentUserId).toList();
              dialogSetState(() {
                searchResults = filtered;
                if (filtered.isEmpty) errorMessage = 'No users found for "$term".';
              });
            } catch (e) {
              if (!mounted || !dialogContext.mounted) return;
              dialogSetState(() => errorMessage = e.toString());
            } finally {
              if (mounted && dialogContext.mounted) dialogSetState(() => isSearching = false);
            }
          }

          Future<void> addUser(Contact contact) async {
            if (!mounted || !dialogContext.mounted) return;
            dialogSetState(() { isAdding = true; errorMessage = null; });
            try {
              await _contactService.addContact(widget.token, contact.username);
              if (!mounted) return;
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              await _load();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Invite sent to ${contact.username}'),
                  backgroundColor: Colors.green,
                ),
              );
            } catch (e) {
              if (!mounted || !dialogContext.mounted) return;
              dialogSetState(() => errorMessage = e.toString());
            } finally {
              if (mounted && dialogContext.mounted) dialogSetState(() => isAdding = false);
            }
          }

          return AlertDialog(
            title: const Text('Add Contact'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: contactController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => performSearch(),
                    decoration: InputDecoration(
                      hintText: 'Search users by name',
                      labelText: 'Search term',
                      errorText: errorMessage,
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: isSearching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                            )
                          : IconButton(icon: const Icon(Icons.search), onPressed: performSearch),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (searchResults.isNotEmpty)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: searchResults.map((result) {
                            final status = existingStatus[result.id];
                            final alreadyLinked = status != null;
                            return Column(
                              children: [
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(result.name),
                                  subtitle: Text(result.username),
                                  trailing: alreadyLinked
                                      ? _RelationChip(status: status)
                                      : ElevatedButton(
                                          onPressed: isAdding ? null : () => addUser(result),
                                          child: const Text('Add'),
                                        ),
                                ),
                                const Divider(height: 1),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isAdding ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddContactDialog,
        tooltip: 'Add Contact',
        child: const Icon(Icons.person_add),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search contacts...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: const Color(0xFF1A2A5C),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),

          // Content
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline, size: 64, color: Colors.red),
                            const SizedBox(height: 16),
                            Text('Error loading contacts', style: Theme.of(context).textTheme.headlineSmall),
                            const SizedBox(height: 8),
                            Text(_error!, textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            ElevatedButton(onPressed: _load, child: const Text('Retry')),
                          ],
                        ),
                      )
                    : _filtered.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _searchController.text.isEmpty ? Icons.people_outline : Icons.search_off,
                                  size: 64,
                                  color: Colors.grey,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _searchController.text.isEmpty ? 'No contacts yet.' : 'No contacts found.',
                                  style: Theme.of(context).textTheme.headlineSmall,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _searchController.text.isEmpty
                                      ? 'Add some contacts to start chatting!'
                                      : 'Try a different search term.',
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              itemCount: _filtered.length,
                              itemBuilder: (context, index) {
                                final contact = _filtered[index];
                                return _ContactTile(
                                  contact: contact,
                                  initials: _getInitials(contact.name),
                                  currentUserId: _currentUserId,
                                  token: widget.token,
                                  onBlock: () => _toggleBlock(contact),
                                  onAccept: () => _acceptInvite(contact),
                                  onIgnore: () => _dismissInvite(contact),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Contact tile
// ---------------------------------------------------------------------------

class _ContactTile extends StatelessWidget {
  final Contact contact;
  final String initials;
  final String currentUserId;
  final String token;
  final VoidCallback onBlock;
  final VoidCallback onAccept;
  final VoidCallback onIgnore;

  const _ContactTile({
    required this.contact,
    required this.initials,
    required this.currentUserId,
    required this.token,
    required this.onBlock,
    required this.onAccept,
    required this.onIgnore,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = contact.status;
    final isAccepted = status == 'accepted';
    final isBlocked = status == 'blocked';
    final isPending = status == 'pending';
    final isInvited = status == 'invited';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: isAccepted
            ? () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      token: token,
                      currentUserId: currentUserId,
                      contact: contact,
                    ),
                  ),
                )
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 24,
                backgroundColor: isBlocked
                    ? Colors.grey.shade700
                    : theme.colorScheme.primary,
                child: Text(
                  initials,
                  style: TextStyle(
                    color: isBlocked ? Colors.grey.shade400 : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contact.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isBlocked ? Colors.grey.shade500 : null,
                      ),
                    ),
                    const SizedBox(height: 3),
                    _StatusChip(status: status),
                  ],
                ),
              ),

              // Trailing actions
              if (isAccepted || isBlocked)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 20),
                  onSelected: (value) {
                    if (value == 'block') onBlock();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'block',
                      child: Row(
                        children: [
                          Icon(
                            isBlocked ? Icons.lock_open : Icons.block,
                            size: 18,
                            color: isBlocked ? Colors.green : Colors.red,
                          ),
                          const SizedBox(width: 8),
                          Text(isBlocked ? 'Unblock' : 'Block'),
                        ],
                      ),
                    ),
                  ],
                )
              else if (isPending)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Tooltip(
                    message: 'Invite sent — waiting for response',
                    child: Icon(Icons.hourglass_top, size: 18, color: Colors.orange),
                  ),
                )
              else if (isInvited)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
            ],
          ),
        ),
      ),
    );
  }
}

// Shown in the search dialog for users already in the contact list.
class _RelationChip extends StatelessWidget {
  final String status;
  const _RelationChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'accepted' => ('Contact', const Color(0xFF22C55E)),
      'pending'  => ('Invite sent', Colors.orange),
      'invited'  => ('Invited you', Colors.blue),
      'blocked'  => ('Blocked', Colors.red),
      _          => (status, Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (status) {
      case 'accepted':
        color = const Color(0xFF22C55E);
        label = 'Contact';
      case 'pending':
        color = Colors.orange;
        label = 'Invite sent';
      case 'invited':
        color = Colors.blue;
        label = 'Wants to connect';
      case 'blocked':
        color = Colors.red.shade400;
        label = 'Blocked';
      default:
        color = Colors.grey;
        label = status;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }
}
