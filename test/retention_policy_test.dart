import 'package:flutter_test/flutter_test.dart';

import 'package:concord/data/models/chat_message.dart';
import 'package:concord/data/state/retention_policy.dart';

void main() {
  group('RetentionPolicy', () {
    test('removes messages older than one year', () {
      final now = DateTime(2026, 3, 15);
      const policy = RetentionPolicy();

      final messages = {
        'ch1': [
          ChatMessage(
            id: 'old',
            channelId: 'ch1',
            authorId: 'u1',
            type: MessageType.text,
            text: 'old',
            createdAt: now.subtract(const Duration(days: 366)),
          ),
          ChatMessage(
            id: 'new',
            channelId: 'ch1',
            authorId: 'u1',
            type: MessageType.text,
            text: 'new',
            createdAt: now.subtract(const Duration(days: 5)),
          ),
        ],
      };

      final result = policy.enforce(messages, now);
      expect(result['ch1']!.length, 1);
      expect(result['ch1']!.single.id, 'new');
    });

    test('removes image payload after 7 days', () {
      final now = DateTime(2026, 3, 15);
      const policy = RetentionPolicy();

      final messages = {
        'ch1': [
          ChatMessage(
            id: 'img',
            channelId: 'ch1',
            authorId: 'u1',
            type: MessageType.image,
            imageUrl: '/tmp/file.png',
            createdAt: now.subtract(const Duration(days: 2)),
            imageExpiresAt: now.subtract(const Duration(hours: 1)),
          ),
        ],
      };

      final result = policy.enforce(messages, now);
      expect(result['ch1']!.single.imageUrl, isNull);
      expect(result['ch1']!.single.text, 'Image removed after 7 days.');
    });
  });
}
