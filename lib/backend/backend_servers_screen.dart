import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'package:concord/backend/backend_server_settings_screen.dart';
import 'package:concord/backend/concord_api_client.dart';
import 'package:concord/backend/backend_user_settings_screen.dart';
import 'package:concord/backend/voice_signaling_client.dart';
import 'package:concord/backend/webrtc_voice_transport.dart';
import 'package:concord/core/time/time_format_provider.dart';
import 'package:concord/core/voice/voice_settings_store.dart';
import 'package:concord/l10n/app_strings.dart';
import 'package:concord/l10n/language_provider.dart';

enum _SidebarMode {
  servers,
  users,
}

class BackendServersScreen extends ConsumerStatefulWidget {
  const BackendServersScreen({
    super.key,
    required this.session,
    required this.baseUrl,
  });

  final ApiAuthSession session;
  final String baseUrl;

  @override
  ConsumerState<BackendServersScreen> createState() =>
      _BackendServersScreenState();
}

class _BackendServersScreenState extends ConsumerState<BackendServersScreen> {
  static const double _railWidth = 90;
  static const double _resizeHandleWidth = 6;
  static const double _minListPaneWidth = 260;
  static const double _minChatPaneWidth = 420;
  static const double _minMemberPaneWidth = 220;
  static const double _maxListPaneWidth = 520;
  static const double _maxMemberPaneWidth = 420;

  final TextEditingController _composerController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  final ScrollController _serverRailScrollController = ScrollController();

  _SidebarMode _sidebarMode = _SidebarMode.servers;
  List<ApiServerSummary> _servers = const [];
  List<ApiChannelSummary> _channels = const [];
  List<ApiChannelSummary> _voiceChannels = const [];
  List<ApiUserSummary> _users = const [];
  List<ApiServerMember> _serverMembers = const [];
  Set<String> _onlineServerMemberUserIds = <String>{};
  List<ApiVoiceState> _voiceStates = const [];
  List<ApiChatMessage> _messages = const [];
  ApiCurrentUser? _currentUserSettings;
  bool _loading = true;
  bool _loadingMessages = false;
  bool _loadingServerMembers = false;
  bool _sending = false;
  bool _runningAction = false;
  String? _error;
  String? _serverMembersError;

  String? _selectedServerId;
  String? _selectedChannelId;
  String? _selectedUserId;
  String? _selectedDmChannelId;
  String? _connectedVoiceServerId;
  String? _connectedVoiceChannelId;
  String? _connectedVoiceChannelName;
  bool _selfVoiceMuted = false;
  bool _selfVoiceDeafened = false;
  bool _voiceBusy = false;
  VoiceSettings _voiceSettings = const VoiceSettings();
  VoiceSignalClient? _voiceSignalClient;
  StreamSubscription<VoiceSignalEvent>? _voiceSignalEventSubscription;
  StreamSubscription<String>? _voiceSignalStatusSubscription;
  StreamSubscription<int>? _voiceLatencySubscription;
  String _voiceSignalStatus = 'idle';
  String _voiceTransportStatus = 'idle';
  int? _voiceLatencyMs;
  DateTime? _voiceConnectedAt;
  WebRtcVoiceTransport? _voiceTransport;
  String? _voiceTransportConfigKey;
  Timer? _voiceReconnectTimer;
  Timer? _voiceConnectionTicker;
  int _voiceReconnectAttempt = 0;
  bool _voiceAutoReconnectEnabled = false;
  Map<String, RTCPeerConnectionState> _voicePeerStates =
      <String, RTCPeerConnectionState>{};
  XFile? _pendingImageFile;
  Uint8List? _pendingImageBytes;
  double _listPaneWidth = 320;
  double _memberPaneWidth = 260;
  final Set<String> _seenMessageIds = <String>{};
  String _messageContextKey = '';

  ConcordApiClient get _client => ConcordApiClient(baseUrl: widget.baseUrl);

  AppStrings _strings() => appStringsFor(ref.read(appLanguageProvider));

  String _t(String key, String fallback) {
    return _strings().t(key, fallback: fallback);
  }

  void _setMessageContextKey(String nextKey) {
    if (_messageContextKey == nextKey) {
      return;
    }
    _messageContextKey = nextKey;
    _seenMessageIds.clear();
  }

  String _extensionFromFilename(String input) {
    final lastDot = input.lastIndexOf('.');
    if (lastDot < 0 || lastDot >= input.length - 1) {
      return '';
    }
    return input.substring(lastDot + 1).toLowerCase();
  }

  String _contentTypeForExtension(String extension) {
    switch (extension.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'image/png';
    }
  }

  bool _isOwnMessage(ApiChatMessage message) {
    return message.authorUserId == widget.session.userId;
  }

  bool _shouldShowServerMemberPane() {
    return _selectedServerId != null &&
        _selectedDmChannelId == null &&
        _sidebarMode == _SidebarMode.servers;
  }

  bool _useCompactMessageDisplay() {
    return _currentUserSettings?.compactMode ?? false;
  }

  bool _showMessageTimestamps() {
    return _currentUserSettings?.showMessageTimestamps ?? true;
  }

  String _activeLocale() {
    final language = normalizeLanguageCode(ref.read(appLanguageProvider));
    return language.replaceAll('-', '_');
  }

  String _activeTimePattern() {
    final format = normalizeTimeFormatPreference(
      ref.read(appTimeFormatProvider),
    );
    if (format == '12h') {
      return 'MM-dd hh:mm a';
    }
    return 'MM-dd HH:mm';
  }

  DateFormat _activeDateFormatter() {
    final pattern = _activeTimePattern();
    final locale = _activeLocale();
    try {
      return DateFormat(pattern, locale);
    } catch (_) {
      return DateFormat(pattern, 'en_US');
    }
  }

  bool _isDarkTheme(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark;
  }

  Color _railBackgroundColor(BuildContext context) {
    return _isDarkTheme(context)
        ? const Color(0xFF1E1F22)
        : const Color(0xFFE3E5E8);
  }

  Color _paneBackgroundColor(BuildContext context) {
    return _isDarkTheme(context)
        ? const Color(0xFF2B2D31)
        : const Color(0xFFF2F3F5);
  }

  Color _chatBackgroundColor(BuildContext context) {
    return _isDarkTheme(context)
        ? const Color(0xFF313338)
        : const Color(0xFFFFFFFF);
  }

  Color _memberPaneBackgroundColor(BuildContext context) {
    return _isDarkTheme(context)
        ? const Color(0xFF232428)
        : const Color(0xFFF3F4F6);
  }

  Color _resizeHandleColor(BuildContext context) {
    return _isDarkTheme(context)
        ? const Color(0xFF1A1B1E)
        : const Color(0xFFD3D7DE);
  }

  Color _resizeGripColor(BuildContext context) {
    return _isDarkTheme(context) ? Colors.white24 : Colors.black26;
  }

  Color _serverPillColor(BuildContext context, bool selected) {
    if (selected) {
      return Theme.of(context).colorScheme.primary;
    }
    return _isDarkTheme(context)
        ? const Color(0xFF2B2D31)
        : const Color(0xFFD3D8DF);
  }

  Color _composerBackgroundColor(BuildContext context) {
    return _isDarkTheme(context)
        ? const Color(0xFF2B2D31)
        : const Color(0xFFF4F5F7);
  }

  Color _composerInputColor(BuildContext context) {
    return _isDarkTheme(context)
        ? const Color(0xFF383A40)
        : const Color(0xFFFFFFFF);
  }

  Color _composerInputBorderColor(BuildContext context) {
    return _isDarkTheme(context)
        ? const Color(0x55363A42)
        : const Color(0xFFCDD3DB);
  }

  Color _composerPreviewColor(BuildContext context) {
    return _isDarkTheme(context)
        ? const Color(0xFF3A3D44)
        : const Color(0xFFEAECEF);
  }

  bool _messagesBelongToSameGroup(
    ApiChatMessage previous,
    ApiChatMessage current,
  ) {
    if (previous.authorUserId != current.authorUserId) {
      return false;
    }
    final gap =
        current.createdAt.toUtc().difference(previous.createdAt.toUtc()).abs();
    return gap <= const Duration(minutes: 6);
  }

  Color _messageBlockColor(BuildContext context, bool isOwn) {
    if (isOwn) {
      return Theme.of(context).colorScheme.primary.withValues(
            alpha: _isDarkTheme(context) ? 0.18 : 0.12,
          );
    }
    return _isDarkTheme(context)
        ? const Color(0xFF272A30)
        : const Color(0xFFF1F3F7);
  }

  BorderRadius _messageBlockRadius({
    required bool isGroupStart,
    required bool isGroupEnd,
  }) {
    const large = Radius.circular(12);
    const small = Radius.circular(7);
    return BorderRadius.only(
      topLeft: isGroupStart ? large : small,
      topRight: isGroupStart ? large : small,
      bottomLeft: isGroupEnd ? large : small,
      bottomRight: isGroupEnd ? large : small,
    );
  }

  Widget _buildChatLoadingSkeleton(BuildContext context) {
    return ListView.builder(
      key: const ValueKey<String>('chat-loading-skeleton'),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      itemCount: 7,
      itemBuilder: (context, index) {
        final widthFactor = 0.58 + ((index % 3) * 0.14);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _AnimatedSkeletonBlock(
                width: 142,
                height: 10,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FractionallySizedBox(
                      widthFactor: widthFactor.clamp(0.4, 0.94).toDouble(),
                      child: const _AnimatedSkeletonBlock(
                        height: 36,
                        borderRadius: 10,
                      ),
                    ),
                    if (index % 3 == 2) ...[
                      const SizedBox(height: 6),
                      const FractionallySizedBox(
                        widthFactor: 0.44,
                        child: _AnimatedSkeletonBlock(
                          height: 72,
                          borderRadius: 10,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMembersLoadingSkeleton(BuildContext context) {
    return ListView.builder(
      key: const ValueKey<String>('members-loading-skeleton'),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      itemCount: 9,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              const _AnimatedSkeletonCircle(size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FractionallySizedBox(
                      widthFactor: 0.5 + ((index % 4) * 0.1),
                      child: const _AnimatedSkeletonBlock(height: 10),
                    ),
                    const SizedBox(height: 6),
                    const FractionallySizedBox(
                      widthFactor: 0.36,
                      child: _AnimatedSkeletonBlock(height: 8),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const _AnimatedSkeletonCircle(size: 10),
            ],
          ),
        );
      },
    );
  }

  _PaneWidths _computePaneWidths(double totalWidth) {
    final requestedMemberPane = _shouldShowServerMemberPane();
    final dividerCount = requestedMemberPane ? 2 : 1;
    double availableForPanes =
        totalWidth - _railWidth - (_resizeHandleWidth * dividerCount);

    bool showMemberPane = requestedMemberPane;
    if (showMemberPane &&
        availableForPanes <
            (_minListPaneWidth + _minChatPaneWidth + _minMemberPaneWidth)) {
      showMemberPane = false;
      availableForPanes = totalWidth - _railWidth - _resizeHandleWidth;
    }

    if (availableForPanes <= 0) {
      return const _PaneWidths(
        showMemberPane: false,
        listPaneWidth: _minListPaneWidth,
        chatPaneWidth: _minChatPaneWidth,
        memberPaneWidth: 0,
      );
    }

    if (!showMemberPane) {
      double maxList = (availableForPanes - _minChatPaneWidth);
      if (maxList > _maxListPaneWidth) {
        maxList = _maxListPaneWidth;
      }
      final clampedList = _listPaneWidth.clamp(
        _minListPaneWidth,
        maxList > _minListPaneWidth ? maxList : _minListPaneWidth,
      );
      final chat = availableForPanes - clampedList;
      return _PaneWidths(
        showMemberPane: false,
        listPaneWidth: clampedList.toDouble(),
        chatPaneWidth: chat,
        memberPaneWidth: 0,
      );
    }

    final maxCombined = availableForPanes - _minChatPaneWidth;
    double listUpper = maxCombined - _minMemberPaneWidth;
    if (listUpper > _maxListPaneWidth) {
      listUpper = _maxListPaneWidth;
    }
    if (listUpper < _minListPaneWidth) {
      listUpper = _minListPaneWidth;
    }
    double memberUpper = maxCombined - _minListPaneWidth;
    if (memberUpper > _maxMemberPaneWidth) {
      memberUpper = _maxMemberPaneWidth;
    }
    if (memberUpper < _minMemberPaneWidth) {
      memberUpper = _minMemberPaneWidth;
    }
    double list = _listPaneWidth
        .clamp(
          _minListPaneWidth,
          listUpper,
        )
        .toDouble();
    double member = _memberPaneWidth
        .clamp(
          _minMemberPaneWidth,
          memberUpper,
        )
        .toDouble();

    if (list + member > maxCombined) {
      final overflow = list + member - maxCombined;
      final reduceMember = (member - _minMemberPaneWidth).clamp(0, overflow);
      member -= reduceMember;
      final remainingOverflow = overflow - reduceMember;
      if (remainingOverflow > 0) {
        list = (list - remainingOverflow).clamp(_minListPaneWidth, list);
      }
    }

    final chat = availableForPanes - list - member;
    return _PaneWidths(
      showMemberPane: true,
      listPaneWidth: list,
      chatPaneWidth: chat,
      memberPaneWidth: member,
    );
  }

  void _resizeListPane(double delta, double totalWidth) {
    final widths = _computePaneWidths(totalWidth);
    final dividerCount = widths.showMemberPane ? 2 : 1;
    final availableForPanes =
        totalWidth - _railWidth - (_resizeHandleWidth * dividerCount);
    double maxList = widths.showMemberPane
        ? (availableForPanes - _minChatPaneWidth - _minMemberPaneWidth)
        : (availableForPanes - _minChatPaneWidth);
    if (maxList > _maxListPaneWidth) {
      maxList = _maxListPaneWidth;
    }

    if (maxList <= _minListPaneWidth) {
      return;
    }

    setState(() {
      _listPaneWidth =
          (_listPaneWidth + delta).clamp(_minListPaneWidth, maxList).toDouble();
    });
  }

  void _resizeMemberPane(double delta, double totalWidth) {
    final widths = _computePaneWidths(totalWidth);
    if (!widths.showMemberPane) {
      return;
    }

    final availableForPanes =
        totalWidth - _railWidth - (_resizeHandleWidth * 2);
    double maxMember =
        availableForPanes - _minChatPaneWidth - widths.listPaneWidth;
    if (maxMember > _maxMemberPaneWidth) {
      maxMember = _maxMemberPaneWidth;
    }
    if (maxMember <= _minMemberPaneWidth) {
      return;
    }

    setState(() {
      _memberPaneWidth = (_memberPaneWidth - delta)
          .clamp(_minMemberPaneWidth, maxMember)
          .toDouble();
    });
  }

  List<ApiServerSummary> _mergeServerIntoList(
    List<ApiServerSummary> servers,
    ApiServerSummary target,
  ) {
    final merged = <ApiServerSummary>[target];
    for (final server in servers) {
      if (server.id != target.id) {
        merged.add(server);
      }
    }
    return merged;
  }

  Future<void> _scrollServerRailToTop() async {
    if (!_serverRailScrollController.hasClients) {
      return;
    }
    await _serverRailScrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  void initState() {
    super.initState();
    _loadVoiceSettings();
    _bootstrap();
  }

  @override
  void dispose() {
    _voiceReconnectTimer?.cancel();
    _voiceConnectionTicker?.cancel();
    _voiceSignalEventSubscription?.cancel();
    _voiceSignalStatusSubscription?.cancel();
    _voiceLatencySubscription?.cancel();
    unawaited(_voiceSignalClient?.dispose());
    unawaited(_voiceTransport?.dispose());
    _composerController.dispose();
    _serverRailScrollController.dispose();
    super.dispose();
  }

  Future<List<ApiUserSummary>> _fetchSidebarUsers() async {
    if (widget.session.isPlatformAdmin) {
      return _client.listAllUsers(accessToken: widget.session.accessToken);
    }
    return _client.listFriends(accessToken: widget.session.accessToken);
  }

  Future<void> _loadVoiceSettings() async {
    final cached = await VoiceSettingsStore.loadPreference();
    if (!mounted) {
      return;
    }
    setState(() {
      _voiceSettings = cached;
    });
    if (_connectedVoiceChannelId != null) {
      await _voiceTransport?.setMuted(_selfVoiceMuted || _selfVoiceDeafened);
      await _voiceTransport?.applyOutputDevice(_voiceSettings.selectedOutputDeviceId);
      await _configureVoiceTransport(channelId: _connectedVoiceChannelId!);
    }
  }

  String _voiceTransportKey() {
    final urls = _voiceSettings.iceServerUrls.join(',');
    final user = _voiceSettings.turnUsername ?? '';
    final credential = _voiceSettings.turnCredential ?? '';
    return '$urls|$user|$credential';
  }

  void _clearVoiceReconnect() {
    _voiceReconnectTimer?.cancel();
    _voiceReconnectTimer = null;
    _voiceReconnectAttempt = 0;
  }

  void _setVoiceConnectedAt(DateTime? joinedAt) {
    _voiceConnectedAt = joinedAt?.toLocal();
    if (_voiceConnectedAt == null) {
      _voiceConnectionTicker?.cancel();
      _voiceConnectionTicker = null;
      return;
    }
    if (_voiceConnectionTicker != null && _voiceConnectionTicker!.isActive) {
      return;
    }
    _voiceConnectionTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      if (_voiceConnectedAt == null || _connectedVoiceChannelId == null) {
        _voiceConnectionTicker?.cancel();
        _voiceConnectionTicker = null;
        return;
      }
      setState(() {});
    });
  }

  void _scheduleVoiceReconnect({
    required String serverId,
    required String channelId,
  }) {
    if (!_voiceAutoReconnectEnabled) {
      return;
    }
    if (_voiceReconnectTimer != null && _voiceReconnectTimer!.isActive) {
      return;
    }
    final delaySeconds = (1 << _voiceReconnectAttempt).clamp(1, 20);
    _voiceReconnectAttempt = (_voiceReconnectAttempt + 1).clamp(0, 8);
    _voiceReconnectTimer = Timer(Duration(seconds: delaySeconds), () async {
      _voiceReconnectTimer = null;
      if (!mounted ||
          !_voiceAutoReconnectEnabled ||
          _connectedVoiceServerId != serverId ||
          _connectedVoiceChannelId != channelId) {
        return;
      }
      try {
        await _connectVoiceSignaling(serverId: serverId, channelId: channelId);
        await _configureVoiceTransport(channelId: channelId);
        if (!mounted) {
          return;
        }
        setState(() {
          _voiceSignalStatus = 'reconnected';
        });
      } catch (_) {
        _scheduleVoiceReconnect(serverId: serverId, channelId: channelId);
      }
    });
  }

  WebRtcVoiceTransport _ensureVoiceTransport() {
    final desiredKey = _voiceTransportKey();
    final existing = _voiceTransport;
    if (existing != null && _voiceTransportConfigKey == desiredKey) {
      return existing;
    }
    if (existing != null) {
      unawaited(existing.dispose());
      _voiceTransport = null;
      _voicePeerStates = <String, RTCPeerConnectionState>{};
    }
    final created = WebRtcVoiceTransport(
      currentUserId: widget.session.userId,
      onIceCandidate: (peerUserId, candidate) async {
        await _voiceSignalClient?.sendSignal(
          signalType: 'candidate',
          data: {
            'target_user_id': peerUserId,
            'candidate': candidate.candidate,
            'sdp_mid': candidate.sdpMid,
            'sdp_mline_index': candidate.sdpMLineIndex,
          },
        );
      },
      onStatus: (status) {
        if (!mounted) {
          return;
        }
        setState(() {
          _voiceTransportStatus = status;
        });
      },
      onPeerConnectionState: (peerUserId, state) {
        if (!mounted) {
          return;
        }
        setState(() {
          _voicePeerStates = {
            ..._voicePeerStates,
            peerUserId: state,
          };
        });
      },
      iceServerUrls: _voiceSettings.iceServerUrls,
      turnUsername: _voiceSettings.turnUsername,
      turnCredential: _voiceSettings.turnCredential,
    );
    _voiceTransport = created;
    _voiceTransportConfigKey = desiredKey;
    return created;
  }

  bool _isOfferLeader(String localUserId, String remoteUserId) {
    return localUserId.compareTo(remoteUserId) < 0;
  }

  Future<void> _syncVoicePeers() async {
    final transport = _voiceTransport;
    final signalClient = _voiceSignalClient;
    if (transport == null || signalClient == null) {
      return;
    }
    final participantIds = _voiceStates
        .map((state) => state.userId)
        .where((userId) => userId != widget.session.userId)
        .toSet();
    await transport.prunePeers(participantIds);
    if (mounted) {
      setState(() {
        _voicePeerStates = Map<String, RTCPeerConnectionState>.fromEntries(
          _voicePeerStates.entries.where(
            (entry) => participantIds.contains(entry.key),
          ),
        );
      });
    }

    for (final peerId in participantIds) {
      await transport.ensurePeerConnection(peerId);
      if (_isOfferLeader(widget.session.userId, peerId)) {
        final offer = await transport.createOffer(peerId);
        await signalClient.sendSignal(
          signalType: 'offer',
          data: {
            'target_user_id': peerId,
            'sdp': offer.sdp,
            'type': offer.type,
          },
        );
      }
    }
  }

  Future<void> _configureVoiceTransport({
    required String channelId,
  }) async {
    final transport = _ensureVoiceTransport();
    await transport.ensureLocalAudioTrack(
      inputDeviceId: _voiceSettings.selectedInputDeviceId,
      muted: _selfVoiceMuted || _selfVoiceDeafened,
      echoCancellation: _voiceSettings.echoCancellation,
      noiseSuppression: _voiceSettings.noiseSuppression,
    );
    await transport.applyOutputDevice(_voiceSettings.selectedOutputDeviceId);
    await _syncVoicePeers();
    await _voiceSignalClient?.sendSignal(
      signalType: 'hello',
      data: {
        'target_user_id': '',
        'channel_id': channelId,
      },
    );
  }

  Future<void> _disposeVoiceTransport() async {
    final transport = _voiceTransport;
    _voiceTransport = null;
    _voiceTransportConfigKey = null;
    _voicePeerStates = <String, RTCPeerConnectionState>{};
    _voiceTransportStatus = 'idle';
    if (transport != null) {
      await transport.dispose();
    }
  }

  Future<void> _handleVoiceSignalEvent(VoiceSignalEvent event) async {
    if (!mounted) {
      return;
    }
    if (_connectedVoiceServerId == null ||
        _connectedVoiceChannelId == null ||
        event.serverId != _connectedVoiceServerId ||
        event.channelId != _connectedVoiceChannelId) {
      return;
    }
    final senderUserId = event.senderUserId;
    if (senderUserId.isEmpty || senderUserId == widget.session.userId) {
      return;
    }
    final data = event.data;
    final targetUserId = (data['target_user_id']?.toString() ?? '').trim();
    final broadcast = targetUserId.isEmpty;
    if (!broadcast && targetUserId != widget.session.userId) {
      return;
    }

    final transport = _ensureVoiceTransport();

    if (event.signalType == 'hello' || event.signalType == 'join') {
      await transport.ensurePeerConnection(senderUserId);
      if (_isOfferLeader(widget.session.userId, senderUserId)) {
        final offer = await transport.createOffer(senderUserId);
        await _voiceSignalClient?.sendSignal(
          signalType: 'offer',
          data: {
            'target_user_id': senderUserId,
            'sdp': offer.sdp,
            'type': offer.type,
          },
        );
      }
      return;
    }

    if (event.signalType == 'leave') {
      await transport.closePeer(senderUserId);
      if (mounted) {
        setState(() {
          _voicePeerStates = {
            for (final entry in _voicePeerStates.entries)
              if (entry.key != senderUserId) entry.key: entry.value,
          };
        });
      }
      return;
    }

    if (event.signalType == 'offer') {
      final sdp = data['sdp']?.toString();
      final type = data['type']?.toString();
      if (sdp == null || sdp.isEmpty || type == null || type.isEmpty) {
        return;
      }
      final answer = await transport.receiveOfferAndCreateAnswer(
        peerUserId: senderUserId,
        sdp: sdp,
        type: type,
      );
      await _voiceSignalClient?.sendSignal(
        signalType: 'answer',
        data: {
          'target_user_id': senderUserId,
          'sdp': answer.sdp,
          'type': answer.type,
        },
      );
      return;
    }

    if (event.signalType == 'answer') {
      final sdp = data['sdp']?.toString();
      final type = data['type']?.toString();
      if (sdp == null || sdp.isEmpty || type == null || type.isEmpty) {
        return;
      }
      await transport.applyAnswer(
        peerUserId: senderUserId,
        sdp: sdp,
        type: type,
      );
      return;
    }

    if (event.signalType == 'candidate') {
      final candidate = data['candidate']?.toString();
      if (candidate == null || candidate.isEmpty) {
        return;
      }
      final sdpMidRaw = data['sdp_mid'];
      final sdpMid = sdpMidRaw == null ? null : sdpMidRaw.toString();
      final sdpMLineRaw = data['sdp_mline_index'];
      int? sdpMLineIndex;
      if (sdpMLineRaw is int) {
        sdpMLineIndex = sdpMLineRaw;
      } else if (sdpMLineRaw is String) {
        sdpMLineIndex = int.tryParse(sdpMLineRaw);
      }
      await transport.addIceCandidate(
        peerUserId: senderUserId,
        candidate: candidate,
        sdpMid: sdpMid,
        sdpMLineIndex: sdpMLineIndex,
      );
    }
  }

  Future<void> _connectVoiceSignaling({
    required String serverId,
    required String channelId,
  }) async {
    final existing = _voiceSignalClient;
    final switchingVoiceChannel = existing != null &&
        (existing.serverId != serverId || existing.channelId != channelId);
    if (switchingVoiceChannel) {
      await _disposeVoiceTransport();
    }
    if (existing != null &&
        existing.serverId == serverId &&
        existing.channelId == channelId &&
        existing.isConnected) {
      return;
    }
    await _disconnectVoiceSignaling();
    final client = VoiceSignalClient(
      baseUrl: widget.baseUrl,
      accessToken: widget.session.accessToken,
      serverId: serverId,
      channelId: channelId,
    );
    _voiceSignalClient = client;
    _voiceSignalStatus = 'connecting';
    if (mounted) {
      setState(() {});
    }
    _voiceSignalEventSubscription = client.events.listen((event) {
      unawaited(_handleVoiceSignalEvent(event));
    });
    _voiceSignalStatusSubscription = client.statusMessages.listen((status) {
      if (!mounted) {
        return;
      }
      setState(() {
        _voiceSignalStatus = status;
        if (status == 'connecting' ||
            status == 'disconnected' ||
            status.startsWith('error')) {
          _voiceLatencyMs = null;
        }
      });
      if (status == 'connected' || status == 'reconnected') {
        _clearVoiceReconnect();
      }
      if ((status == 'disconnected' || status.startsWith('error')) &&
          _voiceAutoReconnectEnabled &&
          _connectedVoiceServerId != null &&
          _connectedVoiceChannelId != null) {
        _scheduleVoiceReconnect(
          serverId: _connectedVoiceServerId!,
          channelId: _connectedVoiceChannelId!,
        );
      }
    });
    _voiceLatencySubscription = client.latencyMs.listen((latencyMs) {
      if (!mounted) {
        return;
      }
      setState(() {
        _voiceLatencyMs = latencyMs;
      });
    });
    try {
      await client.connect();
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _voiceSignalStatus = 'error';
      });
    }
  }

  Future<void> _disconnectVoiceSignaling() async {
    await _voiceSignalEventSubscription?.cancel();
    await _voiceSignalStatusSubscription?.cancel();
    await _voiceLatencySubscription?.cancel();
    _voiceSignalEventSubscription = null;
    _voiceSignalStatusSubscription = null;
    _voiceLatencySubscription = null;
    final client = _voiceSignalClient;
    _voiceSignalClient = null;
    if (client != null) {
      await client.dispose();
    }
    if (mounted) {
      setState(() {
        _voiceSignalStatus = 'idle';
        _voiceLatencyMs = null;
      });
    }
  }

  Future<void> _playVoiceFeedback({
    required bool joinLeave,
  }) async {
    final enabled = joinLeave
        ? _voiceSettings.playJoinLeaveSound
        : _voiceSettings.playMuteDeafenSound;
    if (!enabled) {
      return;
    }
    try {
      await SystemSound.play(
        joinLeave ? SystemSoundType.alert : SystemSoundType.click,
      );
    } catch (_) {
      // Some desktop environments do not expose system sound playback.
    }
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
      final users = await _fetchSidebarUsers();

      if (!mounted) {
        return;
      }

      setState(() {
        _currentUserSettings = me;
        _servers = servers;
        _users = users;
        _selectedServerId = servers.isNotEmpty ? servers.first.id : null;
        _selectedChannelId = null;
        _selectedDmChannelId = null;
        _selectedUserId = null;
        _loading = false;
      });

      if (_selectedServerId != null) {
        await _loadServerChannels(serverId: _selectedServerId!);
      } else {
        _voiceAutoReconnectEnabled = false;
        _clearVoiceReconnect();
        await _disconnectVoiceSignaling();
        await _disposeVoiceTransport();
        _setMessageContextKey('none');
        if (!mounted) {
          return;
        }
        setState(() {
          _messages = const [];
          _serverMembers = const [];
          _onlineServerMemberUserIds = <String>{};
          _voiceChannels = const [];
          _voiceStates = const [];
          _connectedVoiceServerId = null;
          _connectedVoiceChannelId = null;
          _connectedVoiceChannelName = null;
          _setVoiceConnectedAt(null);
          _voiceLatencyMs = null;
          _selfVoiceMuted = false;
          _selfVoiceDeafened = false;
        });
      }
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = _t('failed_load_backend_data', 'Failed to load backend data.');
        _loading = false;
      });
    }
  }

  Future<void> _loadServerChannels({
    required String serverId,
    String? preferredChannelId,
  }) async {
    try {
      final channels = await _client.listServerChannels(
        accessToken: widget.session.accessToken,
        serverId: serverId,
      );
      final sortedChannels = channels.toList(growable: false)
        ..sort((left, right) => left.position.compareTo(right.position));
      final onlyText = sortedChannels
          .where((channel) => channel.kind == 'text')
          .toList(growable: false);
      final onlyVoice = sortedChannels
          .where((channel) => channel.kind == 'voice')
          .toList(growable: false);
      final selected = preferredChannelId ??
          (onlyText.isNotEmpty ? onlyText.first.id : null);
      var shouldDisconnectVoice = false;
      setState(() {
        _selectedServerId = serverId;
        _channels = onlyText;
        _voiceChannels = onlyVoice;
        _selectedChannelId = selected;
        if (_connectedVoiceServerId == serverId && _connectedVoiceChannelId != null) {
          String? refreshedChannelName;
          for (final channel in onlyVoice) {
            if (channel.id == _connectedVoiceChannelId) {
              refreshedChannelName = channel.name;
              break;
            }
          }
          _connectedVoiceChannelName = refreshedChannelName;
        }
        if (_connectedVoiceServerId == serverId &&
            _connectedVoiceChannelId != null &&
            !onlyVoice
                .any((channel) => channel.id == _connectedVoiceChannelId)) {
          shouldDisconnectVoice = true;
          _connectedVoiceServerId = null;
          _connectedVoiceChannelId = null;
          _connectedVoiceChannelName = null;
          _setVoiceConnectedAt(null);
          _voiceLatencyMs = null;
          _voiceStates = const [];
          _selfVoiceMuted = false;
          _selfVoiceDeafened = false;
        }
      });
      if (shouldDisconnectVoice) {
        _voiceAutoReconnectEnabled = false;
        _clearVoiceReconnect();
        await _disconnectVoiceSignaling();
        await _disposeVoiceTransport();
      }
      await _loadServerMembers(serverId: serverId);
      await _loadVoiceSession(serverId: serverId);
      if (selected != null) {
        await _loadServerMessages(serverId: serverId, channelId: selected);
      } else {
        _setMessageContextKey('none');
        setState(() {
          _messages = const [];
        });
      }
    } on ApiException catch (error) {
      setState(() {
        _error = error.message;
      });
    } catch (_) {
      setState(() {
        _error = _t('failed_load_channels', 'Failed to load channels.');
      });
    }
  }

  Future<void> _loadServerMessages({
    required String serverId,
    required String channelId,
  }) async {
    _setMessageContextKey('server:$serverId:$channelId');
    setState(() {
      _loadingMessages = true;
      _error = null;
      _selectedDmChannelId = null;
    });
    try {
      final messages = await _client.listServerChannelMessages(
        accessToken: widget.session.accessToken,
        serverId: serverId,
        channelId: channelId,
      );
      setState(() {
        _messages = messages;
        _loadingMessages = false;
      });
    } on ApiException catch (error) {
      setState(() {
        _error = error.message;
        _loadingMessages = false;
      });
    } catch (_) {
      setState(() {
        _error = _t(
          'failed_load_server_messages',
          'Failed to load server messages.',
        );
        _loadingMessages = false;
      });
    }
  }

  Future<void> _loadServerMembers({
    required String serverId,
  }) async {
    setState(() {
      _loadingServerMembers = true;
      _serverMembersError = null;
    });
    try {
      final members = await _client.listServerMembers(
        accessToken: widget.session.accessToken,
        serverId: serverId,
      );
      final online = await _client.listServerOnlineMembers(
        accessToken: widget.session.accessToken,
        serverId: serverId,
      );
      members.sort((left, right) {
        final roleRank = (String role) {
          if (role == 'owner') {
            return 0;
          }
          if (role == 'admin') {
            return 1;
          }
          return 2;
        };
        final byRole = roleRank(left.role).compareTo(roleRank(right.role));
        if (byRole != 0) {
          return byRole;
        }
        return left.handle.toLowerCase().compareTo(right.handle.toLowerCase());
      });
      setState(() {
        _serverMembers = members;
        final onlineIds = online.onlineUserIds.toSet();
        final hasSelfMember =
            members.any((member) => member.userId == widget.session.userId);
        if (hasSelfMember) {
          onlineIds.add(widget.session.userId);
        }
        _onlineServerMemberUserIds = onlineIds;
        _loadingServerMembers = false;
      });
    } on ApiException catch (error) {
      setState(() {
        _serverMembersError = error.message;
        _loadingServerMembers = false;
      });
    } catch (_) {
      setState(() {
        _serverMembersError = _t(
          'failed_load_server_members',
          'Failed to load server members.',
        );
        _loadingServerMembers = false;
      });
    }
  }

  Future<void> _loadVoiceSession({
    required String serverId,
  }) async {
    try {
      final myState = await _client.getMyVoiceState(
        accessToken: widget.session.accessToken,
        serverId: serverId,
      );
      if (!mounted || _selectedServerId != serverId) {
        return;
      }

      if (myState == null) {
        if (_connectedVoiceServerId == serverId) {
          _voiceAutoReconnectEnabled = false;
          _clearVoiceReconnect();
          await _disconnectVoiceSignaling();
          await _disposeVoiceTransport();
          setState(() {
            _connectedVoiceServerId = null;
            _connectedVoiceChannelId = null;
            _connectedVoiceChannelName = null;
            _setVoiceConnectedAt(null);
            _voiceLatencyMs = null;
            _voiceStates = const [];
            _selfVoiceMuted = false;
            _selfVoiceDeafened = false;
          });
        }
        return;
      }

      final voiceStates = await _client.listVoiceStates(
        accessToken: widget.session.accessToken,
        serverId: serverId,
        channelId: myState.channelId,
      );
      if (!mounted || _selectedServerId != serverId) {
        return;
      }
      String? connectedChannelName;
      for (final channel in _voiceChannels) {
        if (channel.id == myState.channelId) {
          connectedChannelName = channel.name;
          break;
        }
      }
      setState(() {
        _connectedVoiceServerId = serverId;
        _connectedVoiceChannelId = myState.channelId;
        _connectedVoiceChannelName = connectedChannelName;
        _setVoiceConnectedAt(myState.joinedAt);
        _selfVoiceMuted = myState.muted;
        _selfVoiceDeafened = myState.deafened;
        _voiceStates = voiceStates;
      });
      _voiceAutoReconnectEnabled = true;
      await _connectVoiceSignaling(
        serverId: serverId,
        channelId: myState.channelId,
      );
      await _configureVoiceTransport(channelId: myState.channelId);
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
    }
  }

  Future<void> _joinVoiceChannel(String channelId) async {
    if (_voiceBusy || _selectedServerId == null) {
      return;
    }
    final serverId = _selectedServerId!;
    final isFreshJoin = _connectedVoiceChannelId == null;
    var nextMuted = _selfVoiceMuted;
    var nextDeafened = _selfVoiceDeafened;
    if (isFreshJoin) {
      nextMuted = _voiceSettings.startMutedOnJoin;
      nextDeafened = _voiceSettings.startDeafenedOnJoin;
      if (nextDeafened) {
        nextMuted = true;
      }
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
        channelId: channelId,
      );
      await _playVoiceFeedback(joinLeave: true);
      if (!mounted) {
        return;
      }
      String? connectedChannelName;
      for (final channel in _voiceChannels) {
        if (channel.id == state.channelId) {
          connectedChannelName = channel.name;
          break;
        }
      }
      setState(() {
        _connectedVoiceServerId = serverId;
        _connectedVoiceChannelId = state.channelId;
        _connectedVoiceChannelName = connectedChannelName;
        _setVoiceConnectedAt(state.joinedAt);
        _selfVoiceMuted = state.muted;
        _selfVoiceDeafened = state.deafened;
        _voiceStates = participants;
        _voiceBusy = false;
      });
      _voiceAutoReconnectEnabled = true;
      _clearVoiceReconnect();
      await _connectVoiceSignaling(
        serverId: serverId,
        channelId: state.channelId,
      );
      await _configureVoiceTransport(channelId: state.channelId);
      await _voiceSignalClient?.sendSignal(
        signalType: 'join',
        data: {
          'target_user_id': '',
          'muted': state.muted,
          'deafened': state.deafened,
        },
      );
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _voiceBusy = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _voiceBusy = false;
        _error = _t('failed_join_voice', 'Failed to join voice channel.');
      });
    }
  }

  Future<void> _leaveVoiceChannel() async {
    final serverId = _connectedVoiceServerId ?? _selectedServerId;
    final channelId = _connectedVoiceChannelId;
    if (_voiceBusy || serverId == null || channelId == null) {
      return;
    }
    setState(() {
      _voiceBusy = true;
      _error = null;
    });
    try {
      _voiceAutoReconnectEnabled = false;
      _clearVoiceReconnect();
      await _voiceSignalClient?.sendSignal(
        signalType: 'leave',
        data: const {'target_user_id': ''},
      );
      await _client.leaveVoiceState(
        accessToken: widget.session.accessToken,
        serverId: serverId,
        channelId: channelId,
      );
      await _disconnectVoiceSignaling();
      await _disposeVoiceTransport();
      await _playVoiceFeedback(joinLeave: true);
      if (!mounted) {
        return;
      }
      setState(() {
        _connectedVoiceServerId = null;
        _connectedVoiceChannelId = null;
        _connectedVoiceChannelName = null;
        _setVoiceConnectedAt(null);
        _voiceLatencyMs = null;
        _voiceStates = const [];
        _selfVoiceMuted = false;
        _selfVoiceDeafened = false;
        _voiceBusy = false;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _voiceBusy = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _voiceBusy = false;
        _error = _t('failed_leave_voice', 'Failed to leave voice channel.');
      });
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

    setState(() {
      _voiceBusy = true;
      _error = null;
    });
    try {
      final previousMuted = _selfVoiceMuted;
      final previousDeafened = _selfVoiceDeafened;
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
      final voiceToggled =
          state.muted != previousMuted || state.deafened != previousDeafened;
      if (voiceToggled) {
        await _playVoiceFeedback(joinLeave: false);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _selfVoiceMuted = state.muted;
        _selfVoiceDeafened = state.deafened;
        _voiceStates = participants;
        _voiceBusy = false;
      });
      await _voiceTransport?.setMuted(state.muted || state.deafened);
      await _voiceSignalClient?.sendSignal(
        signalType: 'state_update',
        data: {
          'target_user_id': '',
          'muted': state.muted,
          'deafened': state.deafened,
        },
      );
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _voiceBusy = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _voiceBusy = false;
        _error = _t('failed_update_voice', 'Failed to update voice state.');
      });
    }
  }

  Future<void> _openDmAndLoadMessages(String userId) async {
    setState(() {
      _loadingMessages = true;
      _error = null;
      _selectedUserId = userId;
    });
    try {
      final dm = await _client.openDirectMessage(
        accessToken: widget.session.accessToken,
        peerUserId: userId,
      );
      _setMessageContextKey('dm:${dm.channelId}');
      final messages = await _client.listDirectMessageMessages(
        accessToken: widget.session.accessToken,
        channelId: dm.channelId,
      );
      setState(() {
        _selectedDmChannelId = dm.channelId;
        _selectedServerId = null;
        _selectedChannelId = null;
        _serverMembers = const [];
        _serverMembersError = null;
        _messages = messages;
        _loadingMessages = false;
      });
    } on ApiException catch (error) {
      setState(() {
        _error = error.message;
        _loadingMessages = false;
      });
    } catch (_) {
      setState(() {
        _error = _t('failed_open_dm', 'Failed to open DM.');
        _loadingMessages = false;
      });
    }
  }

  Future<void> _sendMessage() async {
    final text = _composerController.text.trim();
    final pendingImage = _pendingImageFile;
    final hasImage = pendingImage != null;
    final hasDestination = _selectedDmChannelId != null ||
        (_selectedServerId != null && _selectedChannelId != null);
    if ((text.isEmpty && !hasImage) || _sending) {
      return;
    }
    if (!hasDestination) {
      setState(() {
        _error = _t(
          'select_destination_first',
          'Select a server channel or DM first.',
        );
      });
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      ApiImageUploadResult? uploadedImage;
      if (pendingImage != null) {
        uploadedImage = await _uploadImageFile(pendingImage);
      }

      final dmChannelId = _selectedDmChannelId;
      if (dmChannelId != null) {
        await _client.sendDirectMessage(
          accessToken: widget.session.accessToken,
          channelId: dmChannelId,
          content: text.isEmpty ? null : text,
          imageUrl: uploadedImage?.imageUrl,
          imageObjectKey: uploadedImage?.imageObjectKey,
        );
        final messages = await _client.listDirectMessageMessages(
          accessToken: widget.session.accessToken,
          channelId: dmChannelId,
        );
        setState(() {
          _messages = messages;
        });
      } else if (_selectedServerId != null && _selectedChannelId != null) {
        await _client.sendServerChannelMessage(
          accessToken: widget.session.accessToken,
          serverId: _selectedServerId!,
          channelId: _selectedChannelId!,
          content: text.isEmpty ? null : text,
          imageUrl: uploadedImage?.imageUrl,
          imageObjectKey: uploadedImage?.imageObjectKey,
        );
        final messages = await _client.listServerChannelMessages(
          accessToken: widget.session.accessToken,
          serverId: _selectedServerId!,
          channelId: _selectedChannelId!,
        );
        setState(() {
          _messages = messages;
        });
      }

      _composerController.clear();
      _clearPendingImage();
    } on ApiException catch (error) {
      setState(() {
        _error = error.message;
      });
    } catch (_) {
      setState(() {
        _error = _t('failed_send_message', 'Failed to send message.');
      });
    } finally {
      setState(() {
        _sending = false;
      });
    }
  }

  Future<void> _reloadCurrentMessages() async {
    final dmChannelId = _selectedDmChannelId;
    if (dmChannelId != null) {
      final messages = await _client.listDirectMessageMessages(
        accessToken: widget.session.accessToken,
        channelId: dmChannelId,
      );
      setState(() {
        _messages = messages;
      });
      return;
    }
    if (_selectedServerId != null && _selectedChannelId != null) {
      final messages = await _client.listServerChannelMessages(
        accessToken: widget.session.accessToken,
        serverId: _selectedServerId!,
        channelId: _selectedChannelId!,
      );
      setState(() {
        _messages = messages;
      });
    }
  }

  Future<void> _pickImageForMessage() async {
    if (_sending) {
      return;
    }
    try {
      final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (picked == null) {
        return;
      }
      final bytes = await picked.readAsBytes();
      setState(() {
        _pendingImageFile = picked;
        _pendingImageBytes = bytes;
      });
    } on ApiException catch (error) {
      setState(() {
        _error = error.message;
      });
    } catch (_) {
      setState(() {
        _error = _t('failed_pick_image', 'Failed to pick image.');
      });
    }
  }

  void _clearPendingImage() {
    setState(() {
      _pendingImageFile = null;
      _pendingImageBytes = null;
    });
  }

  Future<ApiImageUploadResult> _uploadImageFile(XFile file) async {
    final extensionFromName = _extensionFromFilename(file.name);
    final extension = extensionFromName.isEmpty
        ? _extensionFromFilename(file.path)
        : extensionFromName;
    final contentType = _contentTypeForExtension(extension);
    final bytes = await file.readAsBytes();
    return _client.uploadImageDirect(
      accessToken: widget.session.accessToken,
      contentType: contentType,
      fileExtension: extension.isEmpty ? null : extension,
      data: bytes,
    );
  }

  Future<void> _showCreateServerDialog() async {
    if (_runningAction) {
      return;
    }

    final strings = _strings();
    final nameController = TextEditingController();
    final serverName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            strings.t('create_server_title', fallback: 'Create Server'),
          ),
          content: TextField(
            controller: nameController,
            autofocus: true,
            decoration: InputDecoration(
              labelText: strings.t('server_name', fallback: 'Server Name'),
              hintText: strings.t('server_name_hint', fallback: 'My Server'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(strings.t('cancel', fallback: 'Cancel')),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(nameController.text.trim()),
              child: Text(strings.t('create', fallback: 'Create')),
            ),
          ],
        );
      },
    );
    nameController.dispose();

    if (serverName == null || serverName.isEmpty) {
      return;
    }

    setState(() {
      _runningAction = true;
      _error = null;
    });
    try {
      final createdServer = await _client.createServer(
        accessToken: widget.session.accessToken,
        name: serverName,
      );
      final servers =
          await _client.listServers(accessToken: widget.session.accessToken);
      final mergedServers = _mergeServerIntoList(servers, createdServer);
      setState(() {
        _servers = mergedServers;
        _sidebarMode = _SidebarMode.servers;
        _selectedServerId = createdServer.id;
        _selectedUserId = null;
      });
      await _scrollServerRailToTop();
      await _loadServerChannels(serverId: createdServer.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              strings.tf(
                'server_created',
                {'name': serverName},
                fallback: 'Server "{name}" created.',
              ),
            ),
          ),
        );
      }
    } on ApiException catch (error) {
      setState(() {
        _error = error.message;
      });
    } catch (_) {
      setState(() {
        _error = _t('failed_create_server', 'Failed to create server.');
      });
    } finally {
      setState(() {
        _runningAction = false;
      });
    }
  }

  Future<void> _showJoinServerDialog() async {
    if (_runningAction) {
      return;
    }

    final strings = _strings();
    final inviteController = TextEditingController();
    final inviteCode = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            strings.t('join_server_title', fallback: 'Join Server'),
          ),
          content: TextField(
            controller: inviteController,
            autofocus: true,
            decoration: InputDecoration(
              labelText: strings.t('invite_code', fallback: 'Invite Code'),
              hintText: strings.t('invite_code_hint', fallback: 'abc123xyz'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(strings.t('cancel', fallback: 'Cancel')),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(inviteController.text.trim()),
              child: Text(strings.t('join', fallback: 'Join')),
            ),
          ],
        );
      },
    );
    inviteController.dispose();

    if (inviteCode == null || inviteCode.isEmpty) {
      return;
    }

    setState(() {
      _runningAction = true;
      _error = null;
    });
    try {
      final joinedServer = await _client.joinServerByInvite(
        accessToken: widget.session.accessToken,
        code: inviteCode,
      );
      final servers =
          await _client.listServers(accessToken: widget.session.accessToken);
      final mergedServers = _mergeServerIntoList(servers, joinedServer);
      setState(() {
        _servers = mergedServers;
        _sidebarMode = _SidebarMode.servers;
        _selectedServerId = joinedServer.id;
        _selectedUserId = null;
      });
      await _scrollServerRailToTop();
      await _loadServerChannels(serverId: joinedServer.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              strings.tf(
                'joined_server',
                {'name': joinedServer.name},
                fallback: 'Joined "{name}".',
              ),
            ),
          ),
        );
      }
    } on ApiException catch (error) {
      setState(() {
        _error = error.message;
      });
    } catch (_) {
      setState(() {
        _error = _t('failed_join_server', 'Failed to join server.');
      });
    } finally {
      setState(() {
        _runningAction = false;
      });
    }
  }

  Future<void> _showCreateChannelDialog() async {
    if (_runningAction || _selectedServerId == null) {
      return;
    }

    final strings = _strings();
    final nameController = TextEditingController();
    var selectedKind = 'text';
    final channelName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                strings.t('create_channel_title', fallback: 'Create Channel'),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText:
                          strings.t('channel_name', fallback: 'Channel Name'),
                      hintText: strings.t(
                        'channel_name_hint',
                        fallback: 'general-chat',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey('channel-kind-$selectedKind'),
                    initialValue: selectedKind,
                    decoration: InputDecoration(
                      labelText:
                          strings.t('channel_kind', fallback: 'Channel Type'),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'text',
                        child: Text(
                          strings.t('channel_kind_text', fallback: 'Text'),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'voice',
                        child: Text(
                          strings.t('channel_kind_voice', fallback: 'Voice'),
                        ),
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
                  child: Text(strings.t('cancel', fallback: 'Cancel')),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext)
                      .pop(nameController.text.trim()),
                  child: Text(strings.t('create', fallback: 'Create')),
                ),
              ],
            );
          },
        );
      },
    );
    nameController.dispose();

    if (channelName == null || channelName.isEmpty) {
      return;
    }

    setState(() {
      _runningAction = true;
      _error = null;
    });
    try {
      final created = await _client.createServerChannel(
        accessToken: widget.session.accessToken,
        serverId: _selectedServerId!,
        name: channelName,
        kind: selectedKind,
      );
      await _loadServerChannels(
        serverId: _selectedServerId!,
        preferredChannelId: created.kind == 'text' ? created.id : null,
      );
      if (created.kind == 'voice') {
        await _joinVoiceChannel(created.id);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              strings.tf(
                'channel_created',
                {'name': created.name},
                fallback: 'Channel #{name} created.',
              ),
            ),
          ),
        );
      }
    } on ApiException catch (error) {
      setState(() {
        _error = error.message;
      });
    } catch (_) {
      setState(() {
        _error = _t('failed_create_channel', 'Failed to create channel.');
      });
    } finally {
      setState(() {
        _runningAction = false;
      });
    }
  }

  Future<void> _deleteChannel(ApiChannelSummary channel) async {
    if (_runningAction || _selectedServerId == null) {
      return;
    }
    final strings = _strings();
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: Text(
                strings.t('delete_channel', fallback: 'Delete Channel'),
              ),
              content: Text(
                strings.tf(
                  'delete_channel_confirm',
                  {'name': channel.name},
                  fallback: 'Delete channel "{name}"?',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(strings.t('cancel', fallback: 'Cancel')),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(strings.t('delete', fallback: 'Delete')),
                ),
              ],
            );
          },
        ) ??
        false;
    if (!confirmed) {
      return;
    }

    setState(() {
      _runningAction = true;
      _error = null;
    });
    try {
      await _client.deleteServerChannel(
        accessToken: widget.session.accessToken,
        serverId: _selectedServerId!,
        channelId: channel.id,
      );
      await _loadServerChannels(serverId: _selectedServerId!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              strings.tf(
                'channel_deleted',
                {'name': channel.name},
                fallback: 'Channel #{name} deleted.',
              ),
            ),
          ),
        );
      }
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
        _error = strings.t(
          'failed_delete_channel',
          fallback: 'Failed to delete channel.',
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _runningAction = false;
        });
      }
    }
  }

  Future<void> _openServerSettingsScreen() async {
    if (_runningAction || _selectedServerId == null) {
      return;
    }
    final selectedServerId = _selectedServerId!;
    final result =
        await Navigator.of(context).push<BackendServerSettingsResult>(
      MaterialPageRoute(
        builder: (_) => BackendServerSettingsScreen(
          baseUrl: widget.baseUrl,
          session: widget.session,
          serverId: selectedServerId,
        ),
      ),
    );
    if (result == null || !result.didChange) {
      return;
    }

    setState(() {
      _runningAction = true;
      _error = null;
    });
    try {
      final servers =
          await _client.listServers(accessToken: widget.session.accessToken);
      String? nextSelected;
      if (!result.wasDeleted &&
          servers.any((server) => server.id == selectedServerId)) {
        nextSelected = selectedServerId;
      } else if (servers.isNotEmpty) {
        nextSelected = servers.first.id;
      }
      setState(() {
        _servers = servers;
        _selectedServerId = nextSelected;
        _sidebarMode = _SidebarMode.servers;
        _selectedDmChannelId = null;
      });

      if (nextSelected != null) {
        await _loadServerChannels(serverId: nextSelected);
      } else {
        await _disconnectVoiceSignaling();
        await _disposeVoiceTransport();
        _setMessageContextKey('none');
        setState(() {
          _channels = const [];
          _voiceChannels = const [];
          _voiceStates = const [];
          _messages = const [];
          _serverMembers = const [];
          _onlineServerMemberUserIds = <String>{};
          _serverMembersError = null;
          _selectedChannelId = null;
          _selectedUserId = null;
          _connectedVoiceServerId = null;
          _connectedVoiceChannelId = null;
          _connectedVoiceChannelName = null;
          _setVoiceConnectedAt(null);
          _voiceLatencyMs = null;
          _selfVoiceMuted = false;
          _selfVoiceDeafened = false;
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.wasDeleted
                  ? _t('server_deleted', 'Server deleted.')
                  : _t(
                      'server_settings_updated',
                      'Server settings updated.',
                    ),
            ),
          ),
        );
      }
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
        _error = _t(
          'failed_update_server_settings',
          'Failed to update server settings.',
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _runningAction = false;
        });
      }
    }
  }

  Future<void> _showAddFriendDialog() async {
    if (_runningAction) {
      return;
    }

    final strings = _strings();
    final handleController = TextEditingController();
    final handle = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(strings.t('add_friend', fallback: 'Add Friend')),
          content: TextField(
            controller: handleController,
            autofocus: true,
            decoration: InputDecoration(
              labelText: strings.t('handle', fallback: 'Handle'),
              hintText: strings.t(
                'identifier_hint',
                fallback: 'username#0001',
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(strings.t('cancel', fallback: 'Cancel')),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(handleController.text.trim()),
              child: Text(strings.t('add', fallback: 'Add')),
            ),
          ],
        );
      },
    );
    handleController.dispose();

    if (handle == null || handle.isEmpty) {
      return;
    }

    setState(() {
      _runningAction = true;
      _error = null;
    });
    try {
      final friend = await _client.addFriend(
        accessToken: widget.session.accessToken,
        handle: handle,
      );
      final users = await _fetchSidebarUsers();
      setState(() {
        _users = users;
        _sidebarMode = _SidebarMode.users;
      });
      await _openDmAndLoadMessages(friend.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              strings.tf(
                'added_friend',
                {'handle': friend.handle},
                fallback: 'Added {handle}.',
              ),
            ),
          ),
        );
      }
    } on ApiException catch (error) {
      setState(() {
        _error = error.message;
      });
    } catch (_) {
      setState(() {
        _error = _t('failed_add_friend', 'Failed to add friend.');
      });
    } finally {
      setState(() {
        _runningAction = false;
      });
    }
  }

  Future<void> _openUserSettingsScreen() async {
    if (_runningAction) {
      return;
    }

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
      await _loadVoiceSettings();
      if (!mounted) {
        return;
      }
      await _bootstrap();
    }
  }

  Future<void> _showEditMessageDialog(ApiChatMessage message) async {
    if (!_isOwnMessage(message) || message.deletedAt != null) {
      return;
    }

    final strings = _strings();
    final controller = TextEditingController(text: message.content ?? '');
    final edited = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(strings.t('edit_message', fallback: 'Edit Message')),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 1,
            maxLines: 6,
            decoration: InputDecoration(
              labelText: strings.t('message', fallback: 'Message'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(strings.t('cancel', fallback: 'Cancel')),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: Text(strings.t('save', fallback: 'Save')),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (edited == null) {
      return;
    }
    if (edited.isEmpty) {
      setState(() {
        _error = _t('edited_message_empty', 'Edited message cannot be empty.');
      });
      return;
    }

    setState(() {
      _runningAction = true;
      _error = null;
    });
    try {
      if (_selectedDmChannelId != null) {
        await _client.editDirectMessage(
          accessToken: widget.session.accessToken,
          channelId: _selectedDmChannelId!,
          messageId: message.messageId,
          content: edited,
        );
      } else if (_selectedServerId != null && _selectedChannelId != null) {
        await _client.editServerChannelMessage(
          accessToken: widget.session.accessToken,
          serverId: _selectedServerId!,
          channelId: _selectedChannelId!,
          messageId: message.messageId,
          content: edited,
        );
      }
      await _reloadCurrentMessages();
    } on ApiException catch (error) {
      setState(() {
        _error = error.message;
      });
    } catch (_) {
      setState(() {
        _error = _t('failed_edit_message', 'Failed to edit message.');
      });
    } finally {
      setState(() {
        _runningAction = false;
      });
    }
  }

  Future<void> _deleteMessage(ApiChatMessage message) async {
    if (!_isOwnMessage(message) || message.deletedAt != null) {
      return;
    }

    final strings = _strings();
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: Text(
                strings.t('delete_message', fallback: 'Delete Message'),
              ),
              content: Text(
                strings.t(
                  'delete_message_confirm',
                  fallback: 'Delete this message?',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(strings.t('cancel', fallback: 'Cancel')),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(strings.t('delete', fallback: 'Delete')),
                ),
              ],
            );
          },
        ) ??
        false;
    if (!confirmed) {
      return;
    }

    setState(() {
      _runningAction = true;
      _error = null;
    });
    try {
      if (_selectedDmChannelId != null) {
        await _client.deleteDirectMessage(
          accessToken: widget.session.accessToken,
          channelId: _selectedDmChannelId!,
          messageId: message.messageId,
        );
      } else if (_selectedServerId != null && _selectedChannelId != null) {
        await _client.deleteServerChannelMessage(
          accessToken: widget.session.accessToken,
          serverId: _selectedServerId!,
          channelId: _selectedChannelId!,
          messageId: message.messageId,
        );
      }
      await _reloadCurrentMessages();
    } on ApiException catch (error) {
      setState(() {
        _error = error.message;
      });
    } catch (_) {
      setState(() {
        _error = _t('failed_delete_message', 'Failed to delete message.');
      });
    } finally {
      setState(() {
        _runningAction = false;
      });
    }
  }

  Future<void> _showServerMembersDialog() async {
    if (_selectedServerId == null) {
      return;
    }
    final serverId = _selectedServerId!;
    final strings = _strings();
    List<ApiServerMember> members = const [];
    String? dialogError;
    bool loading = true;
    String? busyUserId;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        Future<void> loadMembers(StateSetter setDialogState) async {
          try {
            final loaded = await _client.listServerMembers(
              accessToken: widget.session.accessToken,
              serverId: serverId,
            );
            setDialogState(() {
              members = loaded;
              loading = false;
              dialogError = null;
            });
          } on ApiException catch (error) {
            setDialogState(() {
              loading = false;
              dialogError = error.message;
            });
          } catch (_) {
            setDialogState(() {
              loading = false;
              dialogError = strings.t(
                'failed_load_members',
                fallback: 'Failed to load members.',
              );
            });
          }
        }

        return StatefulBuilder(
          builder: (context, setDialogState) {
            if (loading && members.isEmpty && dialogError == null) {
              loadMembers(setDialogState);
            }
            return AlertDialog(
              title: Text(
                strings.t('server_members', fallback: 'Server Members'),
              ),
              content: SizedBox(
                width: 560,
                height: 420,
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : Column(
                        children: [
                          if (dialogError != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                dialogError!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          Expanded(
                            child: ListView.builder(
                              itemCount: members.length,
                              itemBuilder: (context, index) {
                                final member = members[index];
                                return ListTile(
                                  leading: const Icon(Icons.person_outline),
                                  title: Text(member.handle),
                                  subtitle: Text(
                                    '${member.displayName ?? member.username} - ${_roleLabel(member.role)}',
                                  ),
                                  trailing: busyUserId == member.userId
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : PopupMenuButton<String>(
                                          onSelected: (value) async {
                                            setDialogState(() {
                                              busyUserId = member.userId;
                                              dialogError = null;
                                            });
                                            try {
                                              if (value == 'set_admin') {
                                                await _client
                                                    .updateServerMemberRole(
                                                  accessToken: widget
                                                      .session.accessToken,
                                                  serverId: serverId,
                                                  memberUserId: member.userId,
                                                  role: 'admin',
                                                );
                                              } else if (value ==
                                                  'set_member') {
                                                await _client
                                                    .updateServerMemberRole(
                                                  accessToken: widget
                                                      .session.accessToken,
                                                  serverId: serverId,
                                                  memberUserId: member.userId,
                                                  role: 'member',
                                                );
                                              } else if (value == 'kick') {
                                                await _client.kickServerMember(
                                                  accessToken: widget
                                                      .session.accessToken,
                                                  serverId: serverId,
                                                  memberUserId: member.userId,
                                                );
                                              } else if (value == 'ban') {
                                                await _client.banServerUser(
                                                  accessToken: widget
                                                      .session.accessToken,
                                                  serverId: serverId,
                                                  targetUserId: member.userId,
                                                );
                                              }
                                              final refreshed = await _client
                                                  .listServerMembers(
                                                accessToken:
                                                    widget.session.accessToken,
                                                serverId: serverId,
                                              );
                                              setDialogState(() {
                                                members = refreshed;
                                                busyUserId = null;
                                              });
                                            } on ApiException catch (error) {
                                              setDialogState(() {
                                                busyUserId = null;
                                                dialogError = error.message;
                                              });
                                            } catch (_) {
                                              setDialogState(() {
                                                busyUserId = null;
                                                dialogError = strings.t(
                                                  'failed_member_action',
                                                  fallback:
                                                      'Failed member action.',
                                                );
                                              });
                                            }
                                          },
                                          itemBuilder: (context) => [
                                            if (member.role != 'owner')
                                              PopupMenuItem<String>(
                                                value: 'set_admin',
                                                child: Text(
                                                  strings.t(
                                                    'set_as_admin',
                                                    fallback: 'Set as Admin',
                                                  ),
                                                ),
                                              ),
                                            if (member.role == 'admin')
                                              PopupMenuItem<String>(
                                                value: 'set_member',
                                                child: Text(
                                                  strings.t(
                                                    'set_as_member',
                                                    fallback: 'Set as Member',
                                                  ),
                                                ),
                                              ),
                                            if (member.role != 'owner')
                                              PopupMenuItem<String>(
                                                value: 'kick',
                                                child: Text(
                                                  strings.t(
                                                    'kick',
                                                    fallback: 'Kick',
                                                  ),
                                                ),
                                              ),
                                            if (member.role != 'owner')
                                              PopupMenuItem<String>(
                                                value: 'ban',
                                                child: Text(
                                                  strings.t(
                                                    'ban',
                                                    fallback: 'Ban',
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(strings.t('close', fallback: 'Close')),
                ),
              ],
            );
          },
        );
      },
    );

    if (mounted && _selectedServerId == serverId) {
      await _loadServerMembers(serverId: serverId);
    }
  }

  Future<void> _showServerBansDialog() async {
    if (_selectedServerId == null) {
      return;
    }
    final serverId = _selectedServerId!;
    final strings = _strings();
    List<ApiServerBan> bans = const [];
    String? dialogError;
    bool loading = true;
    String? busyUserId;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        Future<void> loadBans(StateSetter setDialogState) async {
          try {
            final loaded = await _client.listServerBans(
              accessToken: widget.session.accessToken,
              serverId: serverId,
            );
            setDialogState(() {
              bans = loaded;
              loading = false;
              dialogError = null;
            });
          } on ApiException catch (error) {
            setDialogState(() {
              loading = false;
              dialogError = error.message;
            });
          } catch (_) {
            setDialogState(() {
              loading = false;
              dialogError = strings.t(
                'failed_load_bans',
                fallback: 'Failed to load bans.',
              );
            });
          }
        }

        return StatefulBuilder(
          builder: (context, setDialogState) {
            if (loading && bans.isEmpty && dialogError == null) {
              loadBans(setDialogState);
            }
            return AlertDialog(
              title: Text(strings.t('server_bans', fallback: 'Server Bans')),
              content: SizedBox(
                width: 560,
                height: 360,
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : Column(
                        children: [
                          if (dialogError != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                dialogError!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          Expanded(
                            child: bans.isEmpty
                                ? Center(
                                    child: Text(
                                      strings.t(
                                        'no_banned_users',
                                        fallback: 'No banned users.',
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                                    itemCount: bans.length,
                                    itemBuilder: (context, index) {
                                      final ban = bans[index];
                                      return ListTile(
                                        title: Text(ban.userHandle),
                                        subtitle: Text(
                                          ban.reason?.isNotEmpty == true
                                              ? ban.reason!
                                              : strings.t(
                                                  'no_reason_provided',
                                                  fallback:
                                                      'No reason provided.',
                                                ),
                                        ),
                                        trailing: busyUserId == ban.userId
                                            ? const SizedBox(
                                                width: 20,
                                                height: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                ),
                                              )
                                            : TextButton(
                                                onPressed: () async {
                                                  setDialogState(() {
                                                    busyUserId = ban.userId;
                                                    dialogError = null;
                                                  });
                                                  try {
                                                    await _client
                                                        .unbanServerUser(
                                                      accessToken: widget
                                                          .session.accessToken,
                                                      serverId: serverId,
                                                      targetUserId: ban.userId,
                                                    );
                                                    final refreshed =
                                                        await _client
                                                            .listServerBans(
                                                      accessToken: widget
                                                          .session.accessToken,
                                                      serverId: serverId,
                                                    );
                                                    setDialogState(() {
                                                      bans = refreshed;
                                                      busyUserId = null;
                                                    });
                                                  } on ApiException catch (error) {
                                                    setDialogState(() {
                                                      busyUserId = null;
                                                      dialogError =
                                                          error.message;
                                                    });
                                                  } catch (_) {
                                                    setDialogState(() {
                                                      busyUserId = null;
                                                      dialogError = strings.t(
                                                        'failed_unban_user',
                                                        fallback:
                                                            'Failed to unban user.',
                                                      );
                                                    });
                                                  }
                                                },
                                                child: Text(
                                                  strings.t(
                                                    'unban',
                                                    fallback: 'Unban',
                                                  ),
                                                ),
                                              ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(strings.t('close', fallback: 'Close')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showServerInvitesDialog() async {
    if (_selectedServerId == null) {
      return;
    }
    final serverId = _selectedServerId!;
    final strings = _strings();
    final formatter = _activeDateFormatter();
    List<ApiServerInvite> invites = const [];
    String? dialogError;
    bool loading = true;
    bool busy = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        Future<void> loadInvites(StateSetter setDialogState) async {
          try {
            final loaded = await _client.listServerInvites(
              accessToken: widget.session.accessToken,
              serverId: serverId,
            );
            setDialogState(() {
              invites = loaded;
              loading = false;
              dialogError = null;
            });
          } on ApiException catch (error) {
            setDialogState(() {
              loading = false;
              dialogError = error.message;
            });
          } catch (_) {
            setDialogState(() {
              loading = false;
              dialogError = strings.t(
                'failed_load_invites',
                fallback: 'Failed to load invites.',
              );
            });
          }
        }

        return StatefulBuilder(
          builder: (context, setDialogState) {
            if (loading && invites.isEmpty && dialogError == null) {
              loadInvites(setDialogState);
            }
            return AlertDialog(
              title:
                  Text(strings.t('server_invites', fallback: 'Server Invites')),
              content: SizedBox(
                width: 600,
                height: 420,
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              FilledButton.icon(
                                onPressed: busy
                                    ? null
                                    : () async {
                                        setDialogState(() {
                                          busy = true;
                                          dialogError = null;
                                        });
                                        try {
                                          final invite =
                                              await _client.createServerInvite(
                                            accessToken:
                                                widget.session.accessToken,
                                            serverId: serverId,
                                            expiresInHours: 24,
                                          );
                                          await Clipboard.setData(
                                            ClipboardData(text: invite.code),
                                          );
                                          final refreshed =
                                              await _client.listServerInvites(
                                            accessToken:
                                                widget.session.accessToken,
                                            serverId: serverId,
                                          );
                                          setDialogState(() {
                                            invites = refreshed;
                                            busy = false;
                                          });
                                          if (mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  strings.tf(
                                                    'invite_created_and_copied',
                                                    {'code': invite.code},
                                                    fallback:
                                                        'Invite {code} created and copied.',
                                                  ),
                                                ),
                                              ),
                                            );
                                          }
                                        } on ApiException catch (error) {
                                          setDialogState(() {
                                            busy = false;
                                            dialogError = error.message;
                                          });
                                        } catch (_) {
                                          setDialogState(() {
                                            busy = false;
                                            dialogError = strings.t(
                                              'failed_create_invite',
                                              fallback:
                                                  'Failed to create invite.',
                                            );
                                          });
                                        }
                                      },
                                icon: const Icon(Icons.add_link),
                                label: Text(
                                  strings.t(
                                    'create_invite',
                                    fallback: 'Create Invite',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (dialogError != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                dialogError!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          Expanded(
                            child: invites.isEmpty
                                ? Center(
                                    child: Text(
                                      strings.t(
                                        'no_active_invites',
                                        fallback: 'No active invites.',
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                                    itemCount: invites.length,
                                    itemBuilder: (context, index) {
                                      final invite = invites[index];
                                      final expiresAt = invite.expiresAt;
                                      final expiryLabel = expiresAt == null
                                          ? strings.t(
                                              'no_expiry',
                                              fallback: 'No expiry',
                                            )
                                          : strings.tf(
                                              'expires_at',
                                              {
                                                'time': formatter.format(
                                                    expiresAt.toLocal()),
                                              },
                                              fallback: 'Expires {time}',
                                            );
                                      final maxUsesPart = invite.maxUses != null
                                          ? '/${invite.maxUses}'
                                          : '';
                                      return ListTile(
                                        title: Text(invite.code),
                                        subtitle: Text(
                                          strings.tf(
                                            'invite_uses',
                                            {
                                              'expiry': expiryLabel,
                                              'uses': '${invite.useCount}',
                                              'max': maxUsesPart,
                                            },
                                            fallback:
                                                '{expiry} - Uses {uses}{max}',
                                          ),
                                        ),
                                        trailing: PopupMenuButton<String>(
                                          onSelected: (value) async {
                                            if (value == 'copy') {
                                              await Clipboard.setData(
                                                ClipboardData(
                                                    text: invite.code),
                                              );
                                              if (mounted) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      strings.t(
                                                        'invite_code_copied',
                                                        fallback:
                                                            'Invite code copied.',
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              }
                                              return;
                                            }
                                            if (value == 'revoke') {
                                              setDialogState(() {
                                                busy = true;
                                                dialogError = null;
                                              });
                                              try {
                                                await _client
                                                    .revokeServerInvite(
                                                  accessToken: widget
                                                      .session.accessToken,
                                                  serverId: serverId,
                                                  code: invite.code,
                                                );
                                                final refreshed = await _client
                                                    .listServerInvites(
                                                  accessToken: widget
                                                      .session.accessToken,
                                                  serverId: serverId,
                                                );
                                                setDialogState(() {
                                                  invites = refreshed;
                                                  busy = false;
                                                });
                                              } on ApiException catch (error) {
                                                setDialogState(() {
                                                  busy = false;
                                                  dialogError = error.message;
                                                });
                                              } catch (_) {
                                                setDialogState(() {
                                                  busy = false;
                                                  dialogError = strings.t(
                                                    'failed_revoke_invite',
                                                    fallback:
                                                        'Failed to revoke invite.',
                                                  );
                                                });
                                              }
                                            }
                                          },
                                          itemBuilder: (context) => [
                                            PopupMenuItem<String>(
                                              value: 'copy',
                                              child: Text(
                                                strings.t(
                                                  'copy_code',
                                                  fallback: 'Copy Code',
                                                ),
                                              ),
                                            ),
                                            PopupMenuItem<String>(
                                              value: 'revoke',
                                              child: Text(
                                                strings.t(
                                                  'revoke',
                                                  fallback: 'Revoke',
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(strings.t('close', fallback: 'Close')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final strings = appStringsFor(ref.watch(appLanguageProvider));
    const topBarIconSize = kToolbarHeight * 0.8;
    final iconBorderColor = _isDarkTheme(context)
        ? const Color(0xFF3A3D44)
        : const Color(0xFFBFC6D1);
    const iconRectSizeInSvg = 224.0;
    const iconRectRadiusInSvg = 56.0;
    const iconInnerRadius =
        topBarIconSize * (iconRectRadiusInSvg / iconRectSizeInSvg);
    const iconOuterRadius = iconInnerRadius + 1;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: kToolbarHeight,
        titleSpacing: 12,
        title: Row(
          children: [
            Material(
              color: Colors.transparent,
              child: Ink(
                width: topBarIconSize,
                height: topBarIconSize,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(iconOuterRadius),
                  border: Border.all(color: iconBorderColor),
                ),
                child: InkWell(
                  onTap: _runningAction ? null : _openUserSettingsScreen,
                  borderRadius: BorderRadius.circular(iconOuterRadius),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(iconInnerRadius),
                    child: Image.asset(
                      'assets/icons/icon-topbar.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 170,
              child: Text(
                _topBarDisplayName(),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, -0.04),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: KeyedSubtree(
                  key: ValueKey<String>(
                    'voice-topbar:${_connectedVoiceServerId ?? 'none'}:${_connectedVoiceChannelId ?? 'none'}',
                  ),
                  child: _buildTopBarVoiceConnection(context, strings),
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: strings.t('refresh', fallback: 'Refresh'),
            onPressed: _bootstrap,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final widths = _computePaneWidths(constraints.maxWidth);
          return Row(
            children: [
              SizedBox(
                width: _railWidth,
                child: _buildRail(context),
              ),
              SizedBox(
                width: widths.listPaneWidth,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    final slide = Tween<Offset>(
                      begin: const Offset(-0.035, 0),
                      end: Offset.zero,
                    ).animate(animation);
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(position: slide, child: child),
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey<String>(
                      'list:${_sidebarMode.name}:${_selectedServerId ?? 'none'}:${_selectedUserId ?? 'none'}',
                    ),
                    child: _buildListPane(context),
                  ),
                ),
              ),
              _buildResizeHandle(
                onDragUpdate: (delta) =>
                    _resizeListPane(delta, constraints.maxWidth),
              ),
              SizedBox(
                width: widths.chatPaneWidth,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    final slide = Tween<Offset>(
                      begin: const Offset(0.03, 0),
                      end: Offset.zero,
                    ).animate(animation);
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(position: slide, child: child),
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey<String>(
                      'chat:${_selectedServerId ?? 'none'}:${_selectedChannelId ?? 'none'}:${_selectedDmChannelId ?? 'none'}',
                    ),
                    child: _buildChatPane(context),
                  ),
                ),
              ),
              if (widths.showMemberPane) ...[
                _buildResizeHandle(
                  onDragUpdate: (delta) =>
                      _resizeMemberPane(delta, constraints.maxWidth),
                ),
                SizedBox(
                  width: widths.memberPaneWidth,
                  child: _buildServerMemberPane(context),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildTopBarVoiceConnection(BuildContext context, AppStrings strings) {
    final connectedServerId = _connectedVoiceServerId;
    final connectedChannelId = _connectedVoiceChannelId;
    if (connectedServerId == null || connectedChannelId == null) {
      return const SizedBox.shrink();
    }
    final serverName = _serverNameById(connectedServerId) ?? connectedServerId;
    final channelName = _connectedVoiceChannelName ??
        _voiceChannelName(connectedChannelId) ??
        connectedChannelId;
    final boxColor = _isDarkTheme(context)
        ? const Color(0xFF2B2D31)
        : const Color(0xFFF3F4F6);
    final borderColor = _isDarkTheme(context)
        ? const Color(0xFF3A3D44)
        : const Color(0xFFCED4DD);

    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: boxColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              const Icon(Icons.graphic_eq, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$serverName - #$channelName',
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    Text(
                      _voiceConnectionMetaLabel(strings),
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: _selfVoiceMuted
                    ? strings.t('voice_unmute', fallback: 'Unmute')
                    : strings.t('voice_mute', fallback: 'Mute'),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
                onPressed: _voiceBusy
                    ? null
                    : () => _updateVoiceState(
                          muted: !_selfVoiceMuted,
                          deafened: _selfVoiceDeafened,
                        ),
                icon: Icon(
                  _selfVoiceMuted
                      ? Icons.mic_off_outlined
                      : Icons.mic_none_outlined,
                  size: 18,
                ),
              ),
              IconButton(
                tooltip: _selfVoiceDeafened
                    ? strings.t('voice_undeafen', fallback: 'Undeafen')
                    : strings.t('voice_deafen', fallback: 'Deafen'),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
                onPressed: _voiceBusy
                    ? null
                    : () => _updateVoiceState(
                          muted: _selfVoiceMuted,
                          deafened: !_selfVoiceDeafened,
                        ),
                icon: Icon(
                  _selfVoiceDeafened
                      ? Icons.headset_off_outlined
                      : Icons.headset_outlined,
                  size: 18,
                ),
              ),
              IconButton(
                tooltip: strings.t('voice_leave', fallback: 'Leave'),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
                onPressed: _voiceBusy ? null : _leaveVoiceChannel,
                icon: const Icon(Icons.call_end_outlined, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _voiceStatusLabel(String status) {
    if (status == 'audio-out:ready') {
      return 'Output ready';
    }
    if (status == 'audio-out:error') {
      return 'Output route issue';
    }
    return status;
  }

  String _voiceConnectionMetaLabel(AppStrings strings) {
    final connectionState = _voiceConnectionStateLabel(strings);
    final connectedAt = _voiceConnectedAt;
    final connectedFor = connectedAt == null
        ? '--:--'
        : _formatConnectionDuration(
            DateTime.now().toLocal().difference(connectedAt),
          );
    final latency = _voiceLatencyMs == null ? '-- ms' : '$_voiceLatencyMs ms';
    final routeStatus = _voiceStatusLabel(_voiceTransportStatus);
    if (routeStatus == 'Output route issue') {
      return '$connectionState | $connectedFor | $latency | $routeStatus';
    }
    return '$connectionState | $connectedFor | $latency';
  }

  String _voiceConnectionStateLabel(AppStrings strings) {
    final status = _voiceSignalStatus;
    if (status == 'connecting') {
      return strings.t('connecting', fallback: 'Connecting');
    }
    if (status == 'reconnected') {
      return strings.t('reconnected', fallback: 'Reconnected');
    }
    if (status == 'disconnected' || status == 'idle') {
      return strings.t('disconnected', fallback: 'Disconnected');
    }
    if (status.startsWith('error')) {
      return strings.t('connection_issue', fallback: 'Connection issue');
    }
    return strings.t('connected', fallback: 'Connected');
  }

  String _formatConnectionDuration(Duration duration) {
    final totalSeconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      final h = hours.toString().padLeft(2, '0');
      final m = minutes.toString().padLeft(2, '0');
      final s = seconds.toString().padLeft(2, '0');
      return '$h:$m:$s';
    }
    final m = minutes.toString().padLeft(2, '0');
    final s = seconds.toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _buildRail(BuildContext context) {
    final strings = appStringsFor(ref.watch(appLanguageProvider));
    final isUsersSelected = _sidebarMode == _SidebarMode.users;
    final neutralButtonColor = _isDarkTheme(context)
        ? const Color(0xFF2B2D31)
        : const Color(0xFFD6DAE1);
    const successColor = Color(0xFF23A559);
    final onNeutralColor = _isDarkTheme(context)
        ? const Color(0xFFDBDEE1)
        : const Color(0xFF4E5058);

    return Container(
      color: _railBackgroundColor(context),
      child: Column(
        children: [
          const SizedBox(height: 10),
          _RailActionButton(
            label: widget.session.isPlatformAdmin
                ? strings.t('all_users', fallback: 'All Users')
                : strings.t('friends', fallback: 'Friends'),
            icon: Icons.people_outline,
            onPressed: () {
              setState(() {
                _sidebarMode = _SidebarMode.users;
              });
            },
            backgroundColor: isUsersSelected
                ? Theme.of(context).colorScheme.primary
                : neutralButtonColor,
            hoverBackgroundColor: Theme.of(context).colorScheme.primary,
            iconColor: isUsersSelected
                ? Theme.of(context).colorScheme.onPrimary
                : onNeutralColor,
            hoverIconColor: Theme.of(context).colorScheme.onPrimary,
          ),
          const SizedBox(height: 8),
          _RailActionButton(
            label: strings.t('create_server', fallback: 'Create Server'),
            icon: Icons.add,
            onPressed: _runningAction ? null : _showCreateServerDialog,
            backgroundColor: neutralButtonColor,
            hoverBackgroundColor: successColor,
            iconColor: successColor,
            hoverIconColor: Colors.white,
          ),
          const SizedBox(height: 8),
          _RailActionButton(
            label: strings.t('join_server', fallback: 'Join Server'),
            icon: Icons.link,
            onPressed: _runningAction ? null : _showJoinServerDialog,
            backgroundColor: neutralButtonColor,
            hoverBackgroundColor: successColor,
            iconColor: successColor,
            hoverIconColor: Colors.white,
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              controller: _serverRailScrollController,
              itemCount: _servers.length,
              itemBuilder: (context, index) {
                final server = _servers[index];
                final selected = _sidebarMode == _SidebarMode.servers &&
                    _selectedServerId == server.id;
                final voiceConnectedToServer =
                    _connectedVoiceChannelId != null &&
                        _connectedVoiceServerId == server.id;
                final iconText = server.name.isEmpty
                    ? '?'
                    : server.name.substring(0, 1).toUpperCase();
                final iconUrl = server.iconUrl?.trim();
                final hasIconUrl = iconUrl != null && iconUrl.isNotEmpty;
                return _StaggeredEntrance(
                  key: ValueKey<String>('rail-server-${server.id}'),
                  delayMs: (index * 22).clamp(0, 260).toInt(),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Tooltip(
                      message: server.name,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () async {
                          setState(() {
                            _sidebarMode = _SidebarMode.servers;
                            _selectedServerId = server.id;
                            _selectedUserId = null;
                          });
                          await _loadServerChannels(serverId: server.id);
                        },
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            if (voiceConnectedToServer)
                              Positioned(
                                left: -7,
                                top: 13,
                                child: Container(
                                  width: 4,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF3BA55D),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                              ),
                            Container(
                              height: 50,
                              decoration: BoxDecoration(
                                color: _serverPillColor(context, selected),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Center(
                                child: hasIconUrl
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: Image.network(
                                          iconUrl,
                                          width: 44,
                                          height: 44,
                                          fit: BoxFit.cover,
                                        ),
                                      )
                                    : Text(
                                        iconText,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: selected
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .onPrimary
                                              : Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium
                                                  ?.color,
                                        ),
                                      ),
                              ),
                            ),
                            if (voiceConnectedToServer)
                              Positioned(
                                right: -2,
                                bottom: -2,
                                child: Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF3BA55D),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: _railBackgroundColor(context),
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListPane(BuildContext context) {
    final strings = appStringsFor(ref.watch(appLanguageProvider));
    if (_sidebarMode == _SidebarMode.users) {
      return Container(
        color: _paneBackgroundColor(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              title: Text(widget.session.isPlatformAdmin
                  ? strings.t('all_users', fallback: 'All Users')
                  : strings.t('friends', fallback: 'Friends')),
              subtitle: Text(
                strings.tf(
                  'count',
                  {'count': '${_users.length}'},
                  fallback: 'Count: {count}',
                ),
              ),
              trailing: IconButton(
                tooltip: strings.t('add_friend', fallback: 'Add Friend'),
                onPressed: _runningAction ? null : _showAddFriendDialog,
                icon: const Icon(Icons.person_add_alt_1),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _users.isEmpty
                  ? Center(
                      child: Text(
                        widget.session.isPlatformAdmin
                            ? strings.t(
                                'no_users_available',
                                fallback: 'No users available.',
                              )
                            : strings.t(
                                'no_friends_yet',
                                fallback:
                                    'No friends yet.\nUse Add Friend to start chatting.',
                              ),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      itemCount: _users.length,
                      itemBuilder: (context, index) {
                        final user = _users[index];
                        final selected = _selectedUserId == user.id;
                        return ListTile(
                          selected: selected,
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundColor:
                                Theme.of(context).colorScheme.primary,
                            foregroundImage: (user.avatarUrl != null &&
                                    user.avatarUrl!.trim().isNotEmpty)
                                ? NetworkImage(user.avatarUrl!.trim())
                                : null,
                            child: Text(
                              user.username.isNotEmpty
                                  ? user.username.substring(0, 1).toUpperCase()
                                  : '?',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          title: Text(user.handle),
                          subtitle: Text(user.displayName ?? user.username),
                          onTap: user.id == widget.session.userId
                              ? null
                              : () => _openDmAndLoadMessages(user.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    }

    ApiServerSummary? selectedServer;
    for (final server in _servers) {
      if (server.id == _selectedServerId) {
        selectedServer = server;
        break;
      }
    }
    return Container(
      color: _paneBackgroundColor(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            title: Text(
              selectedServer?.name ??
                  strings.t(
                    'no_server_selected',
                    fallback: 'No server selected',
                  ),
            ),
            subtitle: selectedServer == null
                ? Text(
                    strings.t(
                      'no_server_selected',
                      fallback: 'No server selected',
                    ),
                  )
                : null,
            trailing: PopupMenuButton<String>(
              tooltip: strings.t('server_actions', fallback: 'Server Actions'),
              onSelected: (value) {
                if (value == 'create_channel') {
                  _showCreateChannelDialog();
                  return;
                }
                if (value == 'server_settings') {
                  _openServerSettingsScreen();
                  return;
                }
                if (value == 'server_members') {
                  _showServerMembersDialog();
                  return;
                }
                if (value == 'server_bans') {
                  _showServerBansDialog();
                  return;
                }
                if (value == 'server_invites') {
                  _showServerInvitesDialog();
                }
              },
              itemBuilder: (context) => [
                if (_selectedServerId != null)
                  PopupMenuItem<String>(
                    value: 'create_channel',
                    child: Text(
                      strings.t('create_channel', fallback: 'Create Channel'),
                    ),
                  ),
                if (_selectedServerId != null)
                  PopupMenuItem<String>(
                    value: 'server_settings',
                    child: Text(
                      strings.t('server_settings', fallback: 'Server Settings'),
                    ),
                  ),
                if (_selectedServerId != null)
                  PopupMenuItem<String>(
                    value: 'server_members',
                    child: Text(strings.t('members', fallback: 'Members')),
                  ),
                if (_selectedServerId != null)
                  PopupMenuItem<String>(
                    value: 'server_bans',
                    child: Text(strings.t('bans', fallback: 'Bans')),
                  ),
                if (_selectedServerId != null)
                  PopupMenuItem<String>(
                    value: 'server_invites',
                    child: Text(strings.t('invites', fallback: 'Invites')),
                  ),
              ],
              child: const Icon(Icons.more_vert),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              children: [
                if (_channels.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: Text(
                      strings.t('text_channels', fallback: 'Text Channels'),
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                ..._channels.map((channel) {
                  final selected = channel.id == _selectedChannelId;
                  return ListTile(
                    selected: selected,
                    dense: true,
                    leading: const Icon(Icons.tag, size: 18),
                    title: Text(channel.name),
                    trailing: IconButton(
                      tooltip: strings.t('delete_channel',
                          fallback: 'Delete Channel'),
                      onPressed:
                          _runningAction ? null : () => _deleteChannel(channel),
                      icon: const Icon(Icons.delete_outline, size: 18),
                    ),
                    onTap: () async {
                      setState(() {
                        _selectedChannelId = channel.id;
                        _selectedDmChannelId = null;
                        _selectedUserId = null;
                      });
                      if (_selectedServerId != null) {
                        await _loadServerMessages(
                          serverId: _selectedServerId!,
                          channelId: channel.id,
                        );
                      }
                    },
                  );
                }),
                if (_voiceChannels.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: Text(
                      strings.t('voice_channels', fallback: 'Voice Channels'),
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  ..._voiceChannels.map((channel) {
                    final connected = _connectedVoiceChannelId == channel.id;
                    return ListTile(
                      selected: connected,
                      dense: true,
                      leading: const Icon(Icons.volume_up_outlined, size: 18),
                      title: Text(channel.name),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: _voiceBusy
                                ? null
                                : () async {
                                    if (connected) {
                                      await _leaveVoiceChannel();
                                    } else {
                                      await _joinVoiceChannel(channel.id);
                                    }
                                  },
                            child: Text(
                              connected
                                  ? strings.t('voice_leave', fallback: 'Leave')
                                  : strings.t('voice_join', fallback: 'Join'),
                            ),
                          ),
                          IconButton(
                            tooltip: strings.t(
                              'delete_channel',
                              fallback: 'Delete Channel',
                            ),
                            onPressed: _runningAction
                                ? null
                                : () => _deleteChannel(channel),
                            icon: const Icon(Icons.delete_outline, size: 18),
                          ),
                        ],
                      ),
                      onTap: _voiceBusy
                          ? null
                          : () => _joinVoiceChannel(channel.id),
                    );
                  }),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResizeHandle({
    required void Function(double delta) onDragUpdate,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (details) => onDragUpdate(details.delta.dx),
        child: Container(
          width: _resizeHandleWidth,
          color: _resizeHandleColor(context),
          child: Center(
            child: Container(
              width: 2,
              height: 36,
              decoration: BoxDecoration(
                color: _resizeGripColor(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChatPane(BuildContext context) {
    final strings = appStringsFor(ref.watch(appLanguageProvider));
    final formatter = _activeDateFormatter();
    final title = _chatTitle();
    final compactMode = _useCompactMessageDisplay();
    final showTimestamps = _showMessageTimestamps();
    final visibleMessages = _messages
        .where((message) => message.deletedAt == null)
        .toList(growable: false);

    return Container(
      color: _chatBackgroundColor(context),
      child: Column(
        children: [
          Container(
            height: 56,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Text(title),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final slide = Tween<Offset>(
                  begin: const Offset(0, 0.03),
                  end: Offset.zero,
                ).animate(animation);
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: slide, child: child),
                );
              },
              child: _loadingMessages
                  ? _buildChatLoadingSkeleton(context)
                  : visibleMessages.isEmpty
                      ? Center(
                          key: const ValueKey<String>('chat-empty'),
                          child: Text(
                            strings.t('no_messages', fallback: 'No messages'),
                          ),
                        )
                          : ListView.builder(
                              key: ValueKey<String>(
                            'chat-list:$_messageContextKey:${visibleMessages.length}',
                              ),
                          padding: EdgeInsets.all(compactMode ? 6 : 10),
                          itemCount: visibleMessages.length,
                          itemBuilder: (context, index) {
                            final message = visibleMessages[index];
                            final author = _authorLabel(message.authorUserId);
                            final isOwn = _isOwnMessage(message);
                            final previous =
                                index > 0 ? visibleMessages[index - 1] : null;
                            final next = index + 1 < visibleMessages.length
                                ? visibleMessages[index + 1]
                                : null;
                            final groupedWithPrev = previous != null &&
                                _messagesBelongToSameGroup(previous, message);
                            final groupedWithNext = next != null &&
                                _messagesBelongToSameGroup(message, next);
                            final isGroupStart = !groupedWithPrev;
                            final isGroupEnd = !groupedWithNext;
                            final timestamp = formatter
                                .format(message.createdAt.toLocal());
                            final animateEntry =
                                _seenMessageIds.add(message.messageId);
                            final row = Padding(
                              padding: EdgeInsets.symmetric(
                                vertical: compactMode
                                    ? (isGroupStart ? 2 : 1)
                                    : (isGroupStart ? 4 : 1.5),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 200,
                                    child: Text(
                                      isGroupStart
                                          ? (showTimestamps
                                              ? '$author  $timestamp'
                                              : author)
                                          : (showTimestamps ? timestamp : ''),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: isGroupStart
                                                ? Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.color
                                                : Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.color
                                                    ?.withValues(alpha: 0.62),
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 160),
                                      curve: Curves.easeOutCubic,
                                      padding: EdgeInsets.fromLTRB(
                                        10,
                                        isGroupStart ? 8 : 6,
                                        10,
                                        isGroupEnd ? 8 : 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _messageBlockColor(context, isOwn),
                                        borderRadius: _messageBlockRadius(
                                          isGroupStart: isGroupStart,
                                          isGroupEnd: isGroupEnd,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (message.content != null &&
                                              message.content!.isNotEmpty)
                                            Text(message.content!),
                                          if (message.imageUrl != null &&
                                              message.imageUrl!.isNotEmpty)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.only(top: 6),
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                child: Image.network(
                                                  message.imageUrl!,
                                                  width: 260,
                                                  height: 180,
                                                  fit: BoxFit.cover,
                                                ),
                                              ),
                                            ),
                                          if (message.editedAt != null)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.only(top: 4),
                                              child: Text(
                                                strings.t(
                                                  'edited_suffix',
                                                  fallback: '(edited)',
                                                ),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (isOwn)
                                    PopupMenuButton<String>(
                                      tooltip: strings.t(
                                        'message_actions',
                                        fallback: 'Message actions',
                                      ),
                                      onSelected: (value) {
                                        if (value == 'edit') {
                                          _showEditMessageDialog(message);
                                          return;
                                        }
                                        if (value == 'delete') {
                                          _deleteMessage(message);
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        PopupMenuItem<String>(
                                          value: 'edit',
                                          child: Text(
                                            strings.t('edit', fallback: 'Edit'),
                                          ),
                                        ),
                                        PopupMenuItem<String>(
                                          value: 'delete',
                                          child: Text(
                                            strings.t(
                                              'delete',
                                              fallback: 'Delete',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            );
                            if (!animateEntry) {
                              return row;
                            }
                            return TweenAnimationBuilder<double>(
                              tween: Tween<double>(begin: 0, end: 1),
                              duration: const Duration(milliseconds: 260),
                              curve: Curves.easeOutCubic,
                              child: row,
                              builder: (context, value, child) {
                                return Opacity(
                                  opacity: value,
                                  child: Transform.translate(
                                    offset: Offset(0, (1 - value) * 12),
                                    child: child,
                                  ),
                                );
                              },
                            );
                          },
                        ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
            decoration: BoxDecoration(
              color: _composerBackgroundColor(context),
              border: Border(
                  top: BorderSide(color: Theme.of(context).dividerColor)),
            ),
            child: Column(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    return SizeTransition(
                      axisAlignment: -1,
                      sizeFactor: animation,
                      child: FadeTransition(opacity: animation, child: child),
                    );
                  },
                  child: _pendingImageBytes == null
                      ? const SizedBox.shrink(key: ValueKey<String>('no-image-preview'))
                      : Container(
                          key: const ValueKey<String>('has-image-preview'),
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _composerPreviewColor(context),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.memory(
                                  _pendingImageBytes!,
                                  width: 72,
                                  height: 72,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _pendingImageFile?.name.isNotEmpty == true
                                      ? _pendingImageFile!.name
                                      : strings.t(
                                          'selected_image',
                                          fallback: 'Selected image',
                                        ),
                                ),
                              ),
                              IconButton(
                                tooltip: strings.t('remove_image',
                                    fallback: 'Remove image'),
                                onPressed: _sending ? null : _clearPendingImage,
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                        ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: _composerInputColor(context),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: _composerInputBorderColor(context)),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: strings.t(
                          'attach_image',
                          fallback: 'Attach image',
                        ),
                        onPressed: _sending ? null : _pickImageForMessage,
                        icon: const Icon(Icons.image_outlined),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _composerController,
                          decoration: InputDecoration(
                            hintText: strings.t(
                              'message_channel_hint',
                              fallback: 'Message #channel',
                            ),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: _sending ? null : _sendMessage,
                        child: Text(
                          _sending
                              ? strings.t('sending', fallback: 'Sending...')
                              : strings.t('send', fallback: 'Send'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServerMemberPane(BuildContext context) {
    final strings = appStringsFor(ref.watch(appLanguageProvider));
    final owners =
        _serverMembers.where((member) => member.role == 'owner').toList();
    final admins =
        _serverMembers.where((member) => member.role == 'admin').toList();
    final members = _serverMembers
        .where((member) => member.role != 'owner' && member.role != 'admin')
        .toList();
    var staggerCursor = 0;

    Widget staggerMember(Widget child) {
      final delayMs = (staggerCursor * 18).clamp(0, 340).toInt();
      staggerCursor += 1;
      return _StaggeredEntrance(
        delayMs: delayMs,
        child: child,
      );
    }

    List<Widget> buildSection(
      String title,
      List<ApiServerMember> sectionMembers,
    ) {
      if (sectionMembers.isEmpty) {
        return <Widget>[];
      }
      final widgets = <Widget>[
        staggerMember(
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Text(
              '$title - ${sectionMembers.length}',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).textTheme.bodySmall?.color,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ),
      ];
      for (final member in sectionMembers) {
        final isOnline = _onlineServerMemberUserIds.contains(member.userId);
        widgets.add(
          staggerMember(
            ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 13,
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundImage: (member.avatarUrl != null &&
                        member.avatarUrl!.trim().isNotEmpty)
                    ? NetworkImage(member.avatarUrl!.trim())
                    : null,
                child: Text(
                  (member.displayName ?? member.username).isNotEmpty
                      ? (member.displayName ?? member.username)
                          .substring(0, 1)
                          .toUpperCase()
                      : '?',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              title: Text(
                member.displayName ?? member.username,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                member.handle,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Icon(
                Icons.circle,
                size: 10,
                color: isOnline ? const Color(0xFF3BA55D) : Colors.grey,
              ),
            ),
          ),
        );
      }
      return widgets;
    }

    return Container(
      color: _memberPaneBackgroundColor(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          ListTile(
            dense: true,
            title: Text(strings.t('members', fallback: 'Members')),
            subtitle: Text(
              strings.tf(
                'members_total_online',
                {
                  'total': '${_serverMembers.length}',
                  'online': '${_onlineServerMemberUserIds.length}',
                },
                fallback: 'Total: {total} • Online: {online}',
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.015, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: _loadingServerMembers
                  ? _buildMembersLoadingSkeleton(context)
                  : (_serverMembersError != null)
                      ? Center(
                          key: const ValueKey<String>('members-error'),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              _serverMembersError!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        )
                      : _serverMembers.isEmpty
                          ? Center(
                              key: const ValueKey<String>('members-empty'),
                              child: Text(
                                strings.t(
                                  'no_visible_members',
                                  fallback: 'No visible members',
                                ),
                              ),
                            )
                          : ListView(
                              key: ValueKey<String>(
                                'members-list:${_selectedServerId ?? 'none'}:${_serverMembers.length}:${_voiceStates.length}',
                              ),
                              children: [
                              if (_connectedVoiceServerId == _selectedServerId &&
                                  _connectedVoiceChannelId != null &&
                                  _voiceStates.isNotEmpty) ...[
                                staggerMember(
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      10,
                                      12,
                                      4,
                                    ),
                                    child: Text(
                                      strings.tf(
                                        'voice_participants',
                                        {'count': '${_voiceStates.length}'},
                                        fallback:
                                            'Voice Participants - {count}',
                                      ),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.color,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                ),
                                ..._voiceStates.map((state) {
                                  final peerState =
                                      _voicePeerStates[state.userId];
                                  return staggerMember(
                                    ListTile(
                                      dense: true,
                                      leading: CircleAvatar(
                                        radius: 13,
                                        backgroundColor:
                                            Theme.of(context).colorScheme.primary,
                                        foregroundImage: (state.avatarUrl !=
                                                    null &&
                                                state.avatarUrl!
                                                    .trim()
                                                    .isNotEmpty)
                                            ? NetworkImage(
                                                state.avatarUrl!.trim(),
                                              )
                                            : null,
                                        child: Text(
                                          (state.displayName ?? state.handle)
                                              .substring(0, 1)
                                              .toUpperCase(),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      title: Text(
                                        state.displayName ?? state.handle,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Text(
                                        state.handle,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            state.deafened
                                                ? Icons.headset_off_outlined
                                                : (state.muted
                                                    ? Icons.mic_off_outlined
                                                    : Icons.graphic_eq_outlined),
                                            size: 16,
                                          ),
                                          const SizedBox(width: 8),
                                          Tooltip(
                                            message:
                                                peerState?.name ?? 'pending',
                                            child: Icon(
                                              Icons.circle,
                                              size: 10,
                                              color: _voicePeerStateColor(
                                                peerState,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                              ],
                              ...buildSection(
                                strings.t('owner', fallback: 'Owner'),
                                owners,
                              ),
                              ...buildSection(
                                strings.t('admins', fallback: 'Admins'),
                                admins,
                              ),
                              ...buildSection(
                                strings.t('members', fallback: 'Members'),
                                members,
                              ),
                              ],
                            ),
            ),
          ),
        ],
      ),
    );
  }

  String _chatTitle() {
    final strings = _strings();
    if (_selectedDmChannelId != null && _selectedUserId != null) {
      ApiUserSummary? user;
      for (final item in _users) {
        if (item.id == _selectedUserId) {
          user = item;
          break;
        }
      }
      if (user != null) {
        return strings.tf(
          'dm_with',
          {'handle': user.handle},
          fallback: 'DM with {handle}',
        );
      }
      return strings.t('direct_message', fallback: 'Direct Message');
    }
    if (_selectedServerId != null && _selectedChannelId != null) {
      ApiChannelSummary? channel;
      for (final item in _channels) {
        if (item.id == _selectedChannelId) {
          channel = item;
          break;
        }
      }
      if (channel != null) {
        return '# ${channel.name}';
      }
    }
    if (_selectedServerId != null && _connectedVoiceChannelId != null) {
      final name = _voiceChannelName(_connectedVoiceChannelId);
      if (name != null) {
        return strings.tf(
          'voice_connected_to',
          {'channel': name},
          fallback: 'Connected to voice: {channel}',
        );
      }
    }
    return strings.t(
      'select_channel_or_user',
      fallback: 'Select a channel or user',
    );
  }

  String? _serverNameById(String? serverId) {
    if (serverId == null) {
      return null;
    }
    for (final server in _servers) {
      if (server.id == serverId) {
        return server.name;
      }
    }
    return null;
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

  String _authorLabel(String userId) {
    if (userId == widget.session.userId) {
      return widget.session.handle;
    }
    for (final user in _users) {
      if (user.id == userId) {
        return user.handle;
      }
    }
    return userId.substring(0, 8);
  }

  String _topBarDisplayName() {
    final displayName = _currentUserSettings?.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }
    return _t('display_name', 'Display Name');
  }

  String _roleLabel(String role) {
    if (role == 'owner') {
      return _t('owner', 'Owner');
    }
    if (role == 'admin') {
      return _t('admin', 'Admin');
    }
    return _t('member', 'Member');
  }

  Color _voicePeerStateColor(RTCPeerConnectionState? state) {
    if (state == null) {
      return Colors.grey;
    }
    final raw = state.name.toLowerCase();
    if (raw.contains('connected') || raw.contains('completed')) {
      return const Color(0xFF3BA55D);
    }
    if (raw.contains('connecting') || raw.contains('new')) {
      return const Color(0xFFF0B232);
    }
    if (raw.contains('failed') ||
        raw.contains('disconnected') ||
        raw.contains('closed')) {
      return const Color(0xFFED4245);
    }
    return Colors.grey;
  }
}

class _PaneWidths {
  const _PaneWidths({
    required this.showMemberPane,
    required this.listPaneWidth,
    required this.chatPaneWidth,
    required this.memberPaneWidth,
  });

  final bool showMemberPane;
  final double listPaneWidth;
  final double chatPaneWidth;
  final double memberPaneWidth;
}

class _RailActionButton extends StatefulWidget {
  const _RailActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.backgroundColor,
    required this.hoverBackgroundColor,
    required this.iconColor,
    required this.hoverIconColor,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color backgroundColor;
  final Color hoverBackgroundColor;
  final Color iconColor;
  final Color hoverIconColor;

  @override
  State<_RailActionButton> createState() => _RailActionButtonState();
}

class _RailActionButtonState extends State<_RailActionButton> {
  bool _hovering = false;
  OverlayEntry? _hoverOverlayEntry;

  @override
  void dispose() {
    _removeHoverOverlay();
    super.dispose();
  }

  void _showHoverOverlay() {
    if (_hoverOverlayEntry != null || !mounted) {
      return;
    }

    final box = context.findRenderObject();
    if (box is! RenderBox) {
      return;
    }
    final overlay = Overlay.of(context);
    final origin = box.localToGlobal(Offset.zero);
    final size = box.size;

    _hoverOverlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          left: origin.dx + size.width + 8,
          top: origin.dy + (size.height - 36) / 2,
          child: IgnorePointer(
            child: Material(
              color: const Color(0xFF111214),
              elevation: 6,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                child: Text(
                  widget.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_hoverOverlayEntry!);
  }

  void _removeHoverOverlay() {
    _hoverOverlayEntry?.remove();
    _hoverOverlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onPressed == null;
    final resolvedBackground = _hovering && !disabled
        ? widget.hoverBackgroundColor
        : widget.backgroundColor;
    final resolvedIconColor =
        _hovering && !disabled ? widget.hoverIconColor : widget.iconColor;
    final targetScale = _hovering && !disabled ? 1.06 : 1.0;

    return MouseRegion(
      onEnter: (_) {
        setState(() => _hovering = true);
        if (!disabled) {
          _showHoverOverlay();
        }
      },
      onExit: (_) {
        setState(() => _hovering = false);
        _removeHoverOverlay();
      },
      cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: SizedBox(
        width: 76,
        height: 58,
        child: Align(
          alignment: Alignment.center,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(26),
              onTap: () {
                _removeHoverOverlay();
                widget.onPressed?.call();
              },
              child: AnimatedScale(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOutCubic,
                scale: targetScale,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: resolvedBackground.withValues(
                      alpha: disabled ? 0.55 : 1,
                    ),
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: _hovering && !disabled
                        ? [
                            BoxShadow(
                              color: resolvedBackground.withValues(alpha: 0.35),
                              blurRadius: 12,
                              spreadRadius: 1,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : const [],
                  ),
                  child: Icon(
                    widget.icon,
                    size: 28,
                    color: resolvedIconColor.withValues(
                      alpha: disabled ? 0.55 : 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StaggeredEntrance extends StatefulWidget {
  const _StaggeredEntrance({
    super.key,
    required this.child,
    this.delayMs = 0,
  });

  final Widget child;
  final int delayMs;

  @override
  State<_StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<_StaggeredEntrance> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    final delay = widget.delayMs <= 0 ? 0 : widget.delayMs;
    Future<void>.delayed(Duration(milliseconds: delay), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _visible = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      offset: _visible ? Offset.zero : const Offset(0, 0.04),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        opacity: _visible ? 1 : 0,
        child: widget.child,
      ),
    );
  }
}

class _AnimatedSkeletonBlock extends StatefulWidget {
  const _AnimatedSkeletonBlock({
    this.width,
    this.height = 12,
    this.borderRadius = 8,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  State<_AnimatedSkeletonBlock> createState() => _AnimatedSkeletonBlockState();
}

class _AnimatedSkeletonBlockState extends State<_AnimatedSkeletonBlock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 880),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF373A41)
        : const Color(0xFFDDE2EA);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final alpha = 0.42 + (_controller.value * 0.44);
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: baseColor.withValues(alpha: alpha),
            borderRadius: BorderRadius.circular(widget.borderRadius),
          ),
        );
      },
    );
  }
}

class _AnimatedSkeletonCircle extends StatelessWidget {
  const _AnimatedSkeletonCircle({
    required this.size,
  });

  final double size;

  @override
  Widget build(BuildContext context) {
    return _AnimatedSkeletonBlock(
      width: size,
      height: size,
      borderRadius: size / 2,
    );
  }
}
