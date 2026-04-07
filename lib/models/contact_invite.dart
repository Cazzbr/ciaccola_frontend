class ContactInvite {
  final String fromUserId;
  final String fromUsername;
  final int timestamp;

  const ContactInvite({
    required this.fromUserId,
    required this.fromUsername,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
        'fromUserId': fromUserId,
        'fromUsername': fromUsername,
        'timestamp': timestamp,
      };

  factory ContactInvite.fromMap(Map<String, dynamic> map) => ContactInvite(
        fromUserId: map['fromUserId'] as String,
        fromUsername: map['fromUsername'] as String,
        timestamp: map['timestamp'] as int,
      );
}
