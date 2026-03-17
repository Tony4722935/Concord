enum ChannelType {
  dm,
  serverText,
}

class Channel {
  const Channel({
    required this.id,
    required this.name,
    required this.type,
    this.serverId,
    required this.memberIds,
  });

  final String id;
  final String name;
  final ChannelType type;
  final String? serverId;
  final List<String> memberIds;
}
