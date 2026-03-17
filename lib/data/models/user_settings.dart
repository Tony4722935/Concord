enum UserPresence {
  online,
  idle,
  doNotDisturb,
  invisible,
}

class UserSettings {
  const UserSettings({
    required this.displayName,
    required this.customStatus,
    required this.presence,
    required this.allowDirectMessages,
  });

  final String displayName;
  final String customStatus;
  final UserPresence presence;
  final bool allowDirectMessages;

  UserSettings copyWith({
    String? displayName,
    String? customStatus,
    UserPresence? presence,
    bool? allowDirectMessages,
  }) {
    return UserSettings(
      displayName: displayName ?? this.displayName,
      customStatus: customStatus ?? this.customStatus,
      presence: presence ?? this.presence,
      allowDirectMessages: allowDirectMessages ?? this.allowDirectMessages,
    );
  }
}
