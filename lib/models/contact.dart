class Contact {
  final String id;
  final String username;
  final String name;
  final String status;
  final String? lastSeen;

  const Contact({
    required this.id,
    required this.username,
    required this.name,
    this.status = 'pending',
    this.lastSeen,
  });

  factory Contact.fromJson(Map<String, dynamic> json) {
    final contactId = json['contact_id'];
    if (contactId is Map<String, dynamic>) {
      return Contact(
        id: contactId['_id']?.toString() ?? '',
        username: contactId['username']?.toString() ?? '',
        name: contactId['username']?.toString() ?? '',
        status: json['status']?.toString() ?? 'pending',
        lastSeen: contactId['last_seen']?.toString(),
      );
    } else {
      // Fallback for old format
      final rawUsername = json['username'] ?? json['contact_username'] ?? json['name'];
      final rawName = json['name'] ?? json['contact_username'] ?? json['username'];

      return Contact(
        id: json['contact_id']?.toString() ?? json['_id']?.toString() ?? json['id']?.toString() ?? '',
        username: rawUsername?.toString() ?? '',
        name: rawName?.toString() ?? '',
        status: (json['status'] ?? 'pending').toString(),
        lastSeen: null,
      );
    }
  }
}
