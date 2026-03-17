import "package:concord/data/models/chat_message.dart";

class RetentionPolicy {
  static const Duration messageRetention = Duration(days: 365);
  static const Duration uploadRetention = Duration(days: 7);

  const RetentionPolicy();

  Map<String, List<ChatMessage>> enforce(
    Map<String, List<ChatMessage>> messagesByChannel,
    DateTime now,
  ) {
    final cutoff = now.subtract(messageRetention);
    final next = <String, List<ChatMessage>>{};

    for (final entry in messagesByChannel.entries) {
      final filtered = entry.value
          .where((message) => message.createdAt.isAfter(cutoff))
          .map((message) => _expireImageIfNeeded(message, now))
          .toList(growable: false);

      next[entry.key] = filtered;
    }

    return next;
  }

  ChatMessage _expireImageIfNeeded(ChatMessage message, DateTime now) {
    if (message.type != MessageType.image || message.imageExpiresAt == null) {
      return message;
    }

    if (now.isBefore(message.imageExpiresAt!)) {
      return message;
    }

    if (message.imageUrl == null) {
      return message;
    }

    return message.copyWith(
      imageUrl: null,
      text: 'Image removed after 7 days.',
    );
  }
}
