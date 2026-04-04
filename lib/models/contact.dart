class Contact {
  final String id;
  final String username;
  final String name;
  final String status;

  const Contact({
    required this.id,
    required this.username,
    required this.name,
    this.status = 'pending',
  });

  factory Contact.fromJson(Map<String, dynamic> json) {
    final rawUsername = json['username'] ?? json['contact_username'] ?? json['name'];
    final rawName = json['name'] ?? json['contact_username'] ?? json['username'];

    return Contact(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      username: rawUsername?.toString() ?? '',
      name: rawName?.toString() ?? '',
      status: (json['status'] ?? 'pending').toString(),
    );
  }
}
