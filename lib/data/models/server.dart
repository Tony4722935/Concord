class Server {
  const Server({
    required this.id,
    required this.name,
    required this.icon,
    required this.memberIds,
    required this.channelIds,
  });

  final String id;
  final String name;
  final String icon;
  final List<String> memberIds;
  final List<String> channelIds;

  Server copyWith({
    String? name,
    String? icon,
    List<String>? memberIds,
    List<String>? channelIds,
  }) {
    return Server(
      id: id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      memberIds: memberIds ?? this.memberIds,
      channelIds: channelIds ?? this.channelIds,
    );
  }
}
