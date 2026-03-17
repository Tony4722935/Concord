import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:concord/data/state/concord_controller.dart';
import 'package:concord/features/friends/friends_screen.dart';
import 'package:concord/features/servers/servers_screen.dart';
import 'package:concord/features/settings/user_settings_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 1;
  Timer? _retentionTimer;

  static const _pages = [
    FriendsScreen(),
    ServersScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _retentionTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      ref.read(concordControllerProvider.notifier).runRetentionSweep();
    });
  }

  @override
  void dispose() {
    _retentionTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    final state = ref.watch(concordControllerProvider);

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            Container(
              width: 98,
              color: const Color(0xFF15161A),
              child: Column(
                children: [
                  const SizedBox(height: 18),
                  const Text(
                    'CON',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _RailButton(
                    selected: _index == 0,
                    icon: Icons.group,
                    label: 'Friends',
                    onTap: () => setState(() => _index = 0),
                  ),
                  _RailButton(
                    selected: _index == 1,
                    icon: Icons.hub,
                    label: 'Servers',
                    onTap: () => setState(() => _index = 1),
                  ),
                  const Spacer(),
                  _RailButton(
                    selected: false,
                    icon: Icons.settings,
                    label: 'Settings',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const UserSettingsScreen(),
                        ),
                      );
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      state.userSettings.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _pages[_index]),
          ],
        ),
      );
    }

    return Scaffold(
      body: _pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.group),
            label: 'Friends',
          ),
          NavigationDestination(
            icon: Icon(Icons.hub),
            label: 'Servers',
          ),
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Material(
        color: selected ? const Color(0xFF5865F2) : const Color(0xFF2B2D31),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: double.infinity,
            height: 64,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
