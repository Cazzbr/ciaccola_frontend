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
  List<Contact> _filteredContacts = [];
  String _currentUserId = 'me';

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(_filterContacts);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showAddContactDialog() {
    final contactController = TextEditingController();
    final mainContext = context;
    bool isSearching = false;
    bool isAdding = false;
    String? errorMessage;
    List<Contact> searchResults = [];

    showDialog(
      context: mainContext,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, dialogSetState) {
          Future<void> performSearch() async {
            final term = contactController.text.trim();
            if (term.isEmpty) {
              if (dialogContext.mounted) {
                dialogSetState(() => errorMessage = 'Enter a username to search');
              }
              return;
            }

            if (dialogContext.mounted) {
              dialogSetState(() {
                isSearching = true;
                errorMessage = null;
                searchResults = [];
              });
            }

            try {
              final results = await _contactService.searchUsers(widget.token, term, limit: 12);
              if (!mounted || !dialogContext.mounted) return;
              dialogSetState(() {
                searchResults = results;
                if (results.isEmpty) {
                  errorMessage = 'No users found for "$term".';
                }
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
            dialogSetState(() {
              isAdding = true;
              errorMessage = null;
            });

            try {
              await _contactService.addContact(widget.token, contact.username);
              if (!mounted) return;
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext);
              }
              await _load();
              if (!mounted) return;
              if (!mainContext.mounted) return;
              ScaffoldMessenger.of(mainContext).showSnackBar(
                SnackBar(
                  content: Text('Contact added: ${contact.username}'),
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
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : IconButton(
                              icon: const Icon(Icons.search),
                              onPressed: performSearch,
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
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
                            return Column(
                              children: [
                                ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 0),
                                  title: Text(result.name),
                                  subtitle: Text(result.status),
                                  trailing: ElevatedButton(
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

  Future<void> _load() async {
    try {
      _currentUserId = _extractUserId(widget.token) ?? 'me';
      final contacts = await _contactService.fetchContacts(widget.token);
      
      if (mounted) {
        setState(() {
          _contacts = contacts;
          _filteredContacts = contacts;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _filterContacts() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredContacts = _contacts.where((contact) =>
        contact.name.toLowerCase().contains(query)
      ).toList();
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

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'online':
        return Colors.green;
      case 'away':
        return Colors.orange;
      case 'busy':
        return Colors.red;
      case 'offline':
        return Colors.grey;
      default:
        return Colors.blue;
    }
  }

  String _getInitials(String name) {
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
        elevation: 0,
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddContactDialog,
        tooltip: 'Add Contact',
        child: const Icon(Icons.person_add),
      ),
      body: Column(
        children: [
          // Search Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
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
                            Text(
                              'Error loading contacts',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _load,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : _filteredContacts.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _searchController.text.isEmpty
                                      ? Icons.people_outline
                                      : Icons.search_off,
                                  size: 64,
                                  color: Colors.grey,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _searchController.text.isEmpty
                                      ? 'No contacts yet.'
                                      : 'No contacts found.',
                                  style: Theme.of(context).textTheme.headlineSmall,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _searchController.text.isEmpty
                                      ? 'Add some contacts to start chatting!'
                                      : 'Try a different search term.',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _filteredContacts.length,
                              itemBuilder: (context, index) {
                                final contact = _filteredContacts[index];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  elevation: 2,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
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
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Row(
                                        children: [
                                          // Avatar
                                          Container(
                                            width: 50,
                                            height: 50,
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [
                                                  Theme.of(context).colorScheme.primary,
                                                  Theme.of(context).colorScheme.secondary,
                                                ],
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              ),
                                              borderRadius: BorderRadius.circular(25),
                                            ),
                                            child: Center(
                                              child: Text(
                                                _getInitials(contact.name),
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 18,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          
                                          // Contact Info
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  contact.name,
                                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    Container(
                                                      width: 8,
                                                      height: 8,
                                                      decoration: BoxDecoration(
                                                        color: _getStatusColor(contact.status),
                                                        shape: BoxShape.circle,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      contact.status,
                                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                        color: Colors.grey[600],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          
                                          // Arrow Icon
                                          Icon(
                                            Icons.chevron_right,
                                            color: Colors.grey[400],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
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
