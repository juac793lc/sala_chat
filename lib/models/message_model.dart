class MessageModel {
  final String id;
  final String content;
  final String type; // text | media | audio | etc
  final String roomId;
  final MessageSender sender;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;
  final String? mediaId;
  final List<MessageReaction> reactions;
  final List<MessageRead> readBy;

  MessageModel({
    required this.id,
    required this.content,
    required this.type,
    required this.roomId,
    required this.sender,
    required this.createdAt,
    required this.updatedAt,
    required this.isDeleted,
    this.mediaId,
    this.reactions = const [],
    this.readBy = const [],
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    DateTime _parseDate(dynamic v) {
      try { return DateTime.parse(v.toString()); } catch (_) { return DateTime.now(); }
    }
    return MessageModel(
      id: json['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      content: json['content']?.toString() ?? '',
      type: json['type']?.toString() ?? 'text',
      roomId: json['roomId']?.toString() ?? json['room']?.toString() ?? 'sala-general',
      sender: MessageSender.fromJson(json['sender'] is Map ? Map<String,dynamic>.from(json['sender']) : {}),
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
      isDeleted: json['isDeleted'] == true,
      mediaId: json['mediaId']?.toString(),
      reactions: (json['reactions'] as List? ?? []).map((r) => MessageReaction.fromJson(r)).toList(),
      readBy: (json['readBy'] as List? ?? []).map((r) => MessageRead.fromJson(r)).toList(),
    );
  }
}

class MessageSender {
  final String id;
  final String username;
  final String? avatar;
  MessageSender({required this.id, required this.username, this.avatar});
  factory MessageSender.fromJson(Map<String, dynamic> json) => MessageSender(
    id: json['id']?.toString() ?? json['userId']?.toString() ?? 'user-temp',
    username: json['username']?.toString() ?? 'Usuario',
    avatar: json['avatar']?.toString(),
  );
}

class MessageReaction {
  final String userId;
  final String emoji;
  final DateTime createdAt;
  MessageReaction({required this.userId, required this.emoji, required this.createdAt});
  factory MessageReaction.fromJson(Map<String, dynamic> json) => MessageReaction(
    userId: json['user']?.toString() ?? json['userId']?.toString() ?? 'user-temp',
    emoji: json['emoji']?.toString() ?? '👍',
    createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
  );
}

class MessageRead {
  final String userId;
  final DateTime readAt;
  MessageRead({required this.userId, required this.readAt});
  factory MessageRead.fromJson(Map<String, dynamic> json) => MessageRead(
    userId: json['user']?.toString() ?? json['userId']?.toString() ?? 'user-temp',
    readAt: DateTime.tryParse(json['readAt']?.toString() ?? '') ?? DateTime.now(),
  );
}
