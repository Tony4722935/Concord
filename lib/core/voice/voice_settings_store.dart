import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

class VoiceSettings {
  const VoiceSettings({
    this.inputMode = 'voice_activity',
    this.inputVolume = 100,
    this.outputVolume = 100,
    this.automaticInputSensitivity = true,
    this.inputSensitivity = 50,
    this.noiseSuppression = true,
    this.echoCancellation = true,
    this.playJoinLeaveSound = true,
    this.playMuteDeafenSound = true,
    this.startMutedOnJoin = false,
    this.startDeafenedOnJoin = false,
    this.selectedInputDeviceId,
    this.selectedOutputDeviceId,
    this.iceServerUrls = const <String>['stun:stun.l.google.com:19302'],
    this.turnUsername,
    this.turnCredential,
  });

  final String inputMode;
  final double inputVolume;
  final double outputVolume;
  final bool automaticInputSensitivity;
  final double inputSensitivity;
  final bool noiseSuppression;
  final bool echoCancellation;
  final bool playJoinLeaveSound;
  final bool playMuteDeafenSound;
  final bool startMutedOnJoin;
  final bool startDeafenedOnJoin;
  final String? selectedInputDeviceId;
  final String? selectedOutputDeviceId;
  final List<String> iceServerUrls;
  final String? turnUsername;
  final String? turnCredential;

  VoiceSettings copyWith({
    String? inputMode,
    double? inputVolume,
    double? outputVolume,
    bool? automaticInputSensitivity,
    double? inputSensitivity,
    bool? noiseSuppression,
    bool? echoCancellation,
    bool? playJoinLeaveSound,
    bool? playMuteDeafenSound,
    bool? startMutedOnJoin,
    bool? startDeafenedOnJoin,
    String? selectedInputDeviceId,
    bool clearSelectedInputDeviceId = false,
    String? selectedOutputDeviceId,
    bool clearSelectedOutputDeviceId = false,
    List<String>? iceServerUrls,
    String? turnUsername,
    bool clearTurnUsername = false,
    String? turnCredential,
    bool clearTurnCredential = false,
  }) {
    final resolvedStartDeafened =
        startDeafenedOnJoin ?? this.startDeafenedOnJoin;
    final resolvedStartMuted =
        (startMutedOnJoin ?? this.startMutedOnJoin) || resolvedStartDeafened;
    return VoiceSettings(
      inputMode: _normalizeInputMode(inputMode ?? this.inputMode),
      inputVolume: _clampPercent(inputVolume ?? this.inputVolume),
      outputVolume: _clampPercent(outputVolume ?? this.outputVolume),
      automaticInputSensitivity:
          automaticInputSensitivity ?? this.automaticInputSensitivity,
      inputSensitivity:
          _clampSensitivity(inputSensitivity ?? this.inputSensitivity),
      noiseSuppression: noiseSuppression ?? this.noiseSuppression,
      echoCancellation: echoCancellation ?? this.echoCancellation,
      playJoinLeaveSound: playJoinLeaveSound ?? this.playJoinLeaveSound,
      playMuteDeafenSound: playMuteDeafenSound ?? this.playMuteDeafenSound,
      startMutedOnJoin: resolvedStartMuted,
      startDeafenedOnJoin: resolvedStartDeafened,
      selectedInputDeviceId: clearSelectedInputDeviceId
          ? null
          : _normalizeDeviceId(
              selectedInputDeviceId ?? this.selectedInputDeviceId,
            ),
      selectedOutputDeviceId: clearSelectedOutputDeviceId
          ? null
          : _normalizeDeviceId(
              selectedOutputDeviceId ?? this.selectedOutputDeviceId,
            ),
      iceServerUrls: _normalizeIceServerUrls(iceServerUrls ?? this.iceServerUrls),
      turnUsername: clearTurnUsername
          ? null
          : _normalizeOptionalText(turnUsername ?? this.turnUsername),
      turnCredential: clearTurnCredential
          ? null
          : _normalizeOptionalText(turnCredential ?? this.turnCredential),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'input_mode': _normalizeInputMode(inputMode),
      'input_volume': _clampPercent(inputVolume),
      'output_volume': _clampPercent(outputVolume),
      'automatic_input_sensitivity': automaticInputSensitivity,
      'input_sensitivity': _clampSensitivity(inputSensitivity),
      'noise_suppression': noiseSuppression,
      'echo_cancellation': echoCancellation,
      'play_join_leave_sound': playJoinLeaveSound,
      'play_mute_deafen_sound': playMuteDeafenSound,
      'start_muted_on_join': startMutedOnJoin || startDeafenedOnJoin,
      'start_deafened_on_join': startDeafenedOnJoin,
      'selected_input_device_id': _normalizeDeviceId(selectedInputDeviceId),
      'selected_output_device_id': _normalizeDeviceId(selectedOutputDeviceId),
      'ice_server_urls': _normalizeIceServerUrls(iceServerUrls),
      'turn_username': _normalizeOptionalText(turnUsername),
      'turn_credential': _normalizeOptionalText(turnCredential),
    };
  }

  static VoiceSettings fromJson(Map<String, dynamic> raw) {
    final startDeafened = _asBool(raw['start_deafened_on_join'], false);
    final startMuted =
        _asBool(raw['start_muted_on_join'], false) || startDeafened;
    return VoiceSettings(
      inputMode: _normalizeInputMode(raw['input_mode']),
      inputVolume: _clampPercent(_asDouble(raw['input_volume'], 100)),
      outputVolume: _clampPercent(_asDouble(raw['output_volume'], 100)),
      automaticInputSensitivity:
          _asBool(raw['automatic_input_sensitivity'], true),
      inputSensitivity:
          _clampSensitivity(_asDouble(raw['input_sensitivity'], 50)),
      noiseSuppression: _asBool(raw['noise_suppression'], true),
      echoCancellation: _asBool(raw['echo_cancellation'], true),
      playJoinLeaveSound: _asBool(raw['play_join_leave_sound'], true),
      playMuteDeafenSound: _asBool(raw['play_mute_deafen_sound'], true),
      startMutedOnJoin: startMuted,
      startDeafenedOnJoin: startDeafened,
      selectedInputDeviceId:
          _normalizeDeviceId(raw['selected_input_device_id']),
      selectedOutputDeviceId:
          _normalizeDeviceId(raw['selected_output_device_id']),
      iceServerUrls: _normalizeIceServerUrls(raw['ice_server_urls']),
      turnUsername: _normalizeOptionalText(raw['turn_username']),
      turnCredential: _normalizeOptionalText(raw['turn_credential']),
    );
  }

  bool sameAs(VoiceSettings other) {
    return inputMode == other.inputMode &&
        inputVolume == other.inputVolume &&
        outputVolume == other.outputVolume &&
        automaticInputSensitivity == other.automaticInputSensitivity &&
        inputSensitivity == other.inputSensitivity &&
        noiseSuppression == other.noiseSuppression &&
        echoCancellation == other.echoCancellation &&
        playJoinLeaveSound == other.playJoinLeaveSound &&
        playMuteDeafenSound == other.playMuteDeafenSound &&
        startMutedOnJoin == other.startMutedOnJoin &&
        startDeafenedOnJoin == other.startDeafenedOnJoin &&
        selectedInputDeviceId == other.selectedInputDeviceId &&
        selectedOutputDeviceId == other.selectedOutputDeviceId &&
        listEquals(iceServerUrls, other.iceServerUrls) &&
        turnUsername == other.turnUsername &&
        turnCredential == other.turnCredential;
  }

  static String _normalizeInputMode(Object? value) {
    final normalized = (value?.toString().trim().toLowerCase() ?? '');
    if (normalized == 'push_to_talk') {
      return 'push_to_talk';
    }
    return 'voice_activity';
  }

  static double _asDouble(Object? value, double fallback) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value) ?? fallback;
    }
    return fallback;
  }

  static bool _asBool(Object? value, bool fallback) {
    if (value is bool) {
      return value;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true') {
        return true;
      }
      if (normalized == 'false') {
        return false;
      }
    }
    return fallback;
  }

  static double _clampPercent(double value) {
    return value.clamp(0, 200).toDouble();
  }

  static double _clampSensitivity(double value) {
    return value.clamp(0, 100).toDouble();
  }

  static String? _normalizeDeviceId(Object? value) {
    final normalized = value?.toString().trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  static String? _normalizeOptionalText(Object? value) {
    final normalized = value?.toString().trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  static List<String> _normalizeIceServerUrls(Object? raw) {
    final values = <String>[];
    if (raw is List) {
      for (final item in raw) {
        final normalized = item.toString().trim();
        if (normalized.isNotEmpty) {
          values.add(normalized);
        }
      }
    } else if (raw is String) {
      for (final item in raw.split(',')) {
        final normalized = item.trim();
        if (normalized.isNotEmpty) {
          values.add(normalized);
        }
      }
    }
    if (values.isEmpty) {
      return const <String>['stun:stun.l.google.com:19302'];
    }
    return values.toSet().toList(growable: false);
  }
}

class VoiceSettingsStore {
  static String _filePath() {
    return p.join(
        Directory.current.path, '.concord_data', 'voice_settings.json');
  }

  static Future<VoiceSettings> loadPreference() async {
    try {
      final file = File(_filePath());
      if (!file.existsSync()) {
        return const VoiceSettings();
      }
      final raw = (await file.readAsString()).trim();
      if (raw.isEmpty) {
        return const VoiceSettings();
      }
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return VoiceSettings.fromJson(decoded);
      }
      if (decoded is Map) {
        return VoiceSettings.fromJson(
          decoded.map((key, value) => MapEntry(key.toString(), value)),
        );
      }
      return const VoiceSettings();
    } catch (_) {
      return const VoiceSettings();
    }
  }

  static Future<void> savePreference(VoiceSettings settings) async {
    try {
      final directory =
          Directory(p.join(Directory.current.path, '.concord_data'));
      if (!directory.existsSync()) {
        directory.createSync(recursive: true);
      }
      final file = File(_filePath());
      await file.writeAsString(
        jsonEncode(settings.toJson()),
        flush: true,
      );
    } catch (_) {
      // Best-effort local preference cache.
    }
  }
}
