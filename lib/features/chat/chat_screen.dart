import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "package:concord/data/state/concord_controller.dart";
import "package:concord/features/chat/chat_composer.dart";
import "package:concord/features/chat/message_tile.dart";

class ChatScreen extends ConsumerWidget {
  const ChatScreen({
    super.key,
    this.channelId,
    this.compact = false,
  });

  final String? channelId;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(concordControllerProvider);
    final controller = ref.read(concordControllerProvider.notifier);

    final effectiveChannelId = channelId ?? appState.selectedChannelId;
    final channel = appState.channels[effectiveChannelId];
    if (channel == null) {
      return const Center(child: Text('Channel not found'));
    }

    final messages = appState.messagesByChannel[effectiveChannelId] ?? const [];

    return Column(
      children: [
        if (!compact)
          Material(
            color: const Color(0xFF2B2D31),
            child: ListTile(
              leading: const Icon(Icons.tag),
              title: Text(channel.name),
              subtitle: Text(
                channel.type.name == 'dm' ? 'Direct message' : 'Text channel',
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            reverse: true,
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final message = messages[messages.length - 1 - index];
              final author = appState.users[message.authorId];
              if (author == null) {
                return const SizedBox.shrink();
              }

              return MessageTile(
                message: message,
                author: author,
                isMine: message.authorId == appState.currentUserId,
                onDelete: () => controller.deleteOwnMessage(
                  channelId: effectiveChannelId,
                  messageId: message.id,
                ),
                onEdit: () => _openEditDialog(
                  context: context,
                  initialValue: message.text ?? '',
                  onSave: (value) => controller.editOwnMessage(
                    channelId: effectiveChannelId,
                    messageId: message.id,
                    nextText: value,
                  ),
                ),
              );
            },
          ),
        ),
        ChatComposer(
          onSendText: (value) =>
              controller.sendTextMessage(effectiveChannelId, value),
          onSendImage: (value) =>
              controller.sendImageMessage(effectiveChannelId, value),
        ),
      ],
    );
  }

  Future<void> _openEditDialog({
    required BuildContext context,
    required String initialValue,
    required ValueChanged<String> onSave,
  }) async {
    final controller = TextEditingController(text: initialValue);

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Message'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(hintText: 'Message content'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              onSave(controller.text);
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    controller.dispose();
  }
}
