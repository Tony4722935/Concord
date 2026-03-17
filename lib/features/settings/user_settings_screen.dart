import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:concord/data/models/user_settings.dart';
import 'package:concord/data/state/concord_controller.dart';

class UserSettingsScreen extends ConsumerStatefulWidget {
  const UserSettingsScreen({super.key});

  @override
  ConsumerState<UserSettingsScreen> createState() => _UserSettingsScreenState();
}

class _UserSettingsScreenState extends ConsumerState<UserSettingsScreen> {
  final _displayNameController = TextEditingController();
  final _statusController = TextEditingController();
  bool _initialized = false;
  UserPresence _presence = UserPresence.online;
  bool _allowDms = true;

  @override
  void dispose() {
    _displayNameController.dispose();
    _statusController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(concordControllerProvider);
    final settings = state.userSettings;
    final controller = ref.read(concordControllerProvider.notifier);

    if (!_initialized) {
      _displayNameController.text = settings.displayName;
      _statusController.text = settings.customStatus;
      _presence = settings.presence;
      _allowDms = settings.allowDirectMessages;
      _initialized = true;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('User Settings'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SectionCard(
                title: 'Profile',
                child: Column(
                  children: [
                    TextField(
                      controller: _displayNameController,
                      decoration: const InputDecoration(
                        labelText: 'Display name',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _statusController,
                      decoration: const InputDecoration(
                        labelText: 'Custom status',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<UserPresence>(
                      initialValue: _presence,
                      decoration: const InputDecoration(
                        labelText: 'Presence',
                      ),
                      items: UserPresence.values
                          .map(
                            (presence) => DropdownMenuItem(
                              value: presence,
                              child: Text(_presenceLabel(presence)),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          _presence = value;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile.adaptive(
                      value: _allowDms,
                      onChanged: (value) => setState(() => _allowDms = value),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Allow direct messages'),
                      subtitle: const Text(
                        'Friends can message you directly.',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  controller.updateUserSettings(
                    displayName: _displayNameController.text,
                    customStatus: _statusController.text,
                    presence: _presence,
                    allowDirectMessages: _allowDms,
                  );

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Settings saved')),
                  );
                },
                child: const Text('Save Settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _presenceLabel(UserPresence presence) {
    switch (presence) {
      case UserPresence.online:
        return 'Online';
      case UserPresence.idle:
        return 'Idle';
      case UserPresence.doNotDisturb:
        return 'Do Not Disturb';
      case UserPresence.invisible:
        return 'Invisible';
    }
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
