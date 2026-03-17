import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:concord/data/state/concord_controller.dart';

class ServerSettingsScreen extends ConsumerStatefulWidget {
  const ServerSettingsScreen({
    super.key,
    required this.serverId,
  });

  final String serverId;

  @override
  ConsumerState<ServerSettingsScreen> createState() =>
      _ServerSettingsScreenState();
}

class _ServerSettingsScreenState extends ConsumerState<ServerSettingsScreen> {
  final _nameController = TextEditingController();
  final _iconController = TextEditingController();
  bool _initialized = false;

  @override
  void dispose() {
    _nameController.dispose();
    _iconController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(concordControllerProvider);
    final controller = ref.read(concordControllerProvider.notifier);
    final server = state.servers[widget.serverId];

    if (server == null) {
      return const Scaffold(
        body: Center(child: Text('Server not found')),
      );
    }

    if (!_initialized) {
      _nameController.text = server.name;
      _iconController.text = server.icon;
      _initialized = true;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Server Settings'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Overview',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Server name',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _iconController,
                        maxLength: 2,
                        decoration: const InputDecoration(
                          labelText: 'Server icon text (2 letters)',
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Members: ${server.memberIds.length}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      Text(
                        'Text Channels: ${server.channelIds.length}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  controller.updateServerSettings(
                    serverId: server.id,
                    name: _nameController.text,
                    icon: _iconController.text,
                  );

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Server settings saved')),
                  );
                },
                child: const Text('Save Changes'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
