class Contact {
  final String subDocId;
  final String id;
  final String username;
  final String name;
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
      return Contact(
        subDocId: json['_id']?.toString() ?? '',
        id: contactId['_id']?.toString() ?? '',
        username: contactId['username']?.toString() ?? '',
        name: contactId['username']?.toString() ?? '',
        status: json['status']?.toString() ?? 'pending',
        lastSeen: contactId['last_seen']?.toString(),
      );
    }

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
