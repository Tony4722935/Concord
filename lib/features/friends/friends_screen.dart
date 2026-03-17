import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:concord/core/widgets/user_avatar.dart';
import 'package:concord/data/state/concord_controller.dart';
import 'package:concord/features/chat/chat_screen.dart';
import 'package:concord/features/settings/user_settings_screen.dart';

class FriendsScreen extends ConsumerWidget {
  const FriendsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(concordControllerProvider);
    final controller = ref.read(concordControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Friends'),
        actions: [
          IconButton(
            tooltip: 'Add friend',
            onPressed: () => _showAddFriendDialog(context, ref),
            icon: const Icon(Icons.person_add_alt_1),
          ),
          IconButton(
            tooltip: 'User settings',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const UserSettingsScreen(),
                ),
              );
            },
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Text(
              'All Friends (${state.friends.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: state.friends.length,
              itemBuilder: (context, index) {
                final friend = state.friends[index];
                final user = state.users[friend.userId];
                if (user == null) {
                  return const SizedBox.shrink();
                }

                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: ListTile(
                    leading: Stack(
                      children: [
                        UserAvatar(
                            url: user.avatarUrl, fallback: user.username),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: CircleAvatar(
                            radius: 6,
                            backgroundColor: friend.isOnline
                                ? Colors.greenAccent
                                : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    title: Text(user.username),
                    subtitle: Text(friend.note),
                    trailing: FilledButton.tonalIcon(
                      onPressed: () {
                        controller.openDirectMessage(user.id);
                        final channelId = ref
                            .read(concordControllerProvider)
                            .selectedChannelId;

                        Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => Scaffold(
                              appBar:
                                  AppBar(title: Text('DM ? ${user.username}')),
                              body: ChatScreen(
                                channelId: channelId,
                                compact: true,
                              ),
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('Message'),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddFriendDialog(context, ref),
        icon: const Icon(Icons.person_add),
        label: const Text('Add Friend'),
      ),
    );
  }

  Future<void> _showAddFriendDialog(BuildContext context, WidgetRef ref) async {
    final usernameController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Friend'),
          content: TextField(
            controller: usernameController,
            decoration: const InputDecoration(
              labelText: 'Username',
              hintText: 'alice',
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => Navigator.pop(context),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final result = ref
                    .read(concordControllerProvider.notifier)
                    .addFriendByUsername(usernameController.text);

                Navigator.pop(context);
                _showAddFriendFeedback(context, result);
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    usernameController.dispose();
  }

  void _showAddFriendFeedback(BuildContext context, AddFriendResult result) {
    final message = switch (result) {
      AddFriendResult.added => 'Friend added successfully.',
      AddFriendResult.alreadyFriends =>
        'This user is already in your friends list.',
      AddFriendResult.invalidUsername => 'Please enter a valid username.',
      AddFriendResult.cannotAddYourself => 'You cannot add yourself.',
    };

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
