import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() =>
      'ApiException(statusCode: $statusCode, message: $message)';
}

class ApiAuthSession {
  const ApiAuthSession({
    required this.userId,
    required this.handle,
    required this.isPlatformAdmin,
    required this.accessToken,
    required this.refreshToken,
  });

  final String userId;
  final String handle;
  final bool isPlatformAdmin;
  final String accessToken;
  final String refreshToken;
}

class ApiServerSummary {
  const ApiServerSummary({
    required this.id,
    required this.name,
    required this.ownerUserId,
    required this.iconUrl,
  });

  final String id;
  final String name;
  final String ownerUserId;
  final String? iconUrl;
}

class ApiChannelSummary {
  const ApiChannelSummary({
    required this.id,
    required this.serverId,
    required this.name,
    required this.kind,
    required this.position,
  });

  final String id;
  final String serverId;
  final String name;
  final String kind;
  final int position;
}

class ApiUserSummary {
  const ApiUserSummary({
    required this.id,
    required this.handle,
    required this.username,
    required this.displayName,
    required this.avatarUrl,
    required this.isPlatformAdmin,
  });

  final String id;
  final String handle;
  final String username;
  final String? displayName;
  final String? avatarUrl;
  final bool isPlatformAdmin;
}

class ApiChatMessage {
  const ApiChatMessage({
    required this.messageId,
    required this.channelId,
    required this.authorUserId,
    required this.content,
    required this.imageUrl,
    required this.createdAt,
    required this.editedAt,
    required this.deletedAt,
  });

  final String messageId;
  final String channelId;
  final String authorUserId;
  final String? content;
  final String? imageUrl;
  final DateTime createdAt;
  final DateTime? editedAt;
  final DateTime? deletedAt;
}

class ApiAuditLogEntry {
  const ApiAuditLogEntry({
    required this.logId,
    required this.action,
    required this.actorUserId,
    required this.actorHandle,
    required this.targetUserId,
    required this.targetHandle,
    required this.targetChannelId,
    required this.details,
    required this.createdAt,
  });

  final int logId;
  final String action;
  final String actorUserId;
  final String? actorHandle;
  final String? targetUserId;
  final String? targetHandle;
  final String? targetChannelId;
  final Map<String, dynamic>? details;
  final DateTime createdAt;
}

class ApiAuditLogPage {
  const ApiAuditLogPage({
    required this.items,
    required this.nextCursor,
  });

  final List<ApiAuditLogEntry> items;
  final int? nextCursor;
}

class ApiCurrentUser {
  const ApiCurrentUser({
    required this.id,
    required this.handle,
    required this.username,
    required this.displayName,
    required this.avatarUrl,
    required this.themePreference,
    required this.language,
    required this.timeFormat,
    required this.compactMode,
    required this.showMessageTimestamps,
    required this.isPlatformAdmin,
  });

  final String id;
  final String handle;
  final String username;
  final String? displayName;
  final String? avatarUrl;
  final String themePreference;
  final String language;
  final String timeFormat;
  final bool compactMode;
  final bool showMessageTimestamps;
  final bool isPlatformAdmin;
}

class ApiDirectMessageChannel {
  const ApiDirectMessageChannel({
    required this.channelId,
    required this.peerUserId,
    required this.peerHandle,
    required this.peerDisplayName,
    required this.peerAvatarUrl,
  });

  final String channelId;
  final String peerUserId;
  final String peerHandle;
  final String? peerDisplayName;
  final String? peerAvatarUrl;
}

class ApiVoiceState {
  const ApiVoiceState({
    required this.userId,
    required this.channelId,
    required this.handle,
    required this.displayName,
    required this.avatarUrl,
    required this.muted,
    required this.deafened,
    required this.joinedAt,
  });

  final String userId;
  final String channelId;
  final String handle;
  final String? displayName;
  final String? avatarUrl;
  final bool muted;
  final bool deafened;
  final DateTime joinedAt;
}

class ApiServerMember {
  const ApiServerMember({
    required this.userId,
    required this.handle,
    required this.username,
    required this.displayName,
    required this.avatarUrl,
    required this.role,
    required this.joinedAt,
  });

  final String userId;
  final String handle;
  final String username;
  final String? displayName;
  final String? avatarUrl;
  final String role;
  final DateTime joinedAt;
}

class ApiServerOnlineMembers {
  const ApiServerOnlineMembers({
    required this.totalCount,
    required this.onlineCount,
    required this.onlineUserIds,
  });

  final int totalCount;
  final int onlineCount;
  final List<String> onlineUserIds;
}

class ApiServerBan {
  const ApiServerBan({
    required this.userId,
    required this.userHandle,
    required this.userDisplayName,
    required this.bannedByUserId,
    required this.reason,
    required this.createdAt,
  });

  final String userId;
  final String userHandle;
  final String? userDisplayName;
  final String bannedByUserId;
  final String? reason;
  final DateTime createdAt;
}

class ApiServerInvite {
  const ApiServerInvite({
    required this.code,
    required this.serverId,
    required this.createdByUserId,
    required this.maxUses,
    required this.useCount,
    required this.expiresAt,
    required this.revokedAt,
    required this.createdAt,
  });

  final String code;
  final String serverId;
  final String createdByUserId;
  final int? maxUses;
  final int useCount;
  final DateTime? expiresAt;
  final DateTime? revokedAt;
  final DateTime createdAt;
}

class ApiImageUploadPrepare {
  const ApiImageUploadPrepare({
    required this.uploadUrl,
    required this.imageUrl,
    required this.imageObjectKey,
    required this.expiresInSeconds,
    required this.requiredHeaders,
  });

  final String uploadUrl;
  final String imageUrl;
  final String imageObjectKey;
  final int expiresInSeconds;
  final Map<String, String> requiredHeaders;
}

class ApiImageUploadResult {
  const ApiImageUploadResult({
    required this.imageUrl,
    required this.imageObjectKey,
  });

  final String imageUrl;
  final String imageObjectKey;
}

class ConcordApiClient {
  ConcordApiClient({
    required String baseUrl,
    HttpClient? httpClient,
  })  : _baseUrl = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl,
        _httpClient = httpClient ?? HttpClient();

  final String _baseUrl;
  final HttpClient _httpClient;

  Future<ApiAuthSession> login({
    required String identifier,
    required String password,
  }) async {
    final response = await _request(
      method: 'POST',
      path: '/v1/auth/login',
      jsonBody: {
        'identifier': identifier,
        'password': password,
      },
    );
    final body = _asMap(response.body);
    final user = _asMap(body['user']);
    final tokens = _asMap(body['tokens']);

    return ApiAuthSession(
      userId: _asString(user['id']),
      handle: _asString(user['handle']),
      isPlatformAdmin: _asBool(user['is_platform_admin']),
      accessToken: _asString(tokens['access_token']),
      refreshToken: _asString(tokens['refresh_token']),
    );
  }

  Future<ApiAuthSession> register({
    required String username,
    required String password,
    String? displayName,
    int? preferredTag,
  }) async {
    final payload = <String, dynamic>{
      'username': username,
      'password': password,
    };
    final trimmedDisplayName = displayName?.trim();
    if (trimmedDisplayName != null && trimmedDisplayName.isNotEmpty) {
      payload['display_name'] = trimmedDisplayName;
    }
    if (preferredTag != null) {
      payload['preferred_tag'] = preferredTag;
    }

    final response = await _request(
      method: 'POST',
      path: '/v1/auth/register',
      jsonBody: payload,
    );
    final body = _asMap(response.body);
    final user = _asMap(body['user']);
    final tokens = _asMap(body['tokens']);

    return ApiAuthSession(
      userId: _asString(user['id']),
      handle: _asString(user['handle']),
      isPlatformAdmin: _asBool(user['is_platform_admin']),
      accessToken: _asString(tokens['access_token']),
      refreshToken: _asString(tokens['refresh_token']),
    );
  }

  Future<List<ApiServerSummary>> listServers({
    required String accessToken,
  }) async {
    final response = await _request(
      method: 'GET',
      path: '/v1/servers',
      accessToken: accessToken,
    );
    final body = _asList(response.body);
    return body
        .map((raw) => _asMap(raw))
        .map(
          (server) => ApiServerSummary(
            id: _asString(server['id']),
            name: _asString(server['name']),
            ownerUserId: _asString(server['owner_user_id']),
            iconUrl: _asNullableString(server['icon_url']),
          ),
        )
        .toList(growable: false);
  }

  Future<ApiServerSummary> createServer({
    required String accessToken,
    required String name,
  }) async {
    final response = await _request(
      method: 'POST',
      path: '/v1/servers',
      accessToken: accessToken,
      jsonBody: {
        'name': name,
      },
    );
    final server = _asMap(response.body);
    return ApiServerSummary(
      id: _asString(server['id']),
      name: _asString(server['name']),
      ownerUserId: _asString(server['owner_user_id']),
      iconUrl: _asNullableString(server['icon_url']),
    );
  }

  Future<ApiServerSummary> joinServerByInvite({
    required String accessToken,
    required String code,
  }) async {
    final response = await _request(
      method: 'POST',
      path: '/v1/servers/join-by-invite',
      accessToken: accessToken,
      jsonBody: {
        'code': code.trim(),
      },
    );
    final server = _asMap(response.body);
    return ApiServerSummary(
      id: _asString(server['id']),
      name: _asString(server['name']),
      ownerUserId: _asString(server['owner_user_id']),
      iconUrl: _asNullableString(server['icon_url']),
    );
  }

  Future<ApiServerSummary> updateServer({
    required String accessToken,
    required String serverId,
    required String name,
  }) async {
    final response = await _request(
      method: 'PATCH',
      path: '/v1/servers/$serverId',
      accessToken: accessToken,
      jsonBody: {
        'name': name.trim(),
      },
    );
    final server = _asMap(response.body);
    return ApiServerSummary(
      id: _asString(server['id']),
      name: _asString(server['name']),
      ownerUserId: _asString(server['owner_user_id']),
      iconUrl: _asNullableString(server['icon_url']),
    );
  }

  Future<ApiServerSummary> updateServerIcon({
    required String accessToken,
    required String serverId,
    required String imageUrl,
    required String imageObjectKey,
  }) async {
    final response = await _request(
      method: 'PUT',
      path: '/v1/servers/$serverId/icon',
      accessToken: accessToken,
      jsonBody: {
        'image_url': imageUrl,
        'image_object_key': imageObjectKey,
      },
    );
    final server = _asMap(response.body);
    return ApiServerSummary(
      id: _asString(server['id']),
      name: _asString(server['name']),
      ownerUserId: _asString(server['owner_user_id']),
      iconUrl: _asNullableString(server['icon_url']),
    );
  }

  Future<ApiServerSummary> clearServerIcon({
    required String accessToken,
    required String serverId,
  }) async {
    final response = await _request(
      method: 'DELETE',
      path: '/v1/servers/$serverId/icon',
      accessToken: accessToken,
    );
    final server = _asMap(response.body);
    return ApiServerSummary(
      id: _asString(server['id']),
      name: _asString(server['name']),
      ownerUserId: _asString(server['owner_user_id']),
      iconUrl: _asNullableString(server['icon_url']),
    );
  }

  Future<void> deleteServer({
    required String accessToken,
    required String serverId,
  }) async {
    await _request(
      method: 'DELETE',
      path: '/v1/servers/$serverId',
      accessToken: accessToken,
    );
  }

  Future<List<ApiUserSummary>> listAllUsers({
    required String accessToken,
    int limit = 500,
    int offset = 0,
  }) async {
    final response = await _request(
      method: 'GET',
      path: '/v1/users',
      accessToken: accessToken,
      query: {
        'limit': '$limit',
        'offset': '$offset',
      },
    );
    final body = _asList(response.body);
    return body
        .map((raw) => _asMap(raw))
        .map(
          (user) => ApiUserSummary(
            id: _asString(user['id']),
            handle: _asString(user['handle']),
            username: _asString(user['username']),
            displayName: _asNullableString(user['display_name']),
            avatarUrl: _asNullableString(user['avatar_url']),
            isPlatformAdmin: _asBool(user['is_platform_admin']),
          ),
        )
        .toList(growable: false);
  }

  Future<List<ApiUserSummary>> listFriends({
    required String accessToken,
  }) async {
    final response = await _request(
      method: 'GET',
      path: '/v1/friends',
      accessToken: accessToken,
    );
    final body = _asList(response.body);
    return body
        .map((raw) => _asMap(raw))
        .map(
          (friend) => ApiUserSummary(
            id: _asString(friend['user_id']),
            handle: _asString(friend['handle']),
            username: _asString(friend['username']),
            displayName: _asNullableString(friend['display_name']),
            avatarUrl: _asNullableString(friend['avatar_url']),
            isPlatformAdmin: false,
          ),
        )
        .toList(growable: false);
  }

  Future<ApiUserSummary> addFriend({
    required String accessToken,
    required String handle,
  }) async {
    final response = await _request(
      method: 'POST',
      path: '/v1/friends/add',
      accessToken: accessToken,
      jsonBody: {
        'handle': handle,
      },
    );
    final friend = _asMap(response.body);
    return ApiUserSummary(
      id: _asString(friend['user_id']),
      handle: _asString(friend['handle']),
      username: _asString(friend['username']),
      displayName: _asNullableString(friend['display_name']),
      avatarUrl: _asNullableString(friend['avatar_url']),
      isPlatformAdmin: false,
    );
  }

  Future<ApiCurrentUser> getMe({
    required String accessToken,
  }) async {
    final response = await _request(
      method: 'GET',
      path: '/v1/auth/me',
      accessToken: accessToken,
    );
    final user = _asMap(response.body);
    return ApiCurrentUser(
      id: _asString(user['id']),
      handle: _asString(user['handle']),
      username: _asString(user['username']),
      displayName: _asNullableString(user['display_name']),
      avatarUrl: _asNullableString(user['avatar_url']),
      themePreference: _normalizeThemePreference(user['theme_preference']),
      language: _normalizeLanguage(user['language']),
      timeFormat: _normalizeTimeFormat(user['time_format']),
      compactMode: _asBoolOrDefault(user['compact_mode'], false),
      showMessageTimestamps:
          _asBoolOrDefault(user['show_message_timestamps'], true),
      isPlatformAdmin: _asBool(user['is_platform_admin']),
    );
  }

  Future<ApiCurrentUser> updateMe({
    required String accessToken,
    String? username,
    String? displayName,
    String? currentPassword,
    String? newPassword,
    String? themePreference,
    String? language,
    String? timeFormat,
    bool? compactMode,
    bool? showMessageTimestamps,
  }) async {
    final payload = <String, dynamic>{};
    final trimmedUsername = username?.trim();
    final trimmedDisplayName = displayName?.trim();
    final trimmedCurrentPassword = currentPassword?.trim();
    final trimmedNewPassword = newPassword?.trim();

    if (trimmedUsername != null && trimmedUsername.isNotEmpty) {
      payload['username'] = trimmedUsername;
    }
    if (displayName != null) {
      payload['display_name'] =
          (trimmedDisplayName == null || trimmedDisplayName.isEmpty)
              ? null
              : trimmedDisplayName;
    }
    if (trimmedNewPassword != null && trimmedNewPassword.isNotEmpty) {
      payload['new_password'] = trimmedNewPassword;
      payload['current_password'] = trimmedCurrentPassword ?? '';
    }
    if (themePreference != null && themePreference.trim().isNotEmpty) {
      payload['theme_preference'] = themePreference.trim().toLowerCase();
    }
    if (language != null && language.trim().isNotEmpty) {
      payload['language'] = language.trim();
    }
    if (timeFormat != null && timeFormat.trim().isNotEmpty) {
      payload['time_format'] = timeFormat.trim().toLowerCase();
    }
    if (compactMode != null) {
      payload['compact_mode'] = compactMode;
    }
    if (showMessageTimestamps != null) {
      payload['show_message_timestamps'] = showMessageTimestamps;
    }

    final response = await _request(
      method: 'PATCH',
      path: '/v1/auth/me',
      accessToken: accessToken,
      jsonBody: payload,
    );
    final user = _asMap(response.body);
    return ApiCurrentUser(
      id: _asString(user['id']),
      handle: _asString(user['handle']),
      username: _asString(user['username']),
      displayName: _asNullableString(user['display_name']),
      avatarUrl: _asNullableString(user['avatar_url']),
      themePreference: _normalizeThemePreference(user['theme_preference']),
      language: _normalizeLanguage(user['language']),
      timeFormat: _normalizeTimeFormat(user['time_format']),
      compactMode: _asBoolOrDefault(user['compact_mode'], false),
      showMessageTimestamps:
          _asBoolOrDefault(user['show_message_timestamps'], true),
      isPlatformAdmin: _asBool(user['is_platform_admin']),
    );
  }

  Future<ApiCurrentUser> updateMyAvatar({
    required String accessToken,
    required String imageUrl,
    required String imageObjectKey,
  }) async {
    final response = await _request(
      method: 'PUT',
      path: '/v1/auth/me/avatar',
      accessToken: accessToken,
      jsonBody: {
        'image_url': imageUrl,
        'image_object_key': imageObjectKey,
      },
    );
    final user = _asMap(response.body);
    return ApiCurrentUser(
      id: _asString(user['id']),
      handle: _asString(user['handle']),
      username: _asString(user['username']),
      displayName: _asNullableString(user['display_name']),
      avatarUrl: _asNullableString(user['avatar_url']),
      themePreference: _normalizeThemePreference(user['theme_preference']),
      language: _normalizeLanguage(user['language']),
      timeFormat: _normalizeTimeFormat(user['time_format']),
      compactMode: _asBoolOrDefault(user['compact_mode'], false),
      showMessageTimestamps:
          _asBoolOrDefault(user['show_message_timestamps'], true),
      isPlatformAdmin: _asBool(user['is_platform_admin']),
    );
  }

  Future<ApiCurrentUser> clearMyAvatar({
    required String accessToken,
  }) async {
    final response = await _request(
      method: 'DELETE',
      path: '/v1/auth/me/avatar',
      accessToken: accessToken,
    );
    final user = _asMap(response.body);
    return ApiCurrentUser(
      id: _asString(user['id']),
      handle: _asString(user['handle']),
      username: _asString(user['username']),
      displayName: _asNullableString(user['display_name']),
      avatarUrl: _asNullableString(user['avatar_url']),
      themePreference: _normalizeThemePreference(user['theme_preference']),
      language: _normalizeLanguage(user['language']),
      timeFormat: _normalizeTimeFormat(user['time_format']),
      compactMode: _asBoolOrDefault(user['compact_mode'], false),
      showMessageTimestamps:
          _asBoolOrDefault(user['show_message_timestamps'], true),
      isPlatformAdmin: _asBool(user['is_platform_admin']),
    );
  }

  Future<void> deleteMe({
    required String accessToken,
    required String currentPassword,
  }) async {
    await _request(
      method: 'DELETE',
      path: '/v1/auth/me',
      accessToken: accessToken,
      jsonBody: {
        'current_password': currentPassword.trim(),
      },
    );
  }

  Future<List<ApiChannelSummary>> listServerChannels({
    required String accessToken,
    required String serverId,
  }) async {
    final response = await _request(
      method: 'GET',
      path: '/v1/servers/$serverId/channels',
      accessToken: accessToken,
    );
    final body = _asList(response.body);
    return body
        .map((raw) => _asMap(raw))
        .map(
          (channel) => ApiChannelSummary(
            id: _asString(channel['id']),
            serverId: _asString(channel['server_id']),
            name: _asString(channel['name']),
            kind: _asString(channel['kind']),
            position: _asInt(channel['position']),
          ),
        )
        .toList(growable: false);
  }

  Future<ApiChannelSummary> createServerChannel({
    required String accessToken,
    required String serverId,
    required String name,
    String kind = 'text',
  }) async {
    final response = await _request(
      method: 'POST',
      path: '/v1/servers/$serverId/channels',
      accessToken: accessToken,
      jsonBody: {
        'name': name.trim(),
        'kind': kind,
      },
    );
    final channel = _asMap(response.body);
    return ApiChannelSummary(
      id: _asString(channel['id']),
      serverId: _asString(channel['server_id']),
      name: _asString(channel['name']),
      kind: _asString(channel['kind']),
      position: _asInt(channel['position']),
    );
  }

  Future<void> deleteServerChannel({
    required String accessToken,
    required String serverId,
    required String channelId,
  }) async {
    await _request(
      method: 'DELETE',
      path: '/v1/servers/$serverId/channels/$channelId',
      accessToken: accessToken,
    );
  }

  Future<ApiVoiceState?> getMyVoiceState({
    required String accessToken,
    required String serverId,
  }) async {
    final response = await _request(
      method: 'GET',
      path: '/v1/servers/$serverId/voice/me',
      accessToken: accessToken,
    );
    if (response.body == null) {
      return null;
    }
    final state = _asMap(response.body);
    return ApiVoiceState(
      userId: _asString(state['user_id']),
      channelId: _asString(state['channel_id']),
      handle: _asString(state['handle']),
      displayName: _asNullableString(state['display_name']),
      avatarUrl: _asNullableString(state['avatar_url']),
      muted: _asBoolOrDefault(state['muted'], false),
      deafened: _asBoolOrDefault(state['deafened'], false),
      joinedAt: DateTime.parse(_asString(state['joined_at'])),
    );
  }

  Future<List<ApiVoiceState>> listVoiceStates({
    required String accessToken,
    required String serverId,
    required String channelId,
  }) async {
    final response = await _request(
      method: 'GET',
      path: '/v1/servers/$serverId/channels/$channelId/voice/states',
      accessToken: accessToken,
    );
    final body = _asList(response.body);
    return body
        .map((raw) => _asMap(raw))
        .map(
          (state) => ApiVoiceState(
            userId: _asString(state['user_id']),
            channelId: _asString(state['channel_id']),
            handle: _asString(state['handle']),
            displayName: _asNullableString(state['display_name']),
            avatarUrl: _asNullableString(state['avatar_url']),
            muted: _asBoolOrDefault(state['muted'], false),
            deafened: _asBoolOrDefault(state['deafened'], false),
            joinedAt: DateTime.parse(_asString(state['joined_at'])),
          ),
        )
        .toList(growable: false);
  }

  Future<ApiVoiceState> joinOrUpdateVoiceState({
    required String accessToken,
    required String serverId,
    required String channelId,
    required bool muted,
    required bool deafened,
  }) async {
    final response = await _request(
      method: 'PUT',
      path: '/v1/servers/$serverId/channels/$channelId/voice/state',
      accessToken: accessToken,
      jsonBody: {
        'muted': muted,
        'deafened': deafened,
      },
    );
    final state = _asMap(response.body);
    return ApiVoiceState(
      userId: _asString(state['user_id']),
      channelId: _asString(state['channel_id']),
      handle: _asString(state['handle']),
      displayName: _asNullableString(state['display_name']),
      avatarUrl: _asNullableString(state['avatar_url']),
      muted: _asBoolOrDefault(state['muted'], false),
      deafened: _asBoolOrDefault(state['deafened'], false),
      joinedAt: DateTime.parse(_asString(state['joined_at'])),
    );
  }

  Future<void> leaveVoiceState({
    required String accessToken,
    required String serverId,
    required String channelId,
  }) async {
    await _request(
      method: 'DELETE',
      path: '/v1/servers/$serverId/channels/$channelId/voice/state',
      accessToken: accessToken,
    );
  }

  Future<List<ApiServerMember>> listServerMembers({
    required String accessToken,
    required String serverId,
  }) async {
    final response = await _request(
      method: 'GET',
      path: '/v1/servers/$serverId/members',
      accessToken: accessToken,
    );
    final body = _asList(response.body);
    return body
        .map((raw) => _asMap(raw))
        .map(
          (member) => ApiServerMember(
            userId: _asString(member['user_id']),
            handle: _asString(member['handle']),
            username: _asString(member['username']),
            displayName: _asNullableString(member['display_name']),
            avatarUrl: _asNullableString(member['avatar_url']),
            role: _asString(member['role']),
            joinedAt: DateTime.parse(_asString(member['joined_at'])),
          ),
        )
        .toList(growable: false);
  }

  Future<ApiServerOnlineMembers> listServerOnlineMembers({
    required String accessToken,
    required String serverId,
  }) async {
    final response = await _request(
      method: 'GET',
      path: '/v1/servers/$serverId/members/online',
      accessToken: accessToken,
    );
    final body = _asMap(response.body);
    final rawIds = _asList(body['online_user_ids']);
    return ApiServerOnlineMembers(
      totalCount: _asInt(body['total_count']),
      onlineCount: _asInt(body['online_count']),
      onlineUserIds: rawIds.map((value) => _asString(value)).toList(growable: false),
    );
  }

  Future<ApiServerMember> updateServerMemberRole({
    required String accessToken,
    required String serverId,
    required String memberUserId,
    required String role,
  }) async {
    final response = await _request(
      method: 'PATCH',
      path: '/v1/servers/$serverId/members/$memberUserId/role',
      accessToken: accessToken,
      jsonBody: {'role': role},
    );
    final member = _asMap(response.body);
    return ApiServerMember(
      userId: _asString(member['user_id']),
      handle: _asString(member['handle']),
      username: _asString(member['username']),
      displayName: _asNullableString(member['display_name']),
      avatarUrl: _asNullableString(member['avatar_url']),
      role: _asString(member['role']),
      joinedAt: DateTime.parse(_asString(member['joined_at'])),
    );
  }

  Future<void> kickServerMember({
    required String accessToken,
    required String serverId,
    required String memberUserId,
  }) async {
    await _request(
      method: 'POST',
      path: '/v1/servers/$serverId/members/$memberUserId/kick',
      accessToken: accessToken,
    );
  }

  Future<List<ApiServerBan>> listServerBans({
    required String accessToken,
    required String serverId,
  }) async {
    final response = await _request(
      method: 'GET',
      path: '/v1/servers/$serverId/bans',
      accessToken: accessToken,
    );
    final body = _asList(response.body);
    return body
        .map((raw) => _asMap(raw))
        .map(
          (ban) => ApiServerBan(
            userId: _asString(ban['user_id']),
            userHandle: _asString(ban['user_handle']),
            userDisplayName: _asNullableString(ban['user_display_name']),
            bannedByUserId: _asString(ban['banned_by_user_id']),
            reason: _asNullableString(ban['reason']),
            createdAt: DateTime.parse(_asString(ban['created_at'])),
          ),
        )
        .toList(growable: false);
  }

  Future<ApiServerBan> banServerUser({
    required String accessToken,
    required String serverId,
    required String targetUserId,
    String? reason,
  }) async {
    final response = await _request(
      method: 'POST',
      path: '/v1/servers/$serverId/bans/$targetUserId',
      accessToken: accessToken,
      jsonBody: {
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
    final ban = _asMap(response.body);
    return ApiServerBan(
      userId: _asString(ban['user_id']),
      userHandle: _asString(ban['user_handle']),
      userDisplayName: _asNullableString(ban['user_display_name']),
      bannedByUserId: _asString(ban['banned_by_user_id']),
      reason: _asNullableString(ban['reason']),
      createdAt: DateTime.parse(_asString(ban['created_at'])),
    );
  }

  Future<void> unbanServerUser({
    required String accessToken,
    required String serverId,
    required String targetUserId,
  }) async {
    await _request(
      method: 'DELETE',
      path: '/v1/servers/$serverId/bans/$targetUserId',
      accessToken: accessToken,
    );
  }

  Future<ApiServerInvite> createServerInvite({
    required String accessToken,
    required String serverId,
    int? maxUses,
    int? expiresInHours,
  }) async {
    final response = await _request(
      method: 'POST',
      path: '/v1/servers/$serverId/invites',
      accessToken: accessToken,
      jsonBody: {
        if (maxUses != null) 'max_uses': maxUses,
        if (expiresInHours != null) 'expires_in_hours': expiresInHours,
      },
    );
    final invite = _asMap(response.body);
    return ApiServerInvite(
      code: _asString(invite['code']),
      serverId: _asString(invite['server_id']),
      createdByUserId: _asString(invite['created_by_user_id']),
      maxUses: _asNullableInt(invite['max_uses']),
      useCount: _asInt(invite['use_count']),
      expiresAt: _asNullableDateTime(invite['expires_at']),
      revokedAt: _asNullableDateTime(invite['revoked_at']),
      createdAt: DateTime.parse(_asString(invite['created_at'])),
    );
  }

  Future<List<ApiServerInvite>> listServerInvites({
    required String accessToken,
    required String serverId,
  }) async {
    final response = await _request(
      method: 'GET',
      path: '/v1/servers/$serverId/invites',
      accessToken: accessToken,
    );
    final body = _asList(response.body);
    return body
        .map((raw) => _asMap(raw))
        .map(
          (invite) => ApiServerInvite(
            code: _asString(invite['code']),
            serverId: _asString(invite['server_id']),
            createdByUserId: _asString(invite['created_by_user_id']),
            maxUses: _asNullableInt(invite['max_uses']),
            useCount: _asInt(invite['use_count']),
            expiresAt: _asNullableDateTime(invite['expires_at']),
            revokedAt: _asNullableDateTime(invite['revoked_at']),
            createdAt: DateTime.parse(_asString(invite['created_at'])),
          ),
        )
        .toList(growable: false);
  }

  Future<void> revokeServerInvite({
    required String accessToken,
    required String serverId,
    required String code,
  }) async {
    await _request(
      method: 'DELETE',
      path: '/v1/servers/$serverId/invites/$code',
      accessToken: accessToken,
    );
  }

  Future<List<ApiChatMessage>> listServerChannelMessages({
    required String accessToken,
    required String serverId,
    required String channelId,
    int limit = 100,
  }) async {
    final response = await _request(
      method: 'GET',
      path: '/v1/servers/$serverId/channels/$channelId/messages',
      accessToken: accessToken,
      query: {'limit': '$limit'},
    );
    return _parseChatMessages(response.body);
  }

  Future<ApiChatMessage> sendServerChannelMessage({
    required String accessToken,
    required String serverId,
    required String channelId,
    String? content,
    String? imageUrl,
    String? imageObjectKey,
  }) async {
    final trimmedContent = content?.trim();
    final response = await _request(
      method: 'POST',
      path: '/v1/servers/$serverId/channels/$channelId/messages',
      accessToken: accessToken,
      jsonBody: {
        if (trimmedContent != null && trimmedContent.isNotEmpty)
          'content': trimmedContent,
        if (imageUrl != null && imageUrl.isNotEmpty) 'image_url': imageUrl,
        if (imageObjectKey != null && imageObjectKey.isNotEmpty)
          'image_object_key': imageObjectKey,
      },
    );
    final parsed = _parseChatMessages([response.body]);
    return parsed.first;
  }

  Future<ApiChatMessage> editServerChannelMessage({
    required String accessToken,
    required String serverId,
    required String channelId,
    required String messageId,
    required String content,
  }) async {
    final response = await _request(
      method: 'PATCH',
      path: '/v1/servers/$serverId/channels/$channelId/messages/$messageId',
      accessToken: accessToken,
      jsonBody: {'content': content.trim()},
    );
    final parsed = _parseChatMessages([response.body]);
    return parsed.first;
  }

  Future<void> deleteServerChannelMessage({
    required String accessToken,
    required String serverId,
    required String channelId,
    required String messageId,
  }) async {
    await _request(
      method: 'DELETE',
      path: '/v1/servers/$serverId/channels/$channelId/messages/$messageId',
      accessToken: accessToken,
    );
  }

  Future<List<ApiDirectMessageChannel>> listDirectMessageChannels({
    required String accessToken,
  }) async {
    final response = await _request(
      method: 'GET',
      path: '/v1/dms',
      accessToken: accessToken,
    );
    final body = _asList(response.body);
    return body
        .map((raw) => _asMap(raw))
        .map(
          (dm) => ApiDirectMessageChannel(
            channelId: _asString(dm['channel_id']),
            peerUserId: _asString(dm['peer_user_id']),
            peerHandle: _asString(dm['peer_handle']),
            peerDisplayName: _asNullableString(dm['peer_display_name']),
            peerAvatarUrl: _asNullableString(dm['peer_avatar_url']),
          ),
        )
        .toList(growable: false);
  }

  Future<List<ApiChatMessage>> listDirectMessageMessages({
    required String accessToken,
    required String channelId,
    int limit = 100,
  }) async {
    final response = await _request(
      method: 'GET',
      path: '/v1/dms/$channelId/messages',
      accessToken: accessToken,
      query: {'limit': '$limit'},
    );
    return _parseChatMessages(response.body);
  }

  Future<ApiDirectMessageChannel> openDirectMessage({
    required String accessToken,
    required String peerUserId,
  }) async {
    final response = await _request(
      method: 'POST',
      path: '/v1/dms/open',
      accessToken: accessToken,
      jsonBody: {
        'peer_user_id': peerUserId,
      },
    );
    final body = _asMap(response.body);
    return ApiDirectMessageChannel(
      channelId: _asString(body['channel_id']),
      peerUserId: _asString(body['peer_user_id']),
      peerHandle: _asString(body['peer_handle']),
      peerDisplayName: _asNullableString(body['peer_display_name']),
      peerAvatarUrl: _asNullableString(body['peer_avatar_url']),
    );
  }

  Future<void> sendDirectMessage({
    required String accessToken,
    required String channelId,
    String? content,
    String? imageUrl,
    String? imageObjectKey,
  }) async {
    final trimmedContent = content?.trim();
    await _request(
      method: 'POST',
      path: '/v1/dms/$channelId/messages',
      accessToken: accessToken,
      jsonBody: {
        if (trimmedContent != null && trimmedContent.isNotEmpty)
          'content': trimmedContent,
        if (imageUrl != null && imageUrl.isNotEmpty) 'image_url': imageUrl,
        if (imageObjectKey != null && imageObjectKey.isNotEmpty)
          'image_object_key': imageObjectKey,
      },
    );
  }

  Future<ApiChatMessage> editDirectMessage({
    required String accessToken,
    required String channelId,
    required String messageId,
    required String content,
  }) async {
    final response = await _request(
      method: 'PATCH',
      path: '/v1/dms/$channelId/messages/$messageId',
      accessToken: accessToken,
      jsonBody: {'content': content.trim()},
    );
    final parsed = _parseChatMessages([response.body]);
    return parsed.first;
  }

  Future<void> deleteDirectMessage({
    required String accessToken,
    required String channelId,
    required String messageId,
  }) async {
    await _request(
      method: 'DELETE',
      path: '/v1/dms/$channelId/messages/$messageId',
      accessToken: accessToken,
    );
  }

  Future<ApiImageUploadPrepare> prepareImageUpload({
    required String accessToken,
    required String contentType,
    String? fileExtension,
  }) async {
    final response = await _request(
      method: 'POST',
      path: '/v1/uploads/presign-image',
      accessToken: accessToken,
      jsonBody: {
        'content_type': contentType.toLowerCase(),
        if (fileExtension != null && fileExtension.trim().isNotEmpty)
          'file_extension': fileExtension.trim().toLowerCase(),
      },
    );
    final body = _asMap(response.body);
    final requiredHeadersMap = _asMap(body['required_headers']);
    final requiredHeaders = <String, String>{};
    requiredHeadersMap.forEach((key, value) {
      requiredHeaders[key] = _asString(value);
    });
    return ApiImageUploadPrepare(
      uploadUrl: _asString(body['upload_url']),
      imageUrl: _asString(body['image_url']),
      imageObjectKey: _asString(body['image_object_key']),
      expiresInSeconds: _asInt(body['expires_in_seconds']),
      requiredHeaders: requiredHeaders,
    );
  }

  Future<ApiImageUploadResult> uploadImageDirect({
    required String accessToken,
    required String contentType,
    String? fileExtension,
    required Uint8List data,
  }) async {
    final response = await _request(
      method: 'POST',
      path: '/v1/uploads/image-direct',
      accessToken: accessToken,
      jsonBody: {
        'content_type': contentType.toLowerCase(),
        if (fileExtension != null && fileExtension.trim().isNotEmpty)
          'file_extension': fileExtension.trim().toLowerCase(),
        'data_base64': base64Encode(data),
      },
    );
    final body = _asMap(response.body);
    return ApiImageUploadResult(
      imageUrl: _asString(body['image_url']),
      imageObjectKey: _asString(body['image_object_key']),
    );
  }

  List<ApiChatMessage> _parseChatMessages(dynamic rawBody) {
    final body = _asList(rawBody);
    return body
        .map((raw) => _asMap(raw))
        .map(
          (message) => ApiChatMessage(
            messageId: _asString(message['message_id']),
            channelId: _asString(message['channel_id']),
            authorUserId: _asString(message['author_user_id']),
            content: _asNullableString(message['content']),
            imageUrl: _asNullableString(message['image_url']),
            createdAt: DateTime.parse(_asString(message['created_at'])),
            editedAt: _asNullableDateTime(message['edited_at']),
            deletedAt: _asNullableDateTime(message['deleted_at']),
          ),
        )
        .toList(growable: false);
  }

  Future<ApiAuditLogPage> listAuditLogs({
    required String accessToken,
    required String serverId,
    int limit = 50,
    int? cursorLogId,
    String? action,
    String? actorUserId,
    String? targetUserId,
  }) async {
    final query = <String, String>{
      'limit': '$limit',
    };
    if (cursorLogId != null) {
      query['cursor_log_id'] = '$cursorLogId';
    }
    if (action != null && action.trim().isNotEmpty) {
      query['action'] = action.trim();
    }
    if (actorUserId != null && actorUserId.trim().isNotEmpty) {
      query['actor_user_id'] = actorUserId.trim();
    }
    if (targetUserId != null && targetUserId.trim().isNotEmpty) {
      query['target_user_id'] = targetUserId.trim();
    }

    final response = await _request(
      method: 'GET',
      path: '/v1/servers/$serverId/audit-logs',
      accessToken: accessToken,
      query: query,
    );
    final body = _asList(response.body);
    final items = body.map((raw) => _asMap(raw)).map((log) {
      final detailsRaw = log['details'];
      Map<String, dynamic>? details;
      if (detailsRaw is Map) {
        details = detailsRaw.cast<String, dynamic>();
      }
      return ApiAuditLogEntry(
        logId: _asInt(log['log_id']),
        action: _asString(log['action']),
        actorUserId: _asString(log['actor_user_id']),
        actorHandle: _asNullableString(log['actor_handle']),
        targetUserId: _asNullableString(log['target_user_id']),
        targetHandle: _asNullableString(log['target_handle']),
        targetChannelId: _asNullableString(log['target_channel_id']),
        details: details,
        createdAt: DateTime.parse(_asString(log['created_at'])),
      );
    }).toList(growable: false);

    final nextCursorRaw = response.headers['x-next-cursor'];
    final nextCursor = (nextCursorRaw == null || nextCursorRaw.isEmpty)
        ? null
        : int.tryParse(nextCursorRaw);

    return ApiAuditLogPage(
      items: items,
      nextCursor: nextCursor,
    );
  }

  Future<_ApiResponse> _request({
    required String method,
    required String path,
    Map<String, dynamic>? jsonBody,
    Map<String, String>? query,
    String? accessToken,
  }) async {
    final uri = Uri.parse('$_baseUrl$path').replace(
      queryParameters: (query == null || query.isEmpty) ? null : query,
    );
    final request = await _httpClient.openUrl(method, uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');

    if (accessToken != null && accessToken.isNotEmpty) {
      request.headers
          .set(HttpHeaders.authorizationHeader, 'Bearer $accessToken');
    }

    if (jsonBody != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(jsonBody));
    }

    final response = await request.close();
    final rawBody = await utf8.decoder.bind(response).join();
    dynamic parsedBody;
    if (rawBody.isNotEmpty) {
      try {
        parsedBody = jsonDecode(rawBody);
      } catch (_) {
        parsedBody = rawBody;
      }
    }

    if (response.statusCode >= 400) {
      final detail = _extractError(parsedBody);
      throw ApiException(
        detail.isEmpty ? 'Request failed with ${response.statusCode}' : detail,
        statusCode: response.statusCode,
      );
    }

    final normalizedHeaders = <String, String>{};
    response.headers.forEach((name, values) {
      normalizedHeaders[name.toLowerCase()] = values.join(',');
    });

    return _ApiResponse(
      statusCode: response.statusCode,
      body: parsedBody,
      headers: normalizedHeaders,
    );
  }

  String _extractError(dynamic body) {
    if (body is Map) {
      final detail = body['detail'];
      if (detail is String) {
        return detail;
      }
      if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map) {
          final msg = first['msg'];
          if (msg is String && msg.trim().isNotEmpty) {
            return msg;
          }
        }
        return first.toString();
      }
    }
    return body?.toString() ?? '';
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    throw ApiException('Unexpected API response format (expected object).');
  }

  List<dynamic> _asList(dynamic value) {
    if (value is List) {
      return value;
    }
    throw ApiException('Unexpected API response format (expected list).');
  }

  String _asString(dynamic value) {
    if (value is String) {
      return value;
    }
    throw ApiException(
        'Unexpected API response field format (expected string).');
  }

  String? _asNullableString(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is String) {
      return value;
    }
    return value.toString();
  }

  int _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    throw ApiException('Unexpected API response field format (expected int).');
  }

  int? _asNullableInt(dynamic value) {
    if (value == null) {
      return null;
    }
    return _asInt(value);
  }

  bool _asBool(dynamic value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1') {
        return true;
      }
      if (normalized == 'false' || normalized == '0') {
        return false;
      }
    }
    throw ApiException('Unexpected API response field format (expected bool).');
  }

  bool _asBoolOrDefault(dynamic value, bool fallback) {
    try {
      if (value == null) {
        return fallback;
      }
      return _asBool(value);
    } catch (_) {
      return fallback;
    }
  }

  DateTime? _asNullableDateTime(dynamic value) {
    final raw = _asNullableString(value);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return DateTime.parse(raw);
  }

  String _asStringOrDefault(dynamic value, String fallback) {
    if (value == null) {
      return fallback;
    }
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? fallback : trimmed;
    }
    return fallback;
  }

  String _normalizeThemePreference(dynamic value) {
    final raw = _asStringOrDefault(value, 'dark').toLowerCase();
    if (raw == 'light' || raw == 'system') {
      return raw;
    }
    return 'dark';
  }

  String _normalizeLanguage(dynamic value) {
    return _asStringOrDefault(value, 'en-US');
  }

  String _normalizeTimeFormat(dynamic value) {
    final raw = _asStringOrDefault(value, '24h').toLowerCase();
    if (raw == '12h') {
      return '12h';
    }
    return '24h';
  }
}

class _ApiResponse {
  const _ApiResponse({
    required this.statusCode,
    required this.body,
    required this.headers,
  });

  final int statusCode;
  final dynamic body;
  final Map<String, String> headers;
}
