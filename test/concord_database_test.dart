import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:concord/data/db/concord_database.dart';
import 'package:concord/data/models/user_settings.dart';

void main() {
  test('ConcordDatabase persists and reloads state', () {
    final tempDir = Directory.systemTemp.createTempSync('concord_db_test');
    final dbPath = p.join(tempDir.path, 'concord.sqlite');
    final database = ConcordDatabase.openAtPath(dbPath);

    try {
      final seeded = database.loadOrSeedState();
      final withSettings = seeded.copyWith(
        userSettings: seeded.userSettings.copyWith(
          displayName: 'TonyPersisted',
          customStatus: 'Working',
          presence: UserPresence.idle,
          allowDirectMessages: false,
        ),
      );

      database.saveState(withSettings);

      final loaded = database.loadOrSeedState();
      expect(loaded.userSettings.displayName, 'TonyPersisted');
      expect(loaded.userSettings.presence, UserPresence.idle);
      expect(loaded.userSettings.allowDirectMessages, isFalse);
      expect(loaded.servers.isNotEmpty, isTrue);
      expect(loaded.channels.isNotEmpty, isTrue);
    } finally {
      database.close();
      tempDir.deleteSync(recursive: true);
    }
  });

  test('seed fallback still provides usable state when database is empty', () {
    final tempDir = Directory.systemTemp.createTempSync('concord_db_seed');
    final dbPath = p.join(tempDir.path, 'concord.sqlite');
    final database = ConcordDatabase.openAtPath(dbPath);

    try {
      final loaded = database.loadOrSeedState();
      expect(loaded.currentUserId, isNotEmpty);
      expect(loaded.selectedServerId, isNotEmpty);
      expect(loaded.selectedChannelId, isNotEmpty);
    } finally {
      database.close();
      tempDir.deleteSync(recursive: true);
    }
  });
}
