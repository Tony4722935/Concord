enum MessageType {
  text,
  image,
  system,
}

class ChatMessage {
  static const Object _unset = Object();

  const ChatMessage({
    required this.id,
    required this.channelId,
    required this.authorId,
    required this.type,
    required this.createdAt,
    this.text,
    this.imageUrl,
    this.imageExpiresAt,
    this.editedAt,
    this.isDeleted = false,
  });

  final String id;
  final String channelId;
  final String authorId;
  final MessageType type;
  final String? text;
  final String? imageUrl;
  final DateTime createdAt;
  final DateTime? imageExpiresAt;
  final DateTime? editedAt;
  final bool isDeleted;

  bool get hasEditableText => type == MessageType.text && !isDeleted;

  ChatMessage copyWith({
    String? text,
    Object? imageUrl = _unset,
    Object? imageExpiresAt = _unset,
    DateTime? editedAt,
    bool? isDeleted,
  }) {
    return ChatMessage(
      id: id,
      channelId: channelId,
      authorId: authorId,
      type: type,
      createdAt: createdAt,
      text: text ?? this.text,
      imageUrl:
          identical(imageUrl, _unset) ? this.imageUrl : imageUrl as String?,
      imageExpiresAt: identical(imageExpiresAt, _unset)
          ? this.imageExpiresAt
          : imageExpiresAt as DateTime?,
      editedAt: editedAt ?? this.editedAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}
