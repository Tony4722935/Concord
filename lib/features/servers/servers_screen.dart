import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:concord/data/state/concord_controller.dart';
import 'package:concord/features/chat/chat_screen.dart';
import 'package:concord/features/servers/server_settings_screen.dart';
import 'package:concord/features/settings/user_settings_screen.dart';

class ServersScreen extends ConsumerWidget {
  const ServersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(concordControllerProvider);
    final controller = ref.read(concordControllerProvider.notifier);
    final selectedServer = state.servers[state.selectedServerId];

    if (selectedServer == null) {
      return const Center(child: Text('No server selected'));
    }

    final channels = state.channelsForSelectedServer;
    final isWide = MediaQuery.sizeOf(context).width >= 1000;

    if (isWide) {
      return Row(
        children: [
          Container(
            width: 86,
            color: const Color(0xFF1E1F22),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Expanded(
                  child: ListView(
                    children: state.servers.values.map((server) {
                      final selected = server.id == state.selectedServerId;
                      return Padding(
                        padding: const EdgeInsets.all(8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => controller.selectServer(server.id),
                          child: Container(
                            height: 56,
                            decoration: BoxDecoration(
                              color: selected
                                  ? const Color(0xFF5865F2)
                                  : const Color(0xFF2B2D31),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Center(
                              child: Text(
                                server.icon,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(growable: false),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
                  child: IconButton.filled(
                    onPressed: () => _showCreateServerDialog(context, ref),
                    icon: const Icon(Icons.add),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 280,
            color: const Color(0xFF2B2D31),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  title: Text(selectedServer.name),
                  subtitle: const Text('Text channels'),
                  trailing: IconButton(
                    tooltip: 'Server settings',
                    icon: const Icon(Icons.settings),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              ServerSettingsScreen(serverId: selectedServer.id),
                        ),
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    children: [
                      ...channels.map((channel) {
                        final selected = channel.id == state.selectedChannelId;
                        return ListTile(
                          leading: const Icon(Icons.tag, size: 18),
                          title: Text(channel.name),
                          selected: selected,
                          onTap: () => controller.selectChannel(channel.id),
                        );
                      }),
                      ListTile(
                        leading: const Icon(Icons.add),
                        title: const Text('Create channel'),
                        onTap: () => _showCreateChannelDialog(
                          context,
                          ref,
                          selectedServer.id,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.headset_mic_outlined),
                  title: const Text('Voice Chat'),
                  subtitle: const Text('Coming in next phase'),
                  onTap: () {},
                ),
              ],
            ),
          ),
          const Expanded(child: ChatScreen()),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Servers'),
        actions: [
          IconButton(
            tooltip: 'Create server',
            onPressed: () => _showCreateServerDialog(context, ref),
            icon: const Icon(Icons.add_circle_outline),
          ),
          IconButton(
            tooltip: 'Server settings',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      ServerSettingsScreen(serverId: selectedServer.id),
                ),
              );
            },
            icon: const Icon(Icons.tune),
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
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: state.selectedServerId,
                  decoration: const InputDecoration(labelText: 'Server'),
                  items: state.servers.values
                      .map(
                        (server) => DropdownMenuItem(
                          value: server.id,
                          child: Text(server.name),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value != null) {
                      controller.selectServer(value);
                    }
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: state.selectedChannelId,
                  decoration: const InputDecoration(labelText: 'Channel'),
                  items: channels
                      .map(
                        (channel) => DropdownMenuItem(
                          value: channel.id,
                          child: Text('# ${channel.name}'),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value != null) {
                      controller.selectChannel(value);
                    }
                  },
                ),
              ],
            ),
          ),
          const Expanded(child: ChatScreen(compact: true)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            _showCreateChannelDialog(context, ref, state.selectedServerId),
        icon: const Icon(Icons.add),
        label: const Text('Channel'),
      ),
    );
  }

  Future<void> _showCreateServerDialog(
      BuildContext context, WidgetRef ref) async {
    final serverNameController = TextEditingController();
    final channelNameController = TextEditingController(text: 'general');

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Server'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: serverNameController,
              decoration: const InputDecoration(labelText: 'Server name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: channelNameController,
              decoration: const InputDecoration(labelText: 'First channel'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final serverId =
                  ref.read(concordControllerProvider.notifier).createServer(
                        name: serverNameController.text,
                        firstChannelName: channelNameController.text,
                      );

              Navigator.pop(context);
              final ok = serverId != null;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    ok
                        ? 'Server created successfully.'
                        : 'Enter valid server and channel names.',
                  ),
                ),
              );
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );

    serverNameController.dispose();
    channelNameController.dispose();
  }

  Future<void> _showCreateChannelDialog(
    BuildContext context,
    WidgetRef ref,
    String serverId,
  ) async {
    final channelController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Channel'),
        content: TextField(
          controller: channelController,
          decoration: const InputDecoration(
            labelText: 'Channel name',
            hintText: 'general',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final channelId =
                  ref.read(concordControllerProvider.notifier).addServerChannel(
                        serverId: serverId,
                        channelName: channelController.text,
                      );

              Navigator.pop(context);
              final ok = channelId != null;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    ok
                        ? 'Channel created.'
                        : 'Invalid or duplicate channel name.',
                  ),
                ),
              );
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );

    channelController.dispose();
  }
}
