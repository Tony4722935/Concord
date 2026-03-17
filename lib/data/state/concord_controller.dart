import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:concord/data/db/concord_database.dart';
import 'package:concord/data/models/channel.dart';
import 'package:concord/data/models/chat_message.dart';
import 'package:concord/data/models/concord_user.dart';
import 'package:concord/data/models/friend.dart';
import 'package:concord/data/models/server.dart';
import 'package:concord/data/models/user_settings.dart';
import 'package:concord/data/state/concord_state.dart';
import 'package:concord/data/state/retention_policy.dart';

final concordDatabaseProvider = Provider<ConcordDatabase?>((ref) => null);

final concordControllerProvider =
    StateNotifierProvider<ConcordController, ConcordState>((ref) {
  final database = ref.watch(concordDatabaseProvider);
  return ConcordController(database: database);
});

enum AddFriendResult {
  added,
  alreadyFriends,
  invalidUsername,
  cannotAddYourself,
}

class ConcordController extends StateNotifier<ConcordState> {
  ConcordController({ConcordDatabase? database})
      : _database = database,
        _uuid = const Uuid(),
        _retentionPolicy = const RetentionPolicy(),
        super(ConcordState.seed()) {
    final database = _database;
    if (database != null) {
      state = database.loadOrSeedState();
    }
    runRetentionSweep();
    addListener(_persistState, fireImmediately: false);
  }

  final ConcordDatabase? _database;
  final Uuid _uuid;
  final RetentionPolicy _retentionPolicy;

  void runRetentionSweep() {
    final enforced =
        _retentionPolicy.enforce(state.messagesByChannel, DateTime.now());
    if (_isEquivalentMessages(state.messagesByChannel, enforced)) {
      return;
    }

    state = state.copyWith(messagesByChannel: enforced);
  }

  void selectServer(String serverId) {
    final server = state.servers[serverId];
    if (server == null || server.channelIds.isEmpty) {
      return;
    }

    state = state.copyWith(
      selectedServerId: serverId,
      selectedChannelId: server.channelIds.first,
    );
  }

  void selectChannel(String channelId) {
    if (!state.channels.containsKey(channelId)) {
      return;
    }

    state = state.copyWith(selectedChannelId: channelId);
  }

  AddFriendResult addFriendByUsername(String rawUsername) {
    final normalized = rawUsername.trim();
    if (normalized.isEmpty) {
      return AddFriendResult.invalidUsername;
    }

    final me = state.currentUser;
    if (me == null) {
      return AddFriendResult.invalidUsername;
    }

    if (normalized.toLowerCase() == me.username.toLowerCase()) {
      return AddFriendResult.cannotAddYourself;
    }

    final users = Map<String, ConcordUser>.from(state.users);
    ConcordUser? target;

    for (final user in users.values) {
      if (user.username.toLowerCase() == normalized.toLowerCase()) {
        target = user;
        break;
      }
    }

    if (target == null) {
      target = ConcordUser(
        id: 'u_${_uuid.v4()}',
        username: normalized,
        avatarUrl: 'https://api.dicebear.com/8.x/bottts/png?seed=$normalized',
      );
      users[target.id] = target;
    }

    final exists = state.friends.any((friend) => friend.userId == target!.id);
    if (exists) {
      return AddFriendResult.alreadyFriends;
    }

    final friends = List<Friend>.from(state.friends)
      ..add(
        Friend(
          userId: target.id,
          isOnline: false,
          note: 'Recently added',
        ),
      );

    state = state.copyWith(users: users, friends: friends);
    return AddFriendResult.added;
  }

  String? createServer({
    required String name,
    required String firstChannelName,
  }) {
    final serverName = name.trim();
    final channelName = firstChannelName.trim().toLowerCase();
    if (serverName.isEmpty || channelName.isEmpty) {
      return null;
    }

    final serverId = 's_${_uuid.v4()}';
    final channelId = 'ch_${_uuid.v4()}';

    final iconSeed = serverName
        .split(' ')
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part.substring(0, 1).toUpperCase())
        .join();

    final server = Server(
      id: serverId,
      name: serverName,
      icon: iconSeed.isEmpty ? 'SV' : iconSeed,
      memberIds: [state.currentUserId],
      channelIds: [channelId],
    );

    final channel = Channel(
      id: channelId,
      name: channelName,
      type: ChannelType.serverText,
      serverId: serverId,
      memberIds: [state.currentUserId],
    );

    final servers = Map<String, Server>.from(state.servers)
      ..[server.id] = server;
    final channels = Map<String, Channel>.from(state.channels)
      ..[channel.id] = channel;
    final messages =
        Map<String, List<ChatMessage>>.from(state.messagesByChannel)
          ..[channel.id] = [
            ChatMessage(
              id: _uuid.v4(),
              channelId: channel.id,
              authorId: state.currentUserId,
              type: MessageType.system,
              text: 'Server created. Welcome to $serverName.',
              createdAt: DateTime.now(),
            ),
          ];

    state = state.copyWith(
      servers: servers,
      channels: channels,
      messagesByChannel: messages,
      selectedServerId: server.id,
      selectedChannelId: channel.id,
    );

    return server.id;
  }

  String? addServerChannel({
    required String serverId,
    required String channelName,
  }) {
    final server = state.servers[serverId];
    final normalized = channelName.trim().toLowerCase();
    if (server == null || normalized.isEmpty) {
      return null;
    }

    final duplicate = server.channelIds
        .map((id) => state.channels[id])
        .whereType<Channel>()
        .any((channel) => channel.name == normalized);
    if (duplicate) {
      return null;
    }

    final channel = Channel(
      id: 'ch_${_uuid.v4()}',
      name: normalized,
      type: ChannelType.serverText,
      serverId: serverId,
      memberIds: server.memberIds,
    );

    final channels = Map<String, Channel>.from(state.channels)
      ..[channel.id] = channel;

    final updatedServer = server.copyWith(
      channelIds: List<String>.from(server.channelIds)..add(channel.id),
    );

    final servers = Map<String, Server>.from(state.servers)
      ..[serverId] = updatedServer;

    final messages =
        Map<String, List<ChatMessage>>.from(state.messagesByChannel)
          ..[channel.id] = [];

    state = state.copyWith(
      channels: channels,
      servers: servers,
      messagesByChannel: messages,
      selectedChannelId: channel.id,
      selectedServerId: serverId,
    );

    return channel.id;
  }

  void updateServerSettings({
    required String serverId,
    required String name,
    required String icon,
  }) {
    final server = state.servers[serverId];
    if (server == null) {
      return;
    }

    final nextName = name.trim();
    final nextIcon = icon.trim().toUpperCase();
    if (nextName.isEmpty || nextIcon.isEmpty) {
      return;
    }

    final servers = Map<String, Server>.from(state.servers)
      ..[serverId] = server.copyWith(name: nextName, icon: nextIcon);

    state = state.copyWith(servers: servers);
  }

  void updateUserSettings({
    required String displayName,
    required String customStatus,
    required UserPresence presence,
    required bool allowDirectMessages,
  }) {
    final nextDisplayName = displayName.trim();
    if (nextDisplayName.isEmpty) {
      return;
    }

    state = state.copyWith(
      userSettings: state.userSettings.copyWith(
        displayName: nextDisplayName,
        customStatus: customStatus.trim(),
        presence: presence,
        allowDirectMessages: allowDirectMessages,
      ),
    );
  }

  void openDirectMessage(String friendUserId) {
    final me = state.currentUserId;
    final existing = state.channels.values.where(
      (channel) {
        final members = channel.memberIds;
        return channel.type == ChannelType.dm &&
            members.length == 2 &&
            members.contains(me) &&
            members.contains(friendUserId);
      },
    );

    if (existing.isNotEmpty) {
      state = state.copyWith(selectedChannelId: existing.first.id);
      return;
    }

    final friend = state.users[friendUserId];
    if (friend == null) {
      return;
    }

    final channel = Channel(
      id: 'dm_${_uuid.v4()}',
      name: friend.username,
      type: ChannelType.dm,
      memberIds: [me, friendUserId],
    );

    final updatedChannels = Map<String, Channel>.from(state.channels)
      ..[channel.id] = channel;

    final updatedMessages = Map<String, List<ChatMessage>>.from(
      state.messagesByChannel,
    )..[channel.id] = [];

    state = state.copyWith(
      channels: updatedChannels,
      messagesByChannel: updatedMessages,
      selectedChannelId: channel.id,
    );
  }

  void sendTextMessage(String channelId, String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      return;
    }

    final message = ChatMessage(
      id: _uuid.v4(),
      channelId: channelId,
      authorId: state.currentUserId,
      type: MessageType.text,
      text: trimmed,
      createdAt: DateTime.now(),
    );

    _pushMessage(channelId, message);
  }

  void sendImageMessage(String channelId, String imageUrl) {
    final trimmed = imageUrl.trim();
    if (trimmed.isEmpty) {
      return;
    }

    final now = DateTime.now();
    final message = ChatMessage(
      id: _uuid.v4(),
      channelId: channelId,
      authorId: state.currentUserId,
      type: MessageType.image,
      imageUrl: trimmed,
      text: 'Image',
      createdAt: now,
      imageExpiresAt: now.add(RetentionPolicy.uploadRetention),
    );

    _pushMessage(channelId, message);
  }

  void editOwnMessage({
    required String channelId,
    required String messageId,
    required String nextText,
  }) {
    final messages = state.messagesByChannel[channelId];
    if (messages == null) {
      return;
    }

    final trimmed = nextText.trim();
    if (trimmed.isEmpty) {
      return;
    }

    final updated = messages.map((message) {
      final isOwner = message.authorId == state.currentUserId;
      final isTarget = message.id == messageId;
      if (!isTarget || !isOwner || !message.hasEditableText) {
        return message;
      }

      return message.copyWith(
        text: trimmed,
        editedAt: DateTime.now(),
      );
    }).toList(growable: false);

    final all = Map<String, List<ChatMessage>>.from(state.messagesByChannel)
      ..[channelId] = updated;

    state = state.copyWith(messagesByChannel: all);
  }

  void deleteOwnMessage({
    required String channelId,
    required String messageId,
  }) {
    final messages = state.messagesByChannel[channelId];
    if (messages == null) {
      return;
    }

    final updated = messages.where((message) {
      final isTarget = message.id == messageId;
      if (!isTarget) {
        return true;
      }

      return message.authorId != state.currentUserId;
    }).toList(growable: false);

    final all = Map<String, List<ChatMessage>>.from(state.messagesByChannel)
      ..[channelId] = updated;

    state = state.copyWith(messagesByChannel: all);
  }

  void _pushMessage(String channelId, ChatMessage message) {
    final current =
        List<ChatMessage>.from(state.messagesByChannel[channelId] ?? []);
    current.add(message);

    final all = Map<String, List<ChatMessage>>.from(state.messagesByChannel)
      ..[channelId] = current;

    state = state.copyWith(messagesByChannel: all);
    runRetentionSweep();
  }

  bool _isEquivalentMessages(
    Map<String, List<ChatMessage>> left,
    Map<String, List<ChatMessage>> right,
  ) {
    if (left.length != right.length) {
      return false;
    }

    for (final entry in left.entries) {
      final next = right[entry.key];
      if (next == null || next.length != entry.value.length) {
        return false;
      }

      for (var i = 0; i < entry.value.length; i++) {
        final a = entry.value[i];
        final b = next[i];
        if (a.id != b.id ||
            a.text != b.text ||
            a.imageUrl != b.imageUrl ||
            a.editedAt != b.editedAt ||
            a.imageExpiresAt != b.imageExpiresAt) {
          return false;
        }
      }
    }

    return true;
  }

  void _persistState(ConcordState next) {
    final database = _database;
    if (database == null) {
      return;
    }

    database.saveState(next);
  }
}
