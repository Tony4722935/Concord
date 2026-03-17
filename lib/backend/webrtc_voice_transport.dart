import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

typedef VoiceIceCandidateCallback = Future<void> Function(
  String peerUserId,
  RTCIceCandidate candidate,
);

typedef VoiceStatusCallback = void Function(String status);
typedef VoicePeerConnectionStateCallback = void Function(
  String peerUserId,
  RTCPeerConnectionState state,
);

class WebRtcVoiceTransport {
  WebRtcVoiceTransport({
    required this.currentUserId,
    required this.onIceCandidate,
    required this.onStatus,
    required this.onPeerConnectionState,
    this.iceServerUrls = const <String>['stun:stun.l.google.com:19302'],
    this.turnUsername,
    this.turnCredential,
  });

  final String currentUserId;
  final VoiceIceCandidateCallback onIceCandidate;
  final VoiceStatusCallback onStatus;
  final VoicePeerConnectionStateCallback onPeerConnectionState;
  final List<String> iceServerUrls;
  final String? turnUsername;
  final String? turnCredential;

  final Map<String, RTCPeerConnection> _peers = <String, RTCPeerConnection>{};
  MediaStream? _localStream;
  MediaStreamTrack? _localAudioTrack;
  String? _activeInputDeviceId;

  bool get isInitialized => _localAudioTrack != null;
  Set<String> get peerUserIds => _peers.keys.toSet();

  Future<void> ensureLocalAudioTrack({
    required String? inputDeviceId,
    required bool muted,
    required bool echoCancellation,
    required bool noiseSuppression,
  }) async {
    final normalizedInputId =
        inputDeviceId?.trim().isEmpty == true ? null : inputDeviceId?.trim();
    final needsRecreate = _localAudioTrack == null ||
        (_activeInputDeviceId ?? '') != (normalizedInputId ?? '');

    if (needsRecreate) {
      await _replaceLocalAudioTrack(
        inputDeviceId: normalizedInputId,
        echoCancellation: echoCancellation,
        noiseSuppression: noiseSuppression,
      );
    }
    _localAudioTrack?.enabled = !muted;
  }

  Future<void> applyOutputDevice(String? outputDeviceId) async {
    final normalized = outputDeviceId?.trim();
    if (normalized == null || normalized.isEmpty) {
      return;
    }
    try {
      await Helper.selectAudioOutput(normalized);
      onStatus('audio-out:ready');
    } catch (_) {
      onStatus('audio-out:error');
    }
  }

  Future<void> setMuted(bool muted) async {
    _localAudioTrack?.enabled = !muted;
  }

  Future<void> ensurePeerConnection(String peerUserId) async {
    await _getOrCreatePeer(peerUserId);
  }

  Future<RTCSessionDescription> createOffer(String peerUserId) async {
    final peer = await _getOrCreatePeer(peerUserId);
    final offer = await peer.createOffer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': 0,
    });
    await peer.setLocalDescription(offer);
    onStatus('offer:${_shortId(peerUserId)}');
    return offer;
  }

  Future<RTCSessionDescription> receiveOfferAndCreateAnswer({
    required String peerUserId,
    required String sdp,
    required String type,
  }) async {
    final peer = await _getOrCreatePeer(peerUserId);
    await peer.setRemoteDescription(RTCSessionDescription(sdp, type));
    final answer = await peer.createAnswer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': 0,
    });
    await peer.setLocalDescription(answer);
    onStatus('answer:${_shortId(peerUserId)}');
    return answer;
  }

  Future<void> applyAnswer({
    required String peerUserId,
    required String sdp,
    required String type,
  }) async {
    final peer = await _getOrCreatePeer(peerUserId);
    await peer.setRemoteDescription(RTCSessionDescription(sdp, type));
    onStatus('answer-ok:${_shortId(peerUserId)}');
  }

  Future<void> addIceCandidate({
    required String peerUserId,
    required String candidate,
    required String? sdpMid,
    required int? sdpMLineIndex,
  }) async {
    final peer = await _getOrCreatePeer(peerUserId);
    await peer.addCandidate(
      RTCIceCandidate(candidate, sdpMid, sdpMLineIndex),
    );
  }

  Future<void> closePeer(String peerUserId) async {
    final peer = _peers.remove(peerUserId);
    if (peer != null) {
      await peer.close();
      onStatus('peer-left:${_shortId(peerUserId)}');
    }
  }

  Future<void> closeAllPeers() async {
    final entries = _peers.entries.toList(growable: false);
    _peers.clear();
    for (final entry in entries) {
      await entry.value.close();
    }
  }

  Future<void> prunePeers(Set<String> allowedPeerUserIds) async {
    final toRemove = _peers.keys
        .where((peerId) => !allowedPeerUserIds.contains(peerId))
        .toList(growable: false);
    for (final peerId in toRemove) {
      await closePeer(peerId);
    }
  }

  Future<void> dispose() async {
    await closeAllPeers();
    await _disposeLocalStream();
  }

  Future<void> _replaceLocalAudioTrack({
    required String? inputDeviceId,
    required bool echoCancellation,
    required bool noiseSuppression,
  }) async {
    final constraints = <String, dynamic>{
      'audio': <String, dynamic>{
        'echoCancellation': echoCancellation,
        'noiseSuppression': noiseSuppression,
        if (inputDeviceId != null && inputDeviceId.isNotEmpty && kIsWeb)
          'deviceId': inputDeviceId,
        if (inputDeviceId != null && inputDeviceId.isNotEmpty && !kIsWeb)
          'optional': [
            {'sourceId': inputDeviceId}
          ],
      },
      'video': false,
    };
    final newStream = await navigator.mediaDevices.getUserMedia(constraints);
    final newTrack = newStream.getAudioTracks().isEmpty
        ? null
        : newStream.getAudioTracks().first;
    if (newTrack == null) {
      await newStream.dispose();
      throw StateError('No local audio track created');
    }

    final oldStream = _localStream;
    final oldTrack = _localAudioTrack;
    _localStream = newStream;
    _localAudioTrack = newTrack;
    _activeInputDeviceId = inputDeviceId;

    final peerList = _peers.values.toList(growable: false);
    for (final peer in peerList) {
      final senders = await peer.getSenders();
      final audioSender =
          senders.where((sender) => sender.track?.kind == 'audio');
      if (audioSender.isNotEmpty) {
        await audioSender.first.replaceTrack(newTrack);
      } else {
        await peer.addTrack(newTrack, newStream);
      }
    }

    if (oldTrack != null) {
      await oldTrack.stop();
    }
    if (oldStream != null) {
      await oldStream.dispose();
    }
  }

  Future<RTCPeerConnection> _getOrCreatePeer(String peerUserId) async {
    final existing = _peers[peerUserId];
    if (existing != null) {
      return existing;
    }
    final peer = await createPeerConnection({
      'sdpSemantics': 'unified-plan',
      'iceServers': _buildIceServers(),
    });
    _peers[peerUserId] = peer;

    peer.onIceCandidate = (candidate) async {
      if (candidate.candidate == null || candidate.candidate!.isEmpty) {
        return;
      }
      await onIceCandidate(peerUserId, candidate);
    };

    peer.onConnectionState = (state) {
      onStatus('peer:${_shortId(peerUserId)}:${state.name}');
      onPeerConnectionState(peerUserId, state);
    };

    peer.onTrack = (event) {
      // Remote audio tracks are routed by WebRTC natively once attached.
      if (event.track.kind == 'audio') {
        onStatus('remote-audio:${_shortId(peerUserId)}');
      }
    };

    final localTrack = _localAudioTrack;
    final localStream = _localStream;
    if (localTrack != null && localStream != null) {
      await peer.addTrack(localTrack, localStream);
    }
    return peer;
  }

  Future<void> _disposeLocalStream() async {
    final track = _localAudioTrack;
    final stream = _localStream;
    _localAudioTrack = null;
    _localStream = null;
    _activeInputDeviceId = null;
    if (track != null) {
      await track.stop();
    }
    if (stream != null) {
      await stream.dispose();
    }
  }

  String _shortId(String value) {
    if (value.length <= 8) {
      return value;
    }
    return value.substring(0, 8);
  }

  List<Map<String, dynamic>> _buildIceServers() {
    final urls = iceServerUrls.where((url) => url.trim().isNotEmpty).toList();
    if (urls.isEmpty) {
      return const <Map<String, dynamic>>[
        {'urls': ['stun:stun.l.google.com:19302']},
      ];
    }
    final servers = <Map<String, dynamic>>[];
    for (final url in urls) {
      final normalized = url.trim();
      final isTurn = normalized.toLowerCase().startsWith('turn:');
      if (isTurn &&
          turnUsername != null &&
          turnUsername!.trim().isNotEmpty &&
          turnCredential != null &&
          turnCredential!.trim().isNotEmpty) {
        servers.add({
          'urls': [normalized],
          'username': turnUsername!.trim(),
          'credential': turnCredential!.trim(),
        });
      } else {
        servers.add({
          'urls': [normalized],
        });
      }
    }
    return servers;
  }
}
