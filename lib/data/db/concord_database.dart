import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:concord/data/models/channel.dart';
import 'package:concord/data/models/chat_message.dart';
import 'package:concord/data/models/concord_user.dart';
import 'package:concord/data/models/friend.dart';
import 'package:concord/data/models/server.dart';
import 'package:concord/data/models/user_settings.dart';
import 'package:concord/data/state/concord_state.dart';

class ConcordDatabase {
  ConcordDatabase._(this._db) {
    _migrate();
  }

  final Database _db;

  static Future<ConcordDatabase> openDefault() {
    final dataDirectory = Directory(
      p.join(Directory.current.path, '.concord_data'),
    );
    if (!dataDirectory.existsSync()) {
      dataDirectory.createSync(recursive: true);
    }

    final dbFile = p.join(dataDirectory.path, 'concord.sqlite');
    return Future.value(ConcordDatabase.openAtPath(dbFile));
  }

  static ConcordDatabase openAtPath(String dbPath) {
    final db = sqlite3.open(dbPath);
    return ConcordDatabase._(db);
  }

  void close() {
    _db.dispose();
  }

  ConcordState loadOrSeedState() {
    if (_isEmpty()) {
      final seed = ConcordState.seed();
      saveState(seed);
      return seed;
    }

    return _loadState();
  }

  void saveState(ConcordState state) {
    _db.execute('BEGIN TRANSACTION;');
    try {
      _db.execute('DELETE FROM app_meta;');
      _db.execute('DELETE FROM user_settings;');
      _db.execute('DELETE FROM messages;');
      _db.execute('DELETE FROM channel_members;');
      _db.execute('DELETE FROM channels;');
      _db.execute('DELETE FROM server_members;');
      _db.execute('DELETE FROM servers;');
      _db.execute('DELETE FROM friends;');
      _db.execute('DELETE FROM users;');

      for (final user in state.users.values) {
        _db.execute(
          'INSERT INTO users (id, username, avatar_url) VALUES (?, ?, ?);',
          [user.id, user.username, user.avatarUrl],
        );
      }

      for (final friend in state.friends) {
        _db.execute(
          'INSERT INTO friends (user_id, is_online, note) VALUES (?, ?, ?);',
          [friend.userId, friend.isOnline ? 1 : 0, friend.note],
        );
      }

      for (final server in state.servers.values) {
        _db.execute(
          'INSERT INTO servers (id, name, icon) VALUES (?, ?, ?);',
          [server.id, server.name, server.icon],
        );

        for (final memberId in server.memberIds) {
          _db.execute(
            'INSERT INTO server_members (server_id, user_id) VALUES (?, ?);',
            [server.id, memberId],
          );
        }
      }

      for (final channel in state.channels.values) {
        final sortOrder = _channelSortOrder(channel, state);

        _db.execute(
          'INSERT INTO channels (id, name, type, server_id, sort_order) '
          'VALUES (?, ?, ?, ?, ?);',
          [
            channel.id,
            channel.name,
            channel.type.name,
            channel.serverId,
            sortOrder,
          ],
        );

        for (final memberId in channel.memberIds) {
          _db.execute(
            'INSERT INTO channel_members (channel_id, user_id) VALUES (?, ?);',
            [channel.id, memberId],
          );
        }
      }

      for (final entry in state.messagesByChannel.entries) {
        for (final message in entry.value) {
          _db.execute(
            'INSERT INTO messages '
            '(id, channel_id, author_id, type, text, image_url, image_expires_at, '
            'created_at, edited_at, is_deleted) '
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
            [
              message.id,
              message.channelId,
              message.authorId,
              message.type.name,
              message.text,
              message.imageUrl,
              _toEpochMillis(message.imageExpiresAt),
              message.createdAt.millisecondsSinceEpoch,
              _toEpochMillis(message.editedAt),
              message.isDeleted ? 1 : 0,
            ],
          );
        }
      }

      _db.execute(
        'INSERT INTO user_settings '
        '(id, display_name, custom_status, presence, allow_direct_messages) '
        'VALUES (1, ?, ?, ?, ?);',
        [
          state.userSettings.displayName,
          state.userSettings.customStatus,
          state.userSettings.presence.index,
          state.userSettings.allowDirectMessages ? 1 : 0,
        ],
      );

      _db.execute(
        'INSERT INTO app_meta (key, value) VALUES (?, ?);',
        ['selected_server_id', state.selectedServerId],
      );
      _db.execute(
        'INSERT INTO app_meta (key, value) VALUES (?, ?);',
        ['selected_channel_id', state.selectedChannelId],
      );

      _db.execute('COMMIT;');
    } catch (error) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  void _migrate() {
    _db.execute('PRAGMA foreign_keys = ON;');

    _db.execute(
      'CREATE TABLE IF NOT EXISTS users ('
      'id TEXT PRIMARY KEY, '
      'username TEXT NOT NULL, '
      'avatar_url TEXT NOT NULL'
      ');',
    );

    _db.execute(
      'CREATE TABLE IF NOT EXISTS friends ('
      'user_id TEXT PRIMARY KEY, '
      'is_online INTEGER NOT NULL, '
      'note TEXT NOT NULL'
      ');',
    );

    _db.execute(
      'CREATE TABLE IF NOT EXISTS servers ('
      'id TEXT PRIMARY KEY, '
      'name TEXT NOT NULL, '
      'icon TEXT NOT NULL'
      ');',
    );

    _db.execute(
      'CREATE TABLE IF NOT EXISTS server_members ('
      'server_id TEXT NOT NULL, '
      'user_id TEXT NOT NULL'
      ');',
    );

    _db.execute(
      'CREATE TABLE IF NOT EXISTS channels ('
      'id TEXT PRIMARY KEY, '
      'name TEXT NOT NULL, '
      'type TEXT NOT NULL, '
      'server_id TEXT, '
      'sort_order INTEGER NOT NULL DEFAULT 0'
      ');',
    );

    _db.execute(
      'CREATE TABLE IF NOT EXISTS channel_members ('
      'channel_id TEXT NOT NULL, '
      'user_id TEXT NOT NULL'
      ');',
    );

    _db.execute(
      'CREATE TABLE IF NOT EXISTS messages ('
      'id TEXT PRIMARY KEY, '
      'channel_id TEXT NOT NULL, '
      'author_id TEXT NOT NULL, '
      'type TEXT NOT NULL, '
      'text TEXT, '
      'image_url TEXT, '
      'image_expires_at INTEGER, '
      'created_at INTEGER NOT NULL, '
      'edited_at INTEGER, '
      'is_deleted INTEGER NOT NULL DEFAULT 0'
      ');',
    );

    _db.execute(
      'CREATE TABLE IF NOT EXISTS user_settings ('
      'id INTEGER PRIMARY KEY CHECK(id = 1), '
      'display_name TEXT NOT NULL, '
      'custom_status TEXT NOT NULL, '
      'presence INTEGER NOT NULL, '
      'allow_direct_messages INTEGER NOT NULL'
      ');',
    );

    _db.execute(
      'CREATE TABLE IF NOT EXISTS app_meta ('
      'key TEXT PRIMARY KEY, '
      'value TEXT NOT NULL'
      ');',
    );
  }

  bool _isEmpty() {
    final result = _db.select('SELECT COUNT(*) AS c FROM users;');
    final count = result.first['c'] as int;
    return count == 0;
  }

  ConcordState _loadState() {
    final users = <String, ConcordUser>{};
    for (final row
        in _db.select('SELECT id, username, avatar_url FROM users;')) {
      final user = ConcordUser(
        id: row['id'] as String,
        username: row['username'] as String,
        avatarUrl: row['avatar_url'] as String,
      );
      users[user.id] = user;
    }

    final friends = <Friend>[];
    for (final row in _db.select(
      'SELECT user_id, is_online, note FROM friends ORDER BY rowid;',
    )) {
      friends.add(
        Friend(
          userId: row['user_id'] as String,
          isOnline: (row['is_online'] as int) == 1,
          note: row['note'] as String,
        ),
      );
    }

    final servers = <String, Server>{};
    for (final row
        in _db.select('SELECT id, name, icon FROM servers ORDER BY rowid;')) {
      final server = Server(
        id: row['id'] as String,
        name: row['name'] as String,
        icon: row['icon'] as String,
        memberIds: const [],
        channelIds: const [],
      );
      servers[server.id] = server;
    }

    final serverMembers = <String, List<String>>{};
    for (final row in _db.select(
      'SELECT server_id, user_id FROM server_members ORDER BY rowid;',
    )) {
      final serverId = row['server_id'] as String;
      final userId = row['user_id'] as String;
      serverMembers.putIfAbsent(serverId, () => []).add(userId);
    }

    final channels = <String, Channel>{};
    final channelMembers = <String, List<String>>{};

    for (final row in _db.select(
      'SELECT channel_id, user_id FROM channel_members ORDER BY rowid;',
    )) {
      final channelId = row['channel_id'] as String;
      final userId = row['user_id'] as String;
      channelMembers.putIfAbsent(channelId, () => []).add(userId);
    }

    final serverChannelIds = <String, List<String>>{};

    for (final row in _db.select(
      'SELECT id, name, type, server_id FROM channels '
      'ORDER BY CASE WHEN server_id IS NULL THEN 1 ELSE 0 END, server_id, sort_order, rowid;',
    )) {
      final channelId = row['id'] as String;
      final serverId = row['server_id'] as String?;
      final typeName = row['type'] as String;

      final channel = Channel(
        id: channelId,
        name: row['name'] as String,
        type: ChannelType.values.firstWhere(
          (value) => value.name == typeName,
          orElse: () => ChannelType.serverText,
        ),
        serverId: serverId,
        memberIds: channelMembers[channelId] ?? const [],
      );

      channels[channelId] = channel;

      if (serverId != null) {
        serverChannelIds.putIfAbsent(serverId, () => []).add(channelId);
      }
    }

    for (final entry in servers.entries.toList()) {
      final members = serverMembers[entry.key] ?? const <String>[];
      final channelIds = serverChannelIds[entry.key] ?? const <String>[];
      servers[entry.key] = entry.value.copyWith(
        memberIds: List<String>.from(members),
        channelIds: List<String>.from(channelIds),
      );
    }

    final messagesByChannel = <String, List<ChatMessage>>{};
    for (final channelId in channels.keys) {
      messagesByChannel[channelId] = [];
    }

    for (final row in _db.select(
      'SELECT id, channel_id, author_id, type, text, image_url, image_expires_at, '
      'created_at, edited_at, is_deleted '
      'FROM messages ORDER BY created_at ASC, rowid;',
    )) {
      final channelId = row['channel_id'] as String;
      final typeName = row['type'] as String;

      final message = ChatMessage(
        id: row['id'] as String,
        channelId: channelId,
        authorId: row['author_id'] as String,
        type: MessageType.values.firstWhere(
          (value) => value.name == typeName,
          orElse: () => MessageType.text,
        ),
        text: row['text'] as String?,
        imageUrl: row['image_url'] as String?,
        imageExpiresAt: _fromEpochMillis(row['image_expires_at'] as int?),
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
        editedAt: _fromEpochMillis(row['edited_at'] as int?),
        isDeleted: (row['is_deleted'] as int) == 1,
      );

      messagesByChannel.putIfAbsent(channelId, () => []).add(message);
    }

    final settingsRows = _db.select(
      'SELECT display_name, custom_status, presence, allow_direct_messages '
      'FROM user_settings WHERE id = 1;',
    );

    final userSettings = settingsRows.isEmpty
        ? const UserSettings(
            displayName: 'User',
            customStatus: '',
            presence: UserPresence.online,
            allowDirectMessages: true,
          )
        : UserSettings(
            displayName: settingsRows.first['display_name'] as String,
            customStatus: settingsRows.first['custom_status'] as String,
            presence: UserPresence.values[
                (settingsRows.first['presence'] as int)
                    .clamp(0, UserPresence.values.length - 1)],
            allowDirectMessages:
                (settingsRows.first['allow_direct_messages'] as int) == 1,
          );

    final selectedServerId = _metaValue('selected_server_id');
    final selectedChannelId = _metaValue('selected_channel_id');

    final fallbackServerId = servers.keys.isNotEmpty ? servers.keys.first : '';
    final effectiveServerId = servers.containsKey(selectedServerId)
        ? selectedServerId
        : fallbackServerId;

    String fallbackChannelId = '';
    if (effectiveServerId.isNotEmpty && servers[effectiveServerId] != null) {
      final ids = servers[effectiveServerId]!.channelIds;
      if (ids.isNotEmpty) {
        fallbackChannelId = ids.first;
      }
    }
    if (fallbackChannelId.isEmpty && channels.isNotEmpty) {
      fallbackChannelId = channels.keys.first;
    }

    final effectiveChannelId = channels.containsKey(selectedChannelId)
        ? selectedChannelId
        : fallbackChannelId;

    final currentUserId = users.keys.isNotEmpty ? users.keys.first : 'u_me';

    return ConcordState(
      currentUserId: currentUserId,
      users: users,
      friends: friends,
      servers: servers,
      channels: channels,
      messagesByChannel: messagesByChannel,
      selectedServerId: effectiveServerId,
      selectedChannelId: effectiveChannelId,
      userSettings: userSettings,
    );
  }

  String _metaValue(String key) {
    final rows = _db.select('SELECT value FROM app_meta WHERE key = ?;', [key]);
    if (rows.isEmpty) {
      return '';
    }

    return rows.first['value'] as String;
  }

  int _channelSortOrder(Channel channel, ConcordState state) {
    if (channel.serverId == null) {
      return 0;
    }

    final server = state.servers[channel.serverId!];
    if (server == null) {
      return 0;
    }

    final index = server.channelIds.indexOf(channel.id);
    return index < 0 ? 0 : index;
  }

  int? _toEpochMillis(DateTime? dateTime) {
    return dateTime?.millisecondsSinceEpoch;
  }

  DateTime? _fromEpochMillis(int? value) {
    if (value == null) {
      return null;
    }

    return DateTime.fromMillisecondsSinceEpoch(value);
  }
}
