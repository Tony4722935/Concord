import 'dart:async';
import 'dart:convert';
import 'dart:io';

class VoiceSignalEvent {
  const VoiceSignalEvent({
    required this.channelId,
    required this.serverId,
    required this.senderUserId,
    required this.signalType,
    required this.data,
    required this.timestamp,
  });

  final String channelId;
  final String serverId;
  final String senderUserId;
  final String signalType;
  final Map<String, dynamic> data;
  final DateTime timestamp;
}

class VoiceSignalClient {
  VoiceSignalClient({
    required this.baseUrl,
    required this.accessToken,
    required this.serverId,
    required this.channelId,
  });

  final String baseUrl;
  final String accessToken;
  final String serverId;
  final String channelId;

  final StreamController<VoiceSignalEvent> _eventsController =
      StreamController<VoiceSignalEvent>.broadcast();
  final StreamController<String> _statusController =
      StreamController<String>.broadcast();
  final StreamController<int> _latencyMsController =
      StreamController<int>.broadcast();
  WebSocket? _socket;
  Timer? _pingTimer;
  StreamSubscription<dynamic>? _socketSubscription;
  bool _connected = false;
  DateTime? _lastPingSentAtUtc;

  Stream<VoiceSignalEvent> get events => _eventsController.stream;
  Stream<String> get statusMessages => _statusController.stream;
  Stream<int> get latencyMs => _latencyMsController.stream;
  bool get isConnected => _connected;

  Future<void> connect() async {
    if (_connected) {
      return;
    }
    final wsUri = _buildGatewayUri();
    _statusController.add('connecting');
    _socket = await WebSocket.connect(wsUri.toString());
    _connected = true;
    _statusController.add('connected');

    _socketSubscription = _socket!.listen(
      _onSocketData,
      onError: (_) {
        _statusController.add('error');
      },
      onDone: () {
        _connected = false;
        _pingTimer?.cancel();
        _statusController.add('disconnected');
      },
      cancelOnError: false,
    );

    _sendAction('subscribe_voice_channel', {
      'channel_id': channelId,
    });
    _sendPresencePing();
    _pingTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _sendPresencePing(),
    );
  }

  Future<void> sendSignal({
    required String signalType,
    Map<String, dynamic>? data,
  }) async {
    if (!_connected || _socket == null) {
      return;
    }
    _sendAction(
      'voice_signal',
      {
        'channel_id': channelId,
        'signal_type': signalType,
        'data': data ?? const {},
      },
    );
  }

  Future<void> disconnect() async {
    _pingTimer?.cancel();
    _pingTimer = null;
    if (_socket != null) {
      try {
        _sendAction('unsubscribe_voice_channel', {
          'channel_id': channelId,
        });
      } catch (_) {
        // Ignore best-effort unsubscribe failures.
      }
      try {
        await _socket!.close();
      } catch (_) {
        // Ignore close failures.
      }
    }
    await _socketSubscription?.cancel();
    _socketSubscription = null;
    _socket = null;
    _connected = false;
    _lastPingSentAtUtc = null;
    _statusController.add('disconnected');
  }

  Future<void> dispose() async {
    await disconnect();
    await _eventsController.close();
    await _statusController.close();
    await _latencyMsController.close();
  }

  Uri _buildGatewayUri() {
    final baseUri = Uri.parse(baseUrl);
    final wsScheme = baseUri.scheme == 'https' ? 'wss' : 'ws';
    return baseUri.replace(
      scheme: wsScheme,
      path: '/v1/ws',
      queryParameters: {
        'access_token': accessToken,
      },
    );
  }

  void _sendAction(String action, Map<String, dynamic> payload) {
    final socket = _socket;
    if (socket == null) {
      return;
    }
    socket.add(
      jsonEncode({
        'action': action,
        ...payload,
      }),
    );
  }

  void _sendPresencePing() {
    _lastPingSentAtUtc = DateTime.now().toUtc();
    _sendAction('presence_ping', const {});
  }

  void _onSocketData(dynamic raw) {
    Map<String, dynamic>? parsed;
    if (raw is String) {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        parsed = decoded;
      } else if (decoded is Map) {
        parsed = decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } else if (raw is List<int>) {
      final decoded = jsonDecode(utf8.decode(raw));
      if (decoded is Map<String, dynamic>) {
        parsed = decoded;
      } else if (decoded is Map) {
        parsed = decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    }
    if (parsed == null) {
      return;
    }

    final type = (parsed['type']?.toString() ?? '').trim();
    if (type == 'voice.signal') {
      final payload = parsed['payload'];
      if (payload is! Map) {
        return;
      }
      final normalized =
          payload.map((key, value) => MapEntry(key.toString(), value));
      final data = normalized['data'];
      final signalData = data is Map
          ? data.map((key, value) => MapEntry(key.toString(), value))
          : <String, dynamic>{};
      final timestampRaw = normalized['timestamp']?.toString();
      final parsedTimestamp = timestampRaw == null
          ? DateTime.now().toUtc()
          : DateTime.tryParse(timestampRaw)?.toUtc() ?? DateTime.now().toUtc();
      _eventsController.add(
        VoiceSignalEvent(
          channelId: normalized['channel_id']?.toString() ?? channelId,
          serverId: normalized['server_id']?.toString() ?? serverId,
          senderUserId: normalized['sender_user_id']?.toString() ?? '',
          signalType: normalized['signal_type']?.toString() ?? 'unknown',
          data: signalData,
          timestamp: parsedTimestamp,
        ),
      );
      return;
    }

    if (type == 'presence.snapshot') {
      final pingStart = _lastPingSentAtUtc;
      if (pingStart != null) {
        final latency = DateTime.now().toUtc().difference(pingStart).inMilliseconds;
        _latencyMsController.add(latency < 0 ? 0 : latency);
      }
      return;
    }

    if (type == 'error') {
      final payload = parsed['payload'];
      if (payload is Map) {
        final message = payload['message']?.toString();
        if (message != null && message.isNotEmpty) {
          _statusController.add('error:$message');
        }
      }
    }
  }
}
