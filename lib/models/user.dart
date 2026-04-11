class User {
  final String id;
  final String username;
  final String? email;
  final String role;
  final String? photo;

  User({
    required this.id,
    required this.username,
    this.email,
    required this.role,
    this.photo,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      email: json['email']?.toString(),
      role: json['role']?.toString() ?? 'user',
      photo: json['photo']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      if (email != null) 'email': email,
      'role': role,
      if (photo != null) 'photo': photo,
    };
  }

  User copyWith({
    String? id,
    String? username,
    String? email,
    String? role,
    String? photo,
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      email: email ?? this.email,
      role: role ?? this.role,
      photo: photo ?? this.photo,
    );
  }
}
