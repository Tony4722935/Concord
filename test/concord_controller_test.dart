import 'package:flutter_test/flutter_test.dart';

import 'package:concord/data/models/user_settings.dart';
import 'package:concord/data/state/concord_controller.dart';

void main() {
  group('ConcordController', () {
    test('adds new friend by username', () {
      final controller = ConcordController();

      final before = controller.state.friends.length;
      final result = controller.addFriendByUsername('charlie');

      expect(result, AddFriendResult.added);
      expect(controller.state.friends.length, before + 1);
      expect(
        controller.state.users.values.any((user) => user.username == 'charlie'),
        isTrue,
      );
    });

    test('creates server with first channel and selects it', () {
      final controller = ConcordController();
      final serverId = controller.createServer(
        name: 'Gaming Squad',
        firstChannelName: 'general',
      );

      expect(serverId, isNotNull);
      expect(controller.state.selectedServerId, serverId);

      final server = controller.state.servers[serverId!];
      expect(server, isNotNull);
      expect(server!.channelIds.length, 1);
      expect(controller.state.selectedChannelId, server.channelIds.first);
    });

    test('updates user settings', () {
      final controller = ConcordController();
      controller.updateUserSettings(
        displayName: 'Tony Prime',
        customStatus: 'Refactoring',
        presence: UserPresence.idle,
        allowDirectMessages: false,
      );

      final settings = controller.state.userSettings;
      expect(settings.displayName, 'Tony Prime');
      expect(settings.customStatus, 'Refactoring');
      expect(settings.presence, UserPresence.idle);
      expect(settings.allowDirectMessages, isFalse);
    });
  });
}
