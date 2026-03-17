import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:concord/backend/backend_server_settings_screen.dart';
import 'package:concord/backend/backend_session.dart';
import 'package:concord/backend/backend_user_settings_screen.dart';
import 'package:concord/backend/concord_api_client.dart';
import 'package:concord/backend/image_asset_picker.dart';
import 'package:concord/l10n/app_strings.dart';
import 'package:concord/l10n/language_provider.dart';

enum _MobileTab { servers, dms }

class BackendMobileShellScreen extends ConsumerStatefulWidget {
  const BackendMobileShellScreen({
    super.key,
    required this.session,
    required this.baseUrl,
  });

  final ApiAuthSession session;
  final String baseUrl;

  @override
  ConsumerState<BackendMobileShellScreen> createState() =>
      _BackendMobileShellScreenState();
}

class _BackendMobileShellScreenState
    extends ConsumerState<BackendMobileShellScreen> {
  final TextEditingController _composerController = TextEditingController();
  final TextEditingController _dmSearchController = TextEditingController();

  _MobileTab _activeTab = _MobileTab.servers;
  bool _loading = true;
  bool _loadingMessages = false;
  bool _sending = false;
  bool _voiceBusy = false;
  bool _openingDm = false;
  String? _error;
  String _dmSearchQuery = '';

  ApiCurrentUser? _currentUser;
  List<ApiServerSummary> _servers = const [];
  List<ApiChannelSummary> _channels = const [];
  List<ApiChannelSummary> _voiceChannels = const [];
  List<ApiDirectMessageChannel> _dmChannels = const [];
  List<ApiChatMessage> _messages = const [];
  List<ApiVoiceState> _voiceStates = const [];
  Map<String, ApiServerMember> _serverMembersById = const {};

  String? _selectedServerId;
  String? _selectedChannelId;
  String? _selectedDmChannelId;
  String? _connectedVoiceServerId;
  String? _connectedVoiceChannelId;
  bool _selfVoiceMuted = false;
  bool _selfVoiceDeafened = false;

  ConcordApiClient get _client => ConcordApiClient(baseUrl: widget.baseUrl);
  AppStrings _strings() => appStringsFor(ref.read(appLanguageProvider));
  String _t(String key, String fallback) => _strings().t(key, fallback: fallback);
  String _tf(String key, Map<String, String> values, String fallback) =>
      _strings().tf(key, values, fallback: fallback);

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _composerController.dispose();
    _dmSearchController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final me = await _client.getMe(accessToken: widget.session.accessToken);
      final servers =
          await _client.listServers(accessToken: widget.session.accessToken);
      final dms = await _client.listDirectMessageChannels(
        accessToken: widget.session.accessToken,
      );

      final selectedServerId = servers.any((s) => s.id == _selectedServerId)
          ? _selectedServerId
          : (servers.isNotEmpty ? servers.first.id : null);
      final selectedDmId = dms.any((d) => d.channelId == _selectedDmChannelId)
          ? _selectedDmChannelId
          : (dms.isNotEmpty ? dms.first.channelId : null);

      if (!mounted) {
        return;
      }
      setState(() {
        _currentUser = me;
        _servers = servers;
        _dmChannels = dms;
        _selectedServerId = selectedServerId;
        _selectedDmChannelId = selectedDmId;
        _loading = false;
      });

      if (_activeTab == _MobileTab.servers && selectedServerId != null) {
        await _loadServerState(selectedServerId, selectFirstChannel: true);
      } else if (_activeTab == _MobileTab.dms && selectedDmId != null) {
        await _loadDmMessages(selectedDmId);
      } else if (mounted) {
        setState(() {
          _messages = const [];
          _channels = const [];
          _voiceChannels = const [];
          _voiceStates = const [];
          _selectedChannelId = null;
          _serverMembersById = const {};
          _connectedVoiceServerId = null;
          _connectedVoiceChannelId = null;
          _selfVoiceMuted = false;
          _selfVoiceDeafened = false;
        });
      }
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = _t('failed_load_backend_data', 'Failed to load backend data.');
      });
    }
  }

  Future<void> _loadServerState(String serverId,
      {bool selectFirstChannel = false}) async {
    try {
      final channels = await _client.listServerChannels(
        accessToken: widget.session.accessToken,
        serverId: serverId,
      );
      final members = await _client.listServerMembers(
        accessToken: widget.session.accessToken,
        serverId: serverId,
      );
      final textChannels = channels
          .where((c) => c.kind == 'text')
          .toList(growable: false)
        ..sort((a, b) => a.position.compareTo(b.position));
      final voiceChannels = channels
          .where((c) => c.kind == 'voice')
          .toList(growable: false)
        ..sort((a, b) => a.position.compareTo(b.position));
      String? nextChannel = _selectedChannelId;
      if (selectFirstChannel ||
          !textChannels.any((channel) => channel.id == nextChannel)) {
        nextChannel = textChannels.isNotEmpty ? textChannels.first.id : null;
      }
      final membersMap = <String, ApiServerMember>{};
      for (final member in members) {
        membersMap[member.userId] = member;
      }

      ApiVoiceState? myVoiceState;
      List<ApiVoiceState> voiceStates = const [];
      String? voiceLoadError;
      try {
        myVoiceState = await _client.getMyVoiceState(
          accessToken: widget.session.accessToken,
          serverId: serverId,
        );
        if (myVoiceState != null) {
          voiceStates = await _client.listVoiceStates(
            accessToken: widget.session.accessToken,
            serverId: serverId,
            channelId: myVoiceState.channelId,
          );
        }
      } on ApiException catch (error) {
        voiceLoadError = error.message;
      } catch (_) {
        voiceLoadError =
            _t('failed_load_voice_state', 'Failed to load voice state.');
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _selectedServerId = serverId;
        _channels = textChannels;
        _voiceChannels = voiceChannels;
        _selectedChannelId = nextChannel;
        _serverMembersById = membersMap;
        _connectedVoiceServerId = myVoiceState == null ? null : serverId;
        _connectedVoiceChannelId = myVoiceState?.channelId;
        _selfVoiceMuted = myVoiceState?.muted ?? false;
        _selfVoiceDeafened = myVoiceState?.deafened ?? false;
        _voiceStates = voiceStates;
        if (voiceLoadError != null) {
          _error = voiceLoadError;
        }
      });
      if (_activeTab == _MobileTab.servers && nextChannel != null) {
        await _loadServerMessages(serverId, nextChannel);
      } else if (mounted && _activeTab == _MobileTab.servers) {
        setState(() => _messages = const []);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error is ApiException
            ? error.message
            : _t('failed_load_channels', 'Failed to load channels.');
      });
    }
  }

  Future<void> _loadServerMessages(String serverId, String channelId) async {
    if (!mounted) {
      return;
    }
    setState(() {
      _loadingMessages = true;
      _error = null;
    });
    try {
      final messages = await _client.listServerChannelMessages(
        accessToken: widget.session.accessToken,
        serverId: serverId,
        channelId: channelId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _messages = messages;
        _loadingMessages = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingMessages = false;
        _error = error is ApiException
            ? error.message
            : _t('failed_load_messages', 'Failed to load messages.');
      });
    }
  }

  Future<void> _loadDmMessages(String channelId) async {
    if (!mounted) {
      return;
    }
    setState(() {
      _loadingMessages = true;
      _error = null;
    });
    try {
      final messages = await _client.listDirectMessageMessages(
        accessToken: widget.session.accessToken,
        channelId: channelId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _messages = messages;
        _loadingMessages = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingMessages = false;
        _error = error is ApiException
            ? error.message
            : _t('failed_load_messages', 'Failed to load messages.');
      });
    }
  }

  Future<void> _switchTab(int index) async {
    final tab = _MobileTab.values[index];
    if (tab == _activeTab || !mounted) {
      return;
    }
    setState(() {
      _activeTab = tab;
      _messages = const [];
      _error = null;
    });
    if (tab == _MobileTab.servers) {
      final serverId =
          _selectedServerId ?? (_servers.isNotEmpty ? _servers.first.id : null);
      if (serverId != null) {
        await _loadServerState(serverId);
      }
    } else {
      final dmId = _selectedDmChannelId ??
          (_dmChannels.isNotEmpty ? _dmChannels.first.channelId : null);
      if (dmId != null) {
        if (mounted) {
          setState(() => _selectedDmChannelId = dmId);
        }
        await _loadDmMessages(dmId);
      }
    }
  }

  Future<void> _selectChannel(ApiChannelSummary channel) async {
    final serverId = _selectedServerId;
    if (serverId == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedChannelId = channel.id;
    });
    await _loadServerMessages(serverId, channel.id);
  }

  Future<void> _refreshCurrentView() async {
    if (_activeTab == _MobileTab.servers) {
      final serverId = _selectedServerId;
      if (serverId != null) {
        await _loadServerState(serverId);
        return;
      }
    } else {
      final dms = await _client.listDirectMessageChannels(
        accessToken: widget.session.accessToken,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _dmChannels = dms;
        _selectedDmChannelId = dms.any((d) => d.channelId == _selectedDmChannelId)
            ? _selectedDmChannelId
            : (dms.isNotEmpty ? dms.first.channelId : null);
      });
      final dmId = _selectedDmChannelId;
      if (dmId != null) {
        await _loadDmMessages(dmId);
        return;
      }
    }
    await _bootstrap();
  }

  Future<String?> _showSingleInputDialog({
    required String title,
    required String label,
    required String hint,
    required String confirmLabel,
  }) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
            ),
            onSubmitted: (_) =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(_t('cancel', 'Cancel')),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
    controller.dispose();
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  Future<void> _createServer() async {
    final name = await _showSingleInputDialog(
      title: _t('create_server_title', 'Create Server'),
      label: _t('server_name', 'Server Name'),
      hint: _t('server_name_hint', 'My Server'),
      confirmLabel: _t('create_server', 'Create Server'),
    );
    if (name == null) {
      return;
    }
    try {
      final server = await _client.createServer(
        accessToken: widget.session.accessToken,
        name: name,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _activeTab = _MobileTab.servers;
        _selectedServerId = server.id;
      });
      await _bootstrap();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tf(
              'server_created',
              {'name': server.name},
              'Server "{name}" created.',
            ),
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = _t('failed_create_server', 'Failed to create server.');
      });
    }
  }

  Future<void> _joinServer() async {
    final code = await _showSingleInputDialog(
      title: _t('join_server_title', 'Join Server'),
      label: _t('invite_code', 'Invite Code'),
      hint: _t('invite_code_hint', 'abc123xyz'),
      confirmLabel: _t('join_server', 'Join Server'),
    );
    if (code == null) {
      return;
    }
    try {
      final server = await _client.joinServerByInvite(
        accessToken: widget.session.accessToken,
        code: code,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _activeTab = _MobileTab.servers;
        _selectedServerId = server.id;
      });
      await _bootstrap();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tf(
              'joined_server',
              {'name': server.name},
              'Joined "{name}".',
            ),
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = _t('failed_join_server', 'Failed to join server.');
      });
    }
  }

  Future<void> _createChannel() async {
    final serverId = _selectedServerId;
    if (serverId == null) {
      return;
    }
    final nameController = TextEditingController();
    var selectedKind = 'text';
    final payload = await showDialog<Map<String, String>?>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(_t('create_channel_title', 'Create Channel')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: _t('channel_name', 'Channel Name'),
                      hintText: _t('channel_name_hint', 'general-chat'),
                    ),
                    onSubmitted: (_) => Navigator.of(dialogContext).pop({
                      'name': nameController.text.trim(),
                      'kind': selectedKind,
                    }),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey('mobile-channel-kind-$selectedKind'),
                    initialValue: selectedKind,
                    decoration: InputDecoration(
                      labelText: _t('channel_kind', 'Channel Type'),
                    ),
                    items: [
                      DropdownMenuItem<String>(
                        value: 'text',
                        child: Text(_t('channel_kind_text', 'Text')),
                      ),
                      DropdownMenuItem<String>(
                        value: 'voice',
                        child: Text(_t('channel_kind_voice', 'Voice')),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setDialogState(() {
                        selectedKind = value;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(_t('cancel', 'Cancel')),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop({
                    'name': nameController.text.trim(),
                    'kind': selectedKind,
                  }),
                  child: Text(_t('create', 'Create')),
                ),
              ],
            );
          },
        );
      },
    );
    nameController.dispose();

    final name = payload?['name']?.trim();
    if (name == null || name.isEmpty) {
      return;
    }
    final kind = payload?['kind'] == 'voice' ? 'voice' : 'text';
    try {
      final channel = await _client.createServerChannel(
        accessToken: widget.session.accessToken,
        serverId: serverId,
        name: name,
        kind: kind,
      );
      if (!mounted) {
        return;
      }
      if (channel.kind == 'text') {
        setState(() {
          _selectedChannelId = channel.id;
        });
      }
      await _loadServerState(serverId);
      if (channel.kind == 'voice') {
        await _joinVoiceChannel(channel.id);
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tf(
              'channel_created',
              {'name': channel.name},
              'Channel #{name} created.',
            ),
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = _t('failed_create_channel', 'Failed to create channel.');
      });
    }
  }

  Future<void> _openNewDm() async {
    if (_openingDm || !mounted) {
      return;
    }
    setState(() {
      _openingDm = true;
      _error = null;
    });
    try {
      final friends =
          await _client.listFriends(accessToken: widget.session.accessToken);
      if (!mounted) {
        return;
      }
      if (friends.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                _t('no_friends_yet', 'No friends yet.\nUse Add Friend to start chatting.')),
          ),
        );
        return;
      }
      final selected = await showModalBottomSheet<ApiUserSummary>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: ListView.builder(
            itemCount: friends.length,
            itemBuilder: (context, index) {
              final friend = friends[index];
              final display = (friend.displayName?.trim().isNotEmpty ?? false)
                  ? friend.displayName!.trim()
                  : friend.username;
              return ListTile(
                title: Text(display),
                subtitle: Text(friend.handle),
                onTap: () => Navigator.of(context).pop(friend),
              );
            },
          ),
        ),
      );
      if (selected == null) {
        return;
      }
      final dm = await _client.openDirectMessage(
        accessToken: widget.session.accessToken,
        peerUserId: selected.id,
      );
      final dms = await _client.listDirectMessageChannels(
        accessToken: widget.session.accessToken,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _activeTab = _MobileTab.dms;
        _dmChannels = dms;
        _selectedDmChannelId = dm.channelId;
        _messages = const [];
      });
      await _loadDmMessages(dm.channelId);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error is ApiException
            ? error.message
            : _t('failed_open_dm', 'Failed to open DM.');
      });
    } finally {
      if (mounted) {
        setState(() => _openingDm = false);
      }
    }
  }

  Future<void> _sendMessage() async {
    final content = _composerController.text.trim();
    if (_sending || content.isEmpty) {
      return;
    }
    if (_activeTab == _MobileTab.servers) {
      final serverId = _selectedServerId;
      final channelId = _selectedChannelId;
      if (serverId == null || channelId == null) {
        return;
      }
      await _sendServerMessage(serverId, channelId, content);
    } else {
      final channelId = _selectedDmChannelId;
      if (channelId == null) {
        return;
      }
      await _sendDmMessage(channelId, content);
    }
  }

  Future<void> _sendServerMessage(
      String serverId, String channelId, String content) async {
    if (!mounted) {
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await _client.sendServerChannelMessage(
        accessToken: widget.session.accessToken,
        serverId: serverId,
        channelId: channelId,
        content: content,
      );
      _composerController.clear();
      await _loadServerMessages(serverId, channelId);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error is ApiException
            ? error.message
            : _t('failed_send_message', 'Failed to send message.');
      });
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _sendDmMessage(String channelId, String content) async {
    if (!mounted) {
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await _client.sendDirectMessage(
        accessToken: widget.session.accessToken,
        channelId: channelId,
        content: content,
      );
      _composerController.clear();
      await _loadDmMessages(channelId);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error is ApiException
            ? error.message
            : _t('failed_send_message', 'Failed to send message.');
      });
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _openUserSettingsScreen() async {
    final changed = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => BackendUserSettingsScreen(
              baseUrl: widget.baseUrl,
              session: widget.session,
            ),
          ),
        ) ??
        false;
    if (changed && mounted) {
      await _bootstrap();
    }
  }

  Future<void> _openServerSettingsScreen() async {
    final serverId = _selectedServerId;
    if (serverId == null) {
      return;
    }
    final result =
        await Navigator.of(context).push<BackendServerSettingsResult>(
      MaterialPageRoute(
        builder: (_) => BackendServerSettingsScreen(
          baseUrl: widget.baseUrl,
          session: widget.session,
          serverId: serverId,
        ),
      ),
    );
    if (result == null || !result.didChange || !mounted) {
      return;
    }
    await _bootstrap();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.wasDeleted
              ? _t('server_deleted', 'Server deleted.')
              : _t('server_settings_updated', 'Server settings updated.'),
        ),
      ),
    );
  }

  String? _voiceChannelName(String? channelId) {
    if (channelId == null) {
      return null;
    }
    for (final channel in _voiceChannels) {
      if (channel.id == channelId) {
        return channel.name;
      }
    }
    return null;
  }

  String _voiceParticipantLabel(ApiVoiceState state) {
    final display = state.displayName?.trim();
    return (display != null && display.isNotEmpty) ? display : state.handle;
  }

  List<ApiVoiceState> _connectedVoiceParticipants() {
    final channelId = _connectedVoiceChannelId;
    if (channelId == null) {
      return const [];
    }
    return _voiceStates
        .where((state) => state.channelId == channelId)
        .toList(growable: false);
  }

  Future<void> _refreshVoiceParticipants() async {
    final serverId = _connectedVoiceServerId ?? _selectedServerId;
    final channelId = _connectedVoiceChannelId;
    if (serverId == null || channelId == null || _voiceBusy) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _voiceBusy = true;
      _error = null;
    });
    try {
      final participants = await _client.listVoiceStates(
        accessToken: widget.session.accessToken,
        serverId: serverId,
        channelId: channelId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _voiceStates = participants;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = _t('failed_load_voice_state', 'Failed to load voice state.');
      });
    } finally {
      if (mounted) {
        setState(() => _voiceBusy = false);
      }
    }
  }

  Future<void> _joinVoiceChannel(String channelId) async {
    final serverId = _selectedServerId;
    if (_voiceBusy || serverId == null) {
      return;
    }

    var nextMuted = _selfVoiceMuted;
    var nextDeafened = _selfVoiceDeafened;
    if (_connectedVoiceServerId != serverId || _connectedVoiceChannelId == null) {
      nextMuted = false;
      nextDeafened = false;
    }
    if (nextDeafened) {
      nextMuted = true;
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _voiceBusy = true;
      _error = null;
    });

    try {
      final state = await _client.joinOrUpdateVoiceState(
        accessToken: widget.session.accessToken,
        serverId: serverId,
        channelId: channelId,
        muted: nextMuted,
        deafened: nextDeafened,
      );
      final participants = await _client.listVoiceStates(
        accessToken: widget.session.accessToken,
        serverId: serverId,
        channelId: state.channelId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _connectedVoiceServerId = serverId;
        _connectedVoiceChannelId = state.channelId;
        _selfVoiceMuted = state.muted;
        _selfVoiceDeafened = state.deafened;
        _voiceStates = participants;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = _t('failed_join_voice', 'Failed to join voice channel.');
      });
    } finally {
      if (mounted) {
        setState(() => _voiceBusy = false);
      }
    }
  }

  Future<void> _leaveVoiceChannel() async {
    final serverId = _connectedVoiceServerId ?? _selectedServerId;
    final channelId = _connectedVoiceChannelId;
    if (_voiceBusy || serverId == null || channelId == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _voiceBusy = true;
      _error = null;
    });
    try {
      await _client.leaveVoiceState(
        accessToken: widget.session.accessToken,
        serverId: serverId,
        channelId: channelId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _connectedVoiceServerId = null;
        _connectedVoiceChannelId = null;
        _selfVoiceMuted = false;
        _selfVoiceDeafened = false;
        _voiceStates = const [];
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = _t('failed_leave_voice', 'Failed to leave voice channel.');
      });
    } finally {
      if (mounted) {
        setState(() => _voiceBusy = false);
      }
    }
  }

  Future<void> _updateVoiceState({
    required bool muted,
    required bool deafened,
  }) async {
    final serverId = _connectedVoiceServerId ?? _selectedServerId;
    final channelId = _connectedVoiceChannelId;
    if (_voiceBusy || serverId == null || channelId == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _voiceBusy = true;
      _error = null;
    });
    try {
      final state = await _client.joinOrUpdateVoiceState(
        accessToken: widget.session.accessToken,
        serverId: serverId,
        channelId: channelId,
        muted: muted,
        deafened: deafened,
      );
      final participants = await _client.listVoiceStates(
        accessToken: widget.session.accessToken,
        serverId: serverId,
        channelId: channelId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _selfVoiceMuted = state.muted;
        _selfVoiceDeafened = state.deafened;
        _voiceStates = participants;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = _t('failed_update_voice', 'Failed to update voice state.');
      });
    } finally {
      if (mounted) {
        setState(() => _voiceBusy = false);
      }
    }
  }

  ApiDirectMessageChannel? _selectedDm() {
    for (final dm in _dmChannels) {
      if (dm.channelId == _selectedDmChannelId) {
        return dm;
      }
    }
    return null;
  }

  String _dmPeerLabel(ApiDirectMessageChannel dm) {
    final display = dm.peerDisplayName?.trim();
    return (display != null && display.isNotEmpty) ? display : dm.peerHandle;
  }

  List<ApiDirectMessageChannel> _visibleDmChannels() {
    final query = _dmSearchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return _dmChannels;
    }
    return _dmChannels.where((dm) {
      final label = _dmPeerLabel(dm).toLowerCase();
      final handle = dm.peerHandle.toLowerCase();
      return label.contains(query) || handle.contains(query);
    }).toList(growable: false);
  }

  String _topBarName() {
    final displayName = _currentUser?.displayName?.trim();
    return (displayName != null && displayName.isNotEmpty)
        ? displayName
        : _t('display_name', 'Display Name');
  }

  String _conversationTitle() {
    if (_activeTab == _MobileTab.servers) {
      for (final channel in _channels) {
        if (channel.id == _selectedChannelId) {
          return '# ${channel.name}';
        }
      }
      return _t('select_channel', 'Select Channel');
    }
    final dm = _selectedDm();
    return dm == null ? _t('direct_message', 'Direct Message') : _dmPeerLabel(dm);
  }

  bool _hasActiveConversation() => _activeTab == _MobileTab.servers
      ? _selectedChannelId != null
      : _selectedDmChannelId != null;

  String _authorLabel(String userId) {
    if (userId == widget.session.userId) {
      return _topBarName();
    }
    if (_activeTab == _MobileTab.dms) {
      final dm = _selectedDm();
      if (dm != null) {
        return _dmPeerLabel(dm);
      }
    }
    final member = _serverMembersById[userId];
    if (member != null) {
      final display = member.displayName?.trim();
      if (display != null && display.isNotEmpty) {
        return display;
      }
      return member.username;
    }
    return userId.substring(0, 8);
  }

  bool _isOwnMessage(ApiChatMessage message) {
    return message.authorUserId == widget.session.userId;
  }

  Future<void> _editMessage(ApiChatMessage message) async {
    if (!_isOwnMessage(message) || message.deletedAt != null) {
      return;
    }

    final controller = TextEditingController(text: message.content ?? '');
    final updated = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(_t('edit_message', 'Edit Message')),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 1,
            maxLines: 6,
            decoration: InputDecoration(
              labelText: _t('message', 'Message'),
            ),
            onSubmitted: (_) =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(_t('cancel', 'Cancel')),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: Text(_t('save', 'Save')),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (updated == null) {
      return;
    }
    final content = updated.trim();
    if (content.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = _t('edited_message_empty', 'Edited message cannot be empty.');
      });
      return;
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      if (_activeTab == _MobileTab.servers) {
        final serverId = _selectedServerId;
        final channelId = _selectedChannelId;
        if (serverId == null || channelId == null) {
          return;
        }
        await _client.editServerChannelMessage(
          accessToken: widget.session.accessToken,
          serverId: serverId,
          channelId: channelId,
          messageId: message.messageId,
          content: content,
        );
      } else {
        final dmChannelId = _selectedDmChannelId;
        if (dmChannelId == null) {
          return;
        }
        await _client.editDirectMessage(
          accessToken: widget.session.accessToken,
          channelId: dmChannelId,
          messageId: message.messageId,
          content: content,
        );
      }
      await _refreshMessagesOnly();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error is ApiException
            ? error.message
            : _t('failed_edit_message', 'Failed to edit message.');
      });
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _confirmDeleteMessage(ApiChatMessage message) async {
    if (!_isOwnMessage(message) || message.deletedAt != null) {
      return;
    }

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: Text(_t('delete_message', 'Delete Message')),
              content: Text(
                _t('delete_message_confirm', 'Delete this message?'),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(_t('cancel', 'Cancel')),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(_t('delete', 'Delete')),
                ),
              ],
            );
          },
        ) ??
        false;
    if (!confirmed) {
      return;
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      if (_activeTab == _MobileTab.servers) {
        final serverId = _selectedServerId;
        final channelId = _selectedChannelId;
        if (serverId == null || channelId == null) {
          return;
        }
        await _client.deleteServerChannelMessage(
          accessToken: widget.session.accessToken,
          serverId: serverId,
          channelId: channelId,
          messageId: message.messageId,
        );
      } else {
        final dmChannelId = _selectedDmChannelId;
        if (dmChannelId == null) {
          return;
        }
        await _client.deleteDirectMessage(
          accessToken: widget.session.accessToken,
          channelId: dmChannelId,
          messageId: message.messageId,
        );
      }
      await _refreshMessagesOnly();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error is ApiException
            ? error.message
            : _t('failed_delete_message', 'Failed to delete message.');
      });
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _sendImageMessage() async {
    if (_sending || !_hasActiveConversation()) {
      return;
    }
    final picked = await pickAndCropSquareImage(
      context: context,
      strings: _strings(),
      withCircleUi: false,
    );
    if (picked == null) {
      return;
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final uploaded = await _client.uploadImageDirect(
        accessToken: widget.session.accessToken,
        contentType: picked.contentType,
        fileExtension: picked.fileExtension,
        data: picked.data,
      );
      if (_activeTab == _MobileTab.servers) {
        final serverId = _selectedServerId;
        final channelId = _selectedChannelId;
        if (serverId == null || channelId == null) {
          return;
        }
        await _client.sendServerChannelMessage(
          accessToken: widget.session.accessToken,
          serverId: serverId,
          channelId: channelId,
          imageUrl: uploaded.imageUrl,
          imageObjectKey: uploaded.imageObjectKey,
        );
      } else {
        final dmChannelId = _selectedDmChannelId;
        if (dmChannelId == null) {
          return;
        }
        await _client.sendDirectMessage(
          accessToken: widget.session.accessToken,
          channelId: dmChannelId,
          imageUrl: uploaded.imageUrl,
          imageObjectKey: uploaded.imageObjectKey,
        );
      }
      await _refreshMessagesOnly();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error is ApiException
            ? error.message
            : _t('failed_pick_image', 'Failed to pick image.');
      });
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  String _formatTime(DateTime value) =>
      DateFormat('MM-dd HH:mm').format(value.toLocal());

  Widget _buildDrawer() {
    if (_activeTab == _MobileTab.servers) {
      return Drawer(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _t('servers', 'Servers'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: _t('create_server', 'Create Server'),
                      onPressed: () {
                        Navigator.of(context).pop();
                        unawaited(_createServer());
                      },
                      icon: const Icon(Icons.add_business_rounded),
                    ),
                    IconButton(
                      tooltip: _t('join_server', 'Join Server'),
                      onPressed: () {
                        Navigator.of(context).pop();
                        unawaited(_joinServer());
                      },
                      icon: const Icon(Icons.group_add_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: _servers.length,
                  itemBuilder: (context, index) {
                    final server = _servers[index];
                    return ListTile(
                      selected: server.id == _selectedServerId,
                      title: Text(server.name),
                      onTap: () {
                        Navigator.of(context).pop();
                        unawaited(
                          _loadServerState(server.id, selectFirstChannel: true),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: TextField(
                controller: _dmSearchController,
                onChanged: (value) {
                  if (!mounted) {
                    return;
                  }
                  setState(() {
                    _dmSearchQuery = value;
                  });
                },
                decoration: InputDecoration(
                  hintText: _t('search', 'Search'),
                  prefixIcon: const Icon(Icons.search_rounded),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                onPressed: _openingDm ? null : _openNewDm,
                icon: const Icon(Icons.person_add_alt_1_rounded),
              ),
            ),
            Expanded(
              child: Builder(builder: (context) {
                final visibleDms = _visibleDmChannels();
                if (visibleDms.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(_t('no_friends_yet',
                          'No friends yet.\nUse Add Friend to start chatting.')),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: visibleDms.length,
                  itemBuilder: (context, index) {
                    final dm = visibleDms[index];
                    return ListTile(
                      selected: dm.channelId == _selectedDmChannelId,
                      title: Text(_dmPeerLabel(dm)),
                      subtitle: Text(dm.peerHandle),
                      onTap: () {
                        Navigator.of(context).pop();
                        if (mounted) {
                          setState(() => _selectedDmChannelId = dm.channelId);
                        }
                        unawaited(_loadDmMessages(dm.channelId));
                      },
                    );
                  },
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationStrip() {
    final items = _activeTab == _MobileTab.servers ? _channels : _visibleDmChannels();
    if (items.isEmpty) {
      return const SizedBox(height: 10);
    }
    return SizedBox(
      height: 56,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          if (_activeTab == _MobileTab.servers) {
            final channel = _channels[index];
            return ChoiceChip(
              label: Text('# ${channel.name}'),
              selected: channel.id == _selectedChannelId,
              onSelected: (_) => _selectChannel(channel),
            );
          }
          final dm = items[index] as ApiDirectMessageChannel;
          return ChoiceChip(
            label: Text(_dmPeerLabel(dm)),
            selected: dm.channelId == _selectedDmChannelId,
            onSelected: (_) {
              if (mounted) {
                setState(() => _selectedDmChannelId = dm.channelId);
              }
              unawaited(_loadDmMessages(dm.channelId));
            },
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemCount: items.length,
      ),
    );
  }

  Widget _buildVoicePanel() {
    if (_activeTab != _MobileTab.servers || _voiceChannels.isEmpty) {
      return const SizedBox.shrink();
    }

    final connectedChannelId = _connectedVoiceChannelId;
    final connectedChannelName = _voiceChannelName(connectedChannelId);
    final participants = _connectedVoiceParticipants();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _t('voice_channels', 'Voice Channels'),
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const Spacer(),
              IconButton(
                tooltip: _t('refresh', 'Refresh'),
                onPressed: connectedChannelId == null || _voiceBusy
                    ? null
                    : _refreshVoiceParticipants,
                icon: _voiceBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _voiceChannels.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final channel = _voiceChannels[index];
                final connected = connectedChannelId == channel.id;
                return FilledButton.tonalIcon(
                  onPressed: _voiceBusy
                      ? null
                      : () {
                          if (connected) {
                            unawaited(_leaveVoiceChannel());
                          } else {
                            unawaited(_joinVoiceChannel(channel.id));
                          }
                        },
                  icon: Icon(
                    connected
                        ? Icons.call_end_rounded
                        : Icons.volume_up_rounded,
                    size: 18,
                  ),
                  label: Text(
                    '${channel.name} · '
                    '${connected ? _t('voice_leave', 'Leave') : _t('voice_join', 'Join')}',
                  ),
                );
              },
            ),
          ),
          if (connectedChannelId != null) ...[
            const SizedBox(height: 8),
            Text(
              _tf(
                'voice_connected_to',
                {'channel': connectedChannelName ?? connectedChannelId},
                'Connected to voice: {channel}',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  selected: _selfVoiceMuted,
                  onSelected: _voiceBusy
                      ? null
                      : (_) => unawaited(
                            _updateVoiceState(
                              muted: !_selfVoiceMuted,
                              deafened: _selfVoiceDeafened &&
                                  (!_selfVoiceMuted),
                            ),
                          ),
                  label: Text(
                    _selfVoiceMuted
                        ? _t('voice_unmute', 'Unmute')
                        : _t('voice_mute', 'Mute'),
                  ),
                ),
                FilterChip(
                  selected: _selfVoiceDeafened,
                  onSelected: _voiceBusy
                      ? null
                      : (_) => unawaited(
                            _updateVoiceState(
                              muted:
                                  _selfVoiceDeafened ? _selfVoiceMuted : true,
                              deafened: !_selfVoiceDeafened,
                            ),
                          ),
                  label: Text(
                    _selfVoiceDeafened
                        ? _t('voice_undeafen', 'Undeafen')
                        : _t('voice_deafen', 'Deafen'),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _voiceBusy ? null : _leaveVoiceChannel,
                  icon: const Icon(Icons.call_end_rounded),
                  label: Text(_t('voice_leave', 'Leave')),
                ),
              ],
            ),
            if (participants.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _tf(
                  'voice_participants',
                  {'count': '${participants.length}'},
                  'Voice Participants - {count}',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: participants
                    .map(
                      (state) => Chip(
                        avatar: Icon(
                          state.deafened
                              ? Icons.hearing_disabled_rounded
                              : state.muted
                                  ? Icons.mic_off_rounded
                                  : Icons.mic_rounded,
                          size: 16,
                        ),
                        label: Text(_voiceParticipantLabel(state)),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _refreshMessagesOnly() async {
    if (_activeTab == _MobileTab.servers) {
      final serverId = _selectedServerId;
      final channelId = _selectedChannelId;
      if (serverId != null && channelId != null) {
        await _loadServerMessages(serverId, channelId);
      }
    } else {
      final channelId = _selectedDmChannelId;
      if (channelId != null) {
        await _loadDmMessages(channelId);
      }
    }
  }

  Widget _buildMessageList() {
    if (_loadingMessages) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_hasActiveConversation()) {
      return Center(child: Text(_t('select_channel_or_user', 'Select a channel or user')));
    }
    if (_messages.isEmpty) {
      return Center(child: Text(_t('no_messages', 'No messages')));
    }
    return RefreshIndicator(
      onRefresh: _refreshMessagesOnly,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        itemCount: _messages.length,
        itemBuilder: (context, index) {
          final message = _messages[index];
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _authorLabel(message.authorUserId),
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (_isOwnMessage(message) && message.deletedAt == null)
                        PopupMenuButton<String>(
                          tooltip: _t('message_actions', 'Message Actions'),
                          onSelected: (value) {
                            if (value == 'edit') {
                              unawaited(_editMessage(message));
                            } else if (value == 'delete') {
                              unawaited(_confirmDeleteMessage(message));
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem<String>(
                              value: 'edit',
                              child: Text(_t('edit_message', 'Edit Message')),
                            ),
                            PopupMenuItem<String>(
                              value: 'delete',
                              child: Text(_t('delete_message', 'Delete Message')),
                            ),
                          ],
                        ),
                      Text(_formatTime(message.createdAt)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (message.deletedAt != null)
                    Text(_t('message_deleted', 'Message deleted'))
                  else ...[
                    if (message.content != null && message.content!.isNotEmpty)
                      Text(message.content!),
                    if (message.imageUrl != null && message.imageUrl!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            message.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              child: Text(
                                _t('image_load_failed', 'Failed to load image'),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildComposer() {
    final enabled = !_sending && _hasActiveConversation();
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: Row(
          children: [
            IconButton(
              tooltip: _t('pick_image', 'Pick Image'),
              onPressed: enabled ? _sendImageMessage : null,
              icon: const Icon(Icons.add_photo_alternate_rounded),
            ),
            Expanded(
              child: TextField(
                controller: _composerController,
                enabled: enabled,
                minLines: 1,
                maxLines: 5,
                decoration: InputDecoration(
                  hintText: _t('message_placeholder', 'Type a message'),
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: enabled ? _sendMessage : null,
              child: _sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appLanguageProvider);
    return Scaffold(
      drawer: _buildDrawer(),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_topBarName()),
            Text(
              _conversationTitle(),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _t('refresh', 'Refresh'),
            onPressed: () => unawaited(_refreshCurrentView()),
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'create_server') {
                unawaited(_createServer());
                return;
              }
              if (value == 'join_server') {
                unawaited(_joinServer());
                return;
              }
              if (value == 'create_channel') {
                unawaited(_createChannel());
                return;
              }
              if (value == 'server_settings') {
                unawaited(_openServerSettingsScreen());
                return;
              }
              if (value == 'settings') {
                _openUserSettingsScreen();
                return;
              }
              if (value == 'logout') {
                ref.read(backendSessionProvider.notifier).logout();
              }
            },
            itemBuilder: (context) {
              final items = <PopupMenuEntry<String>>[];
              if (_activeTab == _MobileTab.servers) {
                items.add(
                  PopupMenuItem<String>(
                    value: 'create_server',
                    child: Text(_t('create_server', 'Create Server')),
                  ),
                );
                items.add(
                  PopupMenuItem<String>(
                    value: 'join_server',
                    child: Text(_t('join_server', 'Join Server')),
                  ),
                );
                if (_selectedServerId != null) {
                  items.add(
                    PopupMenuItem<String>(
                      value: 'create_channel',
                      child: Text(_t('create_channel', 'Create Channel')),
                    ),
                  );
                  items.add(
                    PopupMenuItem<String>(
                      value: 'server_settings',
                      child: Text(_t('server_settings', 'Server Settings')),
                    ),
                  );
                }
              }
              items.add(
                PopupMenuItem<String>(
                  value: 'settings',
                  child: Text(_t('user_settings_title', 'User Settings')),
                ),
              );
              items.add(
                PopupMenuItem<String>(
                  value: 'logout',
                  child: Text(_t('log_out', 'Log Out')),
                ),
              );
              return items;
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_error != null)
                  Container(
                    width: double.infinity,
                    color: Theme.of(context)
                        .colorScheme
                        .errorContainer
                        .withValues(alpha: 0.8),
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                if (_activeTab == _MobileTab.servers &&
                    _voiceChannels.isNotEmpty) ...[
                  _buildVoicePanel(),
                  const Divider(height: 1),
                ],
                _buildConversationStrip(),
                const Divider(height: 1),
                Expanded(child: _buildMessageList()),
                _buildComposer(),
              ],
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _activeTab.index,
        onDestinationSelected: (index) => unawaited(_switchTab(index)),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.forum_outlined),
            selectedIcon: const Icon(Icons.forum),
            label: _t('servers', 'Servers'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: const Icon(Icons.chat_bubble_rounded),
            label: _t('direct_message', 'DM'),
          ),
        ],
      ),
    );
  }
}
