class Contact {
  final String id;
  final String name;

  const Contact({required this.id, required this.name});

  factory Contact.fromJson(Map<String, dynamic> json) {
    return Contact(
      id: json['id'].toString(),
      name: (json['name'] ?? '').toString(),
    );
  }
}
