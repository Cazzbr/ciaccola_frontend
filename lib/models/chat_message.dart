class ChatMessage {
  final int? localId;
  final String messageId;
  final String contactId;
  final String text;
  final int timestamp;
  final bool isSentByMe;
  final bool isQueued;
  final bool deleted;
  /// Local file path for audio messages; null for text messages.
  final String? audioPath;

  const ChatMessage({
    this.localId,
    required this.messageId,
    required this.contactId,
    required this.text,
    required this.timestamp,
    required this.isSentByMe,
    required this.isQueued,
    required this.deleted,
    this.audioPath,
  });

  bool get isAudio => audioPath != null && audioPath!.isNotEmpty;

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      localId: map['localId'] as int?,
      messageId: map['messageId'].toString(),
      contactId: map['contactId'].toString(),
      text: (map['message'] ?? '').toString(),
      timestamp: map['timestamp'] as int,
      isSentByMe: (map['isSentByMe'] as int? ?? 0) == 1,
      isQueued: (map['isQueued'] as int? ?? 0) == 1,
      deleted: (map['deleted'] as int? ?? 0) == 1,
      audioPath: map['audioPath'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'localId': localId,
      'messageId': messageId,
      'contactId': contactId,
      'message': text,
      'timestamp': timestamp,
      'isSentByMe': isSentByMe ? 1 : 0,
      'isQueued': isQueued ? 1 : 0,
      'deleted': deleted ? 1 : 0,
      'audioPath': audioPath,
    };
  }

  ChatMessage copyWith({
    int? localId,
    String? messageId,
    String? contactId,
    String? text,
    int? timestamp,
    bool? isSentByMe,
    bool? isQueued,
    bool? deleted,
    String? audioPath,
  }) {
    return ChatMessage(
      localId: localId ?? this.localId,
      messageId: messageId ?? this.messageId,
      contactId: contactId ?? this.contactId,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      isSentByMe: isSentByMe ?? this.isSentByMe,
      isQueued: isQueued ?? this.isQueued,
      deleted: deleted ?? this.deleted,
      audioPath: audioPath ?? this.audioPath,
    );
  }
}
