import 'package:concord/data/models/channel.dart';
import 'package:concord/data/models/chat_message.dart';
import 'package:concord/data/models/concord_user.dart';
import 'package:concord/data/models/friend.dart';
import 'package:concord/data/models/server.dart';
import 'package:concord/data/models/user_settings.dart';

class ConcordState {
  const ConcordState({
    required this.currentUserId,
    required this.users,
    required this.friends,
    required this.servers,
    required this.channels,
    required this.messagesByChannel,
    required this.selectedServerId,
    required this.selectedChannelId,
    required this.userSettings,
  });

  final String currentUserId;
  final Map<String, ConcordUser> users;
  final List<Friend> friends;
  final Map<String, Server> servers;
  final Map<String, Channel> channels;
  final Map<String, List<ChatMessage>> messagesByChannel;
  final String selectedServerId;
  final String selectedChannelId;
  final UserSettings userSettings;

  ConcordState copyWith({
    String? currentUserId,
    Map<String, ConcordUser>? users,
    List<Friend>? friends,
    Map<String, Server>? servers,
    Map<String, Channel>? channels,
    Map<String, List<ChatMessage>>? messagesByChannel,
    String? selectedServerId,
    String? selectedChannelId,
    UserSettings? userSettings,
  }) {
    return ConcordState(
      currentUserId: currentUserId ?? this.currentUserId,
      users: users ?? this.users,
      friends: friends ?? this.friends,
      servers: servers ?? this.servers,
      channels: channels ?? this.channels,
      messagesByChannel: messagesByChannel ?? this.messagesByChannel,
      selectedServerId: selectedServerId ?? this.selectedServerId,
      selectedChannelId: selectedChannelId ?? this.selectedChannelId,
      userSettings: userSettings ?? this.userSettings,
    );
  }

  ConcordUser? get currentUser => users[currentUserId];

  List<Channel> get channelsForSelectedServer {
    final server = servers[selectedServerId];
    if (server == null) {
      return const [];
    }

    return server.channelIds
        .map((channelId) => channels[channelId])
        .whereType<Channel>()
        .toList(growable: false);
  }

  static ConcordState seed() {
    final now = DateTime.now();

    const me = ConcordUser(
      id: 'u_me',
      username: 'tony',
      avatarUrl: 'https://api.dicebear.com/8.x/bottts/png?seed=tony',
    );

    const alice = ConcordUser(
      id: 'u_alice',
      username: 'alice',
      avatarUrl: 'https://api.dicebear.com/8.x/bottts/png?seed=alice',
    );

    const bob = ConcordUser(
      id: 'u_bob',
      username: 'bob',
      avatarUrl: 'https://api.dicebear.com/8.x/bottts/png?seed=bob',
    );

    const dmWithAlice = Channel(
      id: 'dm_alice',
      name: 'alice',
      type: ChannelType.dm,
      memberIds: ['u_me', 'u_alice'],
    );

    const general = Channel(
      id: 'ch_general',
      name: 'general',
      type: ChannelType.serverText,
      serverId: 's_flutter',
      memberIds: ['u_me', 'u_alice', 'u_bob'],
    );

    const product = Channel(
      id: 'ch_product',
      name: 'product',
      type: ChannelType.serverText,
      serverId: 's_flutter',
      memberIds: ['u_me', 'u_alice', 'u_bob'],
    );

    const flutterServer = Server(
      id: 's_flutter',
      name: 'Flutter Guild',
      icon: 'FG',
      memberIds: ['u_me', 'u_alice', 'u_bob'],
      channelIds: ['ch_general', 'ch_product'],
    );

    return ConcordState(
      currentUserId: me.id,
      users: {
        me.id: me,
        alice.id: alice,
        bob.id: bob,
      },
      friends: const [
        Friend(userId: 'u_alice', isOnline: true, note: 'Pairing today'),
        Friend(userId: 'u_bob', isOnline: false, note: 'Away'),
      ],
      servers: {
        flutterServer.id: flutterServer,
      },
      channels: {
        dmWithAlice.id: dmWithAlice,
        general.id: general,
        product.id: product,
      },
      messagesByChannel: {
        dmWithAlice.id: [
          ChatMessage(
            id: 'm1',
            channelId: dmWithAlice.id,
            authorId: alice.id,
            type: MessageType.text,
            text: 'Ready to work on Concord?',
            createdAt: now.subtract(const Duration(minutes: 34)),
          ),
        ],
        general.id: [
          ChatMessage(
            id: 'm2',
            channelId: general.id,
            authorId: bob.id,
            type: MessageType.text,
            text: 'Server is up.',
            createdAt: now.subtract(const Duration(minutes: 20)),
          ),
          ChatMessage(
            id: 'm3',
            channelId: general.id,
            authorId: me.id,
            type: MessageType.text,
            text: 'Let us ship MVP first.',
            createdAt: now.subtract(const Duration(minutes: 15)),
          ),
        ],
        product.id: [
          ChatMessage(
            id: 'm4',
            channelId: product.id,
            authorId: me.id,
            type: MessageType.system,
            text: 'Voice chat is scheduled for phase 2.',
            createdAt: now.subtract(const Duration(minutes: 10)),
          ),
        ],
      },
      selectedServerId: flutterServer.id,
      selectedChannelId: general.id,
      userSettings: const UserSettings(
        displayName: 'tony',
        customStatus: 'Building Concord',
        presence: UserPresence.online,
        allowDirectMessages: true,
      ),
    );
  }
}
