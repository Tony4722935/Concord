import "dart:io";

import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:intl/intl.dart";

import "package:concord/core/widgets/user_avatar.dart";
import "package:concord/data/models/chat_message.dart";
import "package:concord/data/models/concord_user.dart";

class MessageTile extends StatelessWidget {
  const MessageTile({
    super.key,
    required this.message,
    required this.author,
    required this.isMine,
    required this.onEdit,
    required this.onDelete,
  });

  final ChatMessage message;
  final ConcordUser author;
  final bool isMine;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final canEdit = isMine && message.hasEditableText;
    final canDelete = isMine;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(
            url: author.avatarUrl,
            fallback: author.username,
            radius: 16,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:
                    isMine ? const Color(0xFF2E3B7A) : const Color(0xFF313338),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        author.username,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat.Hm().format(message.createdAt),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const Spacer(),
                      if (canEdit || canDelete)
                        PopupMenuButton<String>(
                          itemBuilder: (context) => [
                            if (canEdit)
                              const PopupMenuItem(
                                value: 'edit',
                                child: Text('Edit'),
                              ),
                            if (canDelete)
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete'),
                              ),
                          ],
                          onSelected: (value) {
                            if (value == 'edit') {
                              onEdit();
                            } else if (value == 'delete') {
                              onDelete();
                            }
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (message.type == MessageType.image)
                    _ImageSection(message: message)
                  else
                    Text(message.text ?? ''),
                  if (message.editedAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '(edited)',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageSection extends StatelessWidget {
  const _ImageSection({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final url = message.imageUrl;
    if (url == null) {
      return Text(
        message.text ?? 'Image expired.',
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: Colors.orange[200]),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: _messageImage(url),
        ),
        if (message.imageExpiresAt != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Auto-deletes on server: ${DateFormat('yyyy-MM-dd HH:mm').format(message.imageExpiresAt!)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  Widget _messageImage(String url) {
    if (url.startsWith('http')) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        height: 180,
        width: 240,
        errorBuilder: (_, __, ___) => _errorBox(),
      );
    }

    if (!kIsWeb) {
      return Image.file(
        File(url),
        fit: BoxFit.cover,
        height: 180,
        width: 240,
        errorBuilder: (_, __, ___) => _errorBox(),
      );
    }

    return _errorBox();
  }

  Widget _errorBox() {
    return Container(
      height: 120,
      width: 220,
      alignment: Alignment.center,
      color: const Color(0xFF1E1F22),
      child: const Text('Unable to load image'),
    );
  }
}
