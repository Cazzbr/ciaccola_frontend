class Contact {
  /// Subdocument `_id` from the profile contacts array.
  /// Used as the `:id` path param for PATCH /api/users/contacts/:id (block toggle).
  final String subDocId;

  /// The actual user ID (contact_id._id).
  final String id;

  final String username;
  final String name;

  /// Relationship status: pending | invited | accepted | blocked | deleted
  final String status;

  final String? lastSeen;

  const Contact({
    this.subDocId = '',
    required this.id,
    required this.username,
    required this.name,
    this.status = 'pending',
    this.lastSeen,
  });

  Contact copyWith({String? status}) => Contact(
        subDocId: subDocId,
        id: id,
        username: username,
        name: name,
        status: status ?? this.status,
        lastSeen: lastSeen,
      );

  factory Contact.fromJson(Map<String, dynamic> json) {
    final contactId = json['contact_id'];

    if (contactId is Map<String, dynamic>) {
      // Profile contacts format:
      // { "_id": "<subDocId>", "contact_id": { "_id": "...", "username": "...", "last_seen": "..." }, "status": "..." }
      return Contact(
        subDocId: json['_id']?.toString() ?? '',
        id: contactId['_id']?.toString() ?? '',
        username: contactId['username']?.toString() ?? '',
        name: contactId['username']?.toString() ?? '',
        status: json['status']?.toString() ?? 'pending',
        lastSeen: contactId['last_seen']?.toString(),
      );
    }

    // Search results format:
    // { "_id": "<userId>", "username": "...", "role": "...", "last_seen": "...", "createdAt": "..." }
    return Contact(
      subDocId: '',
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      name: json['username']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      lastSeen: json['last_seen']?.toString(),
    );
  }
}
