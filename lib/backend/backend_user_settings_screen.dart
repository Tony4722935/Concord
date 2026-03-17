import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:record/record.dart';

import 'package:concord/backend/backend_session.dart';
import 'package:concord/backend/concord_api_client.dart';
import 'package:concord/backend/image_asset_picker.dart';
import 'package:concord/core/time/time_format_preference_store.dart';
import 'package:concord/core/time/time_format_provider.dart';
import 'package:concord/core/theme/theme_mode_provider.dart';
import 'package:concord/core/theme/theme_preference_store.dart';
import 'package:concord/core/voice/voice_settings_store.dart';
import 'package:concord/l10n/app_strings.dart';
import 'package:concord/l10n/language_preference_store.dart';
import 'package:concord/l10n/language_provider.dart';

enum _SettingsSection {
  account,
  appearance,
  chat,
  languageRegion,
  voiceAudio,
}

class BackendUserSettingsScreen extends ConsumerStatefulWidget {
  const BackendUserSettingsScreen({
    super.key,
    required this.baseUrl,
    required this.session,
  });

  final String baseUrl;
  final ApiAuthSession session;

  @override
  ConsumerState<BackendUserSettingsScreen> createState() =>
      _BackendUserSettingsScreenState();
}

class _BackendUserSettingsScreenState
    extends ConsumerState<BackendUserSettingsScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _currentPasswordController =
      TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final TextEditingController _deletePasswordController =
      TextEditingController();
  final AudioRecorder _audioRecorder = AudioRecorder();

  bool _loading = true;
  bool _saving = false;
  bool _deleting = false;
  bool _avatarWorking = false;
  bool _didChange = false;
  String? _error;
  ApiCurrentUser? _me;
  _SettingsSection _selectedSection = _SettingsSection.account;
  String _initialThemePreference = 'dark';
  String _initialLanguage = 'en-US';
  String _initialTimeFormat = '24h';
  String _themePreference = 'dark';
  String _language = 'en-US';
  String _timeFormat = '24h';
  bool _compactMode = false;
  bool _showMessageTimestamps = true;
  VoiceSettings _initialVoiceSettings = const VoiceSettings();
  VoiceSettings _voiceSettings = const VoiceSettings();
  bool _voiceTestRunning = false;
  String? _voiceTestError;
  StreamSubscription<Uint8List>? _micStreamSubscription;
  bool _micMeterActive = false;
  double _micInputLevel = 0;
  String? _micMeterError;
  RTCPeerConnection? _micLoopbackSender;
  RTCPeerConnection? _micLoopbackReceiver;
  MediaStream? _micLoopbackStream;
  List<InputDevice> _inputDevices = const [];
  List<MediaDeviceInfo> _outputDevices = const [];
  bool _audioDevicesLoading = false;
  String? _audioDevicesError;

  ConcordApiClient get _client => ConcordApiClient(baseUrl: widget.baseUrl);

  AppStrings _strings() {
    return appStringsFor(ref.read(appLanguageProvider));
  }

  ApiCurrentUser _copyUserWithLocalPreferences(
    ApiCurrentUser user,
    String themePreference,
    String language,
    String timeFormat,
  ) {
    return ApiCurrentUser(
      id: user.id,
      handle: user.handle,
      username: user.username,
      displayName: user.displayName,
      avatarUrl: user.avatarUrl,
      themePreference: themePreference,
      language: language,
      timeFormat: normalizeTimeFormatPreference(timeFormat),
      compactMode: user.compactMode,
      showMessageTimestamps: user.showMessageTimestamps,
      isPlatformAdmin: user.isPlatformAdmin,
    );
  }

  void _closeSettings() {
    if (_saving) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _strings().t('wait_saving',
                fallback: 'Please wait, settings are still saving.'),
          ),
        ),
      );
      return;
    }
    if (_themePreference != _initialThemePreference) {
      ref.read(appThemeModeProvider.notifier).state =
          themeModeFromPreference(_initialThemePreference);
    }
    if (_language != _initialLanguage) {
      ref.read(appLanguageProvider.notifier).state = _initialLanguage;
    }
    _stopVoiceTest();
    unawaited(_stopMicLevelMonitor());
    Navigator.of(context).pop(_didChange);
  }

  void _stopVoiceTest() {
    unawaited(_stopMicLoopback());
    unawaited(_stopMicLevelMonitor());
    if (!mounted) {
      return;
    }
    setState(() {
      _voiceTestRunning = false;
    });
  }

  void _toggleVoiceTest() {
    if (_voiceTestRunning) {
      _stopVoiceTest();
      return;
    }
    unawaited(_startVoiceTest());
  }

  Future<void> _startVoiceTest() async {
    setState(() {
      _voiceTestRunning = true;
      _voiceTestError = null;
    });
    await _startMicLevelMonitor();
    try {
      await _startMicLoopback();
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _voiceTestRunning = false;
        _voiceTestError = _strings().t(
          'voice_loopback_failed',
          fallback: 'Failed to start microphone test loopback.',
        );
      });
      return;
    }
  }

  bool _voiceSettingsChanged() {
    return !_voiceSettings.sameAs(_initialVoiceSettings);
  }

  Future<void> _startMicLevelMonitor() async {
    if (_micMeterActive) {
      return;
    }
    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        if (!mounted) {
          return;
        }
        setState(() {
          _micMeterError = _strings().t(
            'voice_mic_permission_denied',
            fallback:
                'Microphone permission denied. Enable microphone access and reopen Voice & Audio.',
          );
          _micMeterActive = false;
          _micInputLevel = 0;
        });
        return;
      }

      final stream = await _audioRecorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          device: _selectedRecordInputDevice(),
          echoCancel: _voiceSettings.echoCancellation,
          noiseSuppress: _voiceSettings.noiseSuppression,
        ),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _micMeterError = null;
        _micMeterActive = true;
      });
      _micStreamSubscription = stream.listen(
        (chunk) {
          if (!mounted) {
            return;
          }
          final nextLevel = _pcm16ToLevel(chunk);
          setState(() {
            _micInputLevel = (_micInputLevel * 0.65) + (nextLevel * 0.35);
          });
        },
        onError: (_) {
          if (!mounted) {
            return;
          }
          setState(() {
            _micMeterActive = false;
            _micInputLevel = 0;
            _micMeterError = _strings().t(
              'voice_mic_read_failed',
              fallback: 'Failed to read microphone input level.',
            );
          });
        },
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _micMeterActive = false;
        _micInputLevel = 0;
        _micMeterError = _strings().t(
          'voice_mic_read_failed',
          fallback: 'Failed to read microphone input level.',
        );
      });
    }
  }

  Future<void> _stopMicLevelMonitor() async {
    await _micStreamSubscription?.cancel();
    _micStreamSubscription = null;
    try {
      await _audioRecorder.stop();
    } catch (_) {
      // Ignore stop failures during teardown.
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _micMeterActive = false;
      _micInputLevel = 0;
    });
  }

  InputDevice? _selectedRecordInputDevice() {
    final selectedId = _voiceSettings.selectedInputDeviceId;
    if (selectedId == null || selectedId.isEmpty) {
      return null;
    }
    for (final device in _inputDevices) {
      if (device.id == selectedId) {
        return device;
      }
    }
    return null;
  }

  String _inputDeviceLabel(InputDevice device, int index) {
    final raw = device.label.trim();
    if (raw.isNotEmpty) {
      return raw;
    }
    return _strings().tf(
      'voice_input_device_indexed',
      {'index': '${index + 1}'},
      fallback: 'Input Device {index}',
    );
  }

  String _outputDeviceLabel(MediaDeviceInfo device, int index) {
    final raw = device.label.trim();
    if (raw.isNotEmpty) {
      return raw;
    }
    return _strings().tf(
      'voice_output_device_indexed',
      {'index': '${index + 1}'},
      fallback: 'Output Device {index}',
    );
  }

  Future<void> _loadAudioDevices() async {
    if (_audioDevicesLoading) {
      return;
    }
    setState(() {
      _audioDevicesLoading = true;
      _audioDevicesError = null;
    });

    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        if (!mounted) {
          return;
        }
        setState(() {
          _inputDevices = const [];
          _outputDevices = const [];
          _audioDevicesLoading = false;
          _audioDevicesError = _strings().t(
            'voice_mic_permission_denied',
            fallback:
                'Microphone permission denied. Enable microphone access and reopen Voice & Audio.',
          );
        });
        return;
      }

      final inputs = await _audioRecorder.listInputDevices();
      MediaStream? temporary;
      try {
        temporary = await navigator.mediaDevices.getUserMedia({
          'audio': true,
          'video': false,
        });
      } catch (_) {
        // Continue; outputs might still be available.
      } finally {
        if (temporary != null) {
          for (final track in temporary.getTracks()) {
            await track.stop();
          }
          await temporary.dispose();
        }
      }

      final allWebRtcDevices = await navigator.mediaDevices.enumerateDevices();
      final outputs = allWebRtcDevices
          .where((device) => device.kind == 'audiooutput')
          .toList(growable: false);

      if (!mounted) {
        return;
      }

      final hasSelectedInput = _voiceSettings.selectedInputDeviceId != null &&
          inputs.any(
              (device) => device.id == _voiceSettings.selectedInputDeviceId);
      final hasSelectedOutput = _voiceSettings.selectedOutputDeviceId != null &&
          outputs.any(
            (device) =>
                device.deviceId == _voiceSettings.selectedOutputDeviceId,
          );

      setState(() {
        _inputDevices = inputs;
        _outputDevices = outputs;
        _audioDevicesLoading = false;
        _audioDevicesError = null;
        _voiceSettings = _voiceSettings.copyWith(
          selectedInputDeviceId: hasSelectedInput
              ? _voiceSettings.selectedInputDeviceId
              : (inputs.isNotEmpty ? inputs.first.id : null),
          clearSelectedInputDeviceId: inputs.isEmpty,
          selectedOutputDeviceId: hasSelectedOutput
              ? _voiceSettings.selectedOutputDeviceId
              : (outputs.isNotEmpty ? outputs.first.deviceId : null),
          clearSelectedOutputDeviceId: outputs.isEmpty,
        );
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _audioDevicesLoading = false;
        _audioDevicesError = _strings().t(
          'failed_load_audio_devices',
          fallback: 'Failed to load audio devices.',
        );
      });
    }
  }

  Future<void> _restartMicMonitor() async {
    final wasActive =
        _micMeterActive || _voiceTestRunning || _micStreamSubscription != null;
    await _stopMicLevelMonitor();
    if (!mounted ||
        _selectedSection != _SettingsSection.voiceAudio ||
        !wasActive) {
      return;
    }
    await _startMicLevelMonitor();
    if (_voiceTestRunning) {
      try {
        await _startMicLoopback();
      } catch (_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _voiceTestError = _strings().t(
            'voice_loopback_failed',
            fallback: 'Failed to start microphone test loopback.',
          );
        });
      }
    }
  }

  Future<void> _restartMicLoopbackIfTesting() async {
    if (!_voiceTestRunning) {
      return;
    }
    try {
      await _startMicLoopback();
      if (!mounted) {
        return;
      }
      setState(() {
        _voiceTestError = null;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _voiceTestError = _strings().t(
          'voice_loopback_failed',
          fallback: 'Failed to start microphone test loopback.',
        );
      });
    }
  }

  double _pcm16ToLevel(Uint8List bytes) {
    if (bytes.length < 2) {
      return 0;
    }
    var sampleCount = 0;
    var sumSquares = 0.0;
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      var sample = bytes[i] | (bytes[i + 1] << 8);
      if (sample >= 0x8000) {
        sample -= 0x10000;
      }
      final normalized = sample / 32768.0;
      sumSquares += normalized * normalized;
      sampleCount += 1;
    }
    if (sampleCount == 0) {
      return 0;
    }
    final rms = math.sqrt(sumSquares / sampleCount).clamp(0.0, 1.0).toDouble();
    final db = 20 * math.log(math.max(rms, 1e-8)) / math.ln10;
    var normalized = ((db + 60) / 60).clamp(0.0, 1.0).toDouble();
    normalized = math.pow(normalized, 0.55).toDouble();
    final inputGain = (_voiceSettings.inputVolume / 100).clamp(0.1, 2.0);
    normalized = (normalized * inputGain).clamp(0.0, 1.0).toDouble();
    if (!_voiceSettings.automaticInputSensitivity) {
      final sensitivity = (_voiceSettings.inputSensitivity / 100).clamp(0, 1);
      final gateDb = -55 + (sensitivity * 35);
      final gate = ((db - gateDb) / (0 - gateDb)).clamp(0.0, 1.0).toDouble();
      normalized = (normalized * gate).clamp(0.0, 1.0).toDouble();
    }
    return normalized;
  }

  Map<String, dynamic> _micAudioConstraints() {
    final selectedInputId = _voiceSettings.selectedInputDeviceId;
    return <String, dynamic>{
      'audio': <String, dynamic>{
        'echoCancellation': _voiceSettings.echoCancellation,
        'noiseSuppression': _voiceSettings.noiseSuppression,
        if (selectedInputId != null && selectedInputId.isNotEmpty && kIsWeb)
          'deviceId': selectedInputId,
        if (selectedInputId != null && selectedInputId.isNotEmpty && !kIsWeb)
          'optional': [
            {'sourceId': selectedInputId}
          ],
      },
      'video': false,
    };
  }

  Future<void> _applySelectedOutputDevice() async {
    final selectedOutputId = _voiceSettings.selectedOutputDeviceId;
    if (selectedOutputId == null || selectedOutputId.isEmpty) {
      return;
    }
    try {
      await Helper.selectAudioOutput(selectedOutputId);
    } catch (_) {
      // Some platforms do not support selecting a specific output.
    }
  }

  Future<void> _startMicLoopback() async {
    await _stopMicLoopback();
    final localStream =
        await navigator.mediaDevices.getUserMedia(_micAudioConstraints());
    final audioTracks = localStream.getAudioTracks();
    if (audioTracks.isEmpty) {
      await localStream.dispose();
      throw StateError('No audio track available for mic loopback.');
    }

    final sender = await createPeerConnection(
      const {
        'sdpSemantics': 'unified-plan',
        'iceServers': [],
      },
    );
    final receiver = await createPeerConnection(
      const {
        'sdpSemantics': 'unified-plan',
        'iceServers': [],
      },
    );

    sender.onIceCandidate = (candidate) async {
      if (candidate.candidate == null || candidate.candidate!.isEmpty) {
        return;
      }
      try {
        await receiver.addCandidate(candidate);
      } catch (_) {
        // Ignore transient candidate races during local loopback setup.
      }
    };
    receiver.onIceCandidate = (candidate) async {
      if (candidate.candidate == null || candidate.candidate!.isEmpty) {
        return;
      }
      try {
        await sender.addCandidate(candidate);
      } catch (_) {
        // Ignore transient candidate races during local loopback setup.
      }
    };
    receiver.onTrack = (_) {
      // Remote loopback audio is rendered by WebRTC on desktop platforms.
    };

    await sender.addTrack(audioTracks.first, localStream);

    final offer = await sender.createOffer(const {
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': 0,
    });
    await sender.setLocalDescription(offer);
    await receiver.setRemoteDescription(offer);
    final answer = await receiver.createAnswer(const {
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': 0,
    });
    await receiver.setLocalDescription(answer);
    await sender.setRemoteDescription(answer);
    await _applySelectedOutputDevice();

    _micLoopbackSender = sender;
    _micLoopbackReceiver = receiver;
    _micLoopbackStream = localStream;
  }

  Future<void> _stopMicLoopback() async {
    final sender = _micLoopbackSender;
    final receiver = _micLoopbackReceiver;
    final stream = _micLoopbackStream;
    _micLoopbackSender = null;
    _micLoopbackReceiver = null;
    _micLoopbackStream = null;

    if (sender != null) {
      try {
        await sender.close();
      } catch (_) {
        // Ignore teardown failures.
      }
    }
    if (receiver != null) {
      try {
        await receiver.close();
      } catch (_) {
        // Ignore teardown failures.
      }
    }
    if (stream != null) {
      for (final track in stream.getTracks()) {
        try {
          await track.stop();
        } catch (_) {
          // Ignore teardown failures.
        }
      }
      try {
        await stream.dispose();
      } catch (_) {
        // Ignore teardown failures.
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _loadMe();
  }

  @override
  void dispose() {
    unawaited(_stopMicLoopback());
    unawaited(_stopMicLevelMonitor());
    unawaited(_audioRecorder.dispose());
    _usernameController.dispose();
    _displayNameController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _deletePasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadMe() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final me = await _client.getMe(accessToken: widget.session.accessToken);
      final localThemePreference =
          themePreferenceFromMode(ref.read(appThemeModeProvider));
      final localLanguage =
          normalizeLanguageCode(ref.read(appLanguageProvider));
      final cachedTimeFormat = await TimeFormatPreferenceStore.loadPreference();
      final cachedVoiceSettings = await VoiceSettingsStore.loadPreference();
      final localTimeFormat = cachedTimeFormat == null
          ? normalizeTimeFormatPreference(me.timeFormat)
          : normalizeTimeFormatPreference(cachedTimeFormat);
      if (cachedTimeFormat == null) {
        ref.read(appTimeFormatProvider.notifier).state = localTimeFormat;
        await TimeFormatPreferenceStore.savePreference(localTimeFormat);
      }
      final meWithLocalPreferences = _copyUserWithLocalPreferences(
        me,
        localThemePreference,
        localLanguage,
        localTimeFormat,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _me = meWithLocalPreferences;
        _usernameController.text = meWithLocalPreferences.username;
        _displayNameController.text = meWithLocalPreferences.displayName ?? '';
        _initialThemePreference = localThemePreference;
        _themePreference = localThemePreference;
        _initialLanguage = localLanguage;
        _language = localLanguage;
        _initialTimeFormat = localTimeFormat;
        _timeFormat = localTimeFormat;
        _compactMode = meWithLocalPreferences.compactMode;
        _showMessageTimestamps = meWithLocalPreferences.showMessageTimestamps;
        _initialVoiceSettings = cachedVoiceSettings;
        _voiceSettings = cachedVoiceSettings;
        _loading = false;
      });
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
        _error = _strings().t('failed_load_settings',
            fallback: 'Failed to load user settings.');
      });
    }
  }

  Future<void> _saveSettings() async {
    if (_saving || _deleting || _avatarWorking || _me == null) {
      return;
    }

    final me = _me!;
    final username = _usernameController.text.trim();
    final displayName = _displayNameController.text.trim();
    final currentPassword = _currentPasswordController.text.trim();
    final newPassword = _newPasswordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (username.isEmpty) {
      setState(() {
        _error = _strings()
            .t('username_required', fallback: 'Username is required.');
      });
      return;
    }

    final wantsPasswordChange =
        newPassword.isNotEmpty || confirmPassword.isNotEmpty;
    if (wantsPasswordChange && newPassword != confirmPassword) {
      setState(() {
        _error = _strings().t('password_mismatch',
            fallback: 'New password and confirmation do not match.');
      });
      return;
    }
    if (wantsPasswordChange && currentPassword.isEmpty) {
      setState(() {
        _error = _strings().t(
          'current_password_required',
          fallback: 'Current password is required to change password.',
        );
      });
      return;
    }

    final usernameChanged = username != me.username;
    final displayNameChanged = displayName != (me.displayName ?? '');
    final themeChanged = _themePreference != me.themePreference;
    final languageChanged = _language != _initialLanguage;
    final timeFormatChanged = _timeFormat != _initialTimeFormat;
    final compactChanged = _compactMode != me.compactMode;
    final timestampChanged = _showMessageTimestamps != me.showMessageTimestamps;
    final voiceChanged = _voiceSettingsChanged();
    final hasBackendChanges = usernameChanged ||
        displayNameChanged ||
        wantsPasswordChange ||
        timeFormatChanged ||
        compactChanged ||
        timestampChanged;

    if (!usernameChanged &&
        !displayNameChanged &&
        !wantsPasswordChange &&
        !themeChanged &&
        !languageChanged &&
        !timeFormatChanged &&
        !compactChanged &&
        !timestampChanged &&
        !voiceChanged) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _strings()
                  .t('no_changes', fallback: 'No additional changes to save.'),
            ),
          ),
        );
      }
      return;
    }

    if (!hasBackendChanges &&
        (themeChanged || languageChanged || voiceChanged)) {
      ref.read(appThemeModeProvider.notifier).state =
          themeModeFromPreference(_themePreference);
      await ThemePreferenceStore.savePreference(_themePreference);
      ref.read(appLanguageProvider.notifier).state = _language;
      await LanguagePreferenceStore.savePreference(_language);
      ref.read(appTimeFormatProvider.notifier).state =
          normalizeTimeFormatPreference(_timeFormat);
      await TimeFormatPreferenceStore.savePreference(_timeFormat);
      await VoiceSettingsStore.savePreference(_voiceSettings);
      setState(() {
        _me = ApiCurrentUser(
          id: me.id,
          handle: me.handle,
          username: me.username,
          displayName: me.displayName,
          avatarUrl: me.avatarUrl,
          themePreference: _themePreference,
          language: _language,
          timeFormat: _timeFormat,
          compactMode: me.compactMode,
          showMessageTimestamps: me.showMessageTimestamps,
          isPlatformAdmin: me.isPlatformAdmin,
        );
        _initialThemePreference = _themePreference;
        _initialLanguage = _language;
        _initialTimeFormat = _timeFormat;
        _initialVoiceSettings = _voiceSettings;
        _didChange = true;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _strings()
                  .t('settings_updated', fallback: 'User settings updated.'),
            ),
          ),
        );
      }
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      ApiCurrentUser updated = await _client.updateMe(
        accessToken: widget.session.accessToken,
        username: usernameChanged ? username : null,
        displayName: displayNameChanged ? displayName : null,
        currentPassword: wantsPasswordChange ? currentPassword : null,
        newPassword: wantsPasswordChange ? newPassword : null,
        timeFormat: timeFormatChanged ? _timeFormat : null,
        compactMode: compactChanged ? _compactMode : null,
        showMessageTimestamps: timestampChanged ? _showMessageTimestamps : null,
      );
      if (!mounted) {
        return;
      }
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      _deletePasswordController.clear();

      ref.read(backendSessionProvider.notifier).updateSessionHandle(
            updated.handle,
          );

      final appliedTheme =
          themeChanged ? _themePreference : _initialThemePreference;
      final appliedLanguage = _language;
      final appliedTimeFormat =
          timeFormatChanged ? _timeFormat : _initialTimeFormat;
      final appliedCompact =
          compactChanged ? _compactMode : updated.compactMode;
      final appliedTimestamps = timestampChanged
          ? _showMessageTimestamps
          : updated.showMessageTimestamps;

      ref.read(appThemeModeProvider.notifier).state =
          themeModeFromPreference(appliedTheme);
      await ThemePreferenceStore.savePreference(appliedTheme);
      ref.read(appLanguageProvider.notifier).state = appliedLanguage;
      await LanguagePreferenceStore.savePreference(appliedLanguage);
      ref.read(appTimeFormatProvider.notifier).state =
          normalizeTimeFormatPreference(appliedTimeFormat);
      await TimeFormatPreferenceStore.savePreference(appliedTimeFormat);
      await VoiceSettingsStore.savePreference(_voiceSettings);

      setState(() {
        _me = _copyUserWithLocalPreferences(
          ApiCurrentUser(
            id: updated.id,
            handle: updated.handle,
            username: updated.username,
            displayName: updated.displayName,
            avatarUrl: updated.avatarUrl,
            themePreference: updated.themePreference,
            language: appliedLanguage,
            timeFormat: appliedTimeFormat,
            compactMode: appliedCompact,
            showMessageTimestamps: appliedTimestamps,
            isPlatformAdmin: updated.isPlatformAdmin,
          ),
          appliedTheme,
          appliedLanguage,
          appliedTimeFormat,
        );
        _initialThemePreference = appliedTheme;
        _themePreference = appliedTheme;
        _initialLanguage = appliedLanguage;
        _language = appliedLanguage;
        _initialTimeFormat = appliedTimeFormat;
        _timeFormat = appliedTimeFormat;
        _compactMode = appliedCompact;
        _showMessageTimestamps = appliedTimestamps;
        _initialVoiceSettings = _voiceSettings;
        _saving = false;
        _didChange = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _strings()
                .t('settings_updated', fallback: 'User settings updated.'),
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      final shouldRetryCompatibility = error.message
          .contains('At least one settings field must be provided');

      if (shouldRetryCompatibility && _me != null) {
        try {
          final retry = await _client.updateMe(
            accessToken: widget.session.accessToken,
            username: _me!.username,
            timeFormat: _timeFormat,
            compactMode: _compactMode,
            showMessageTimestamps: _showMessageTimestamps,
          );

          if (!mounted) {
            return;
          }
          ref.read(backendSessionProvider.notifier).updateSessionHandle(
                retry.handle,
              );
          ref.read(appThemeModeProvider.notifier).state =
              themeModeFromPreference(_themePreference);
          await ThemePreferenceStore.savePreference(_themePreference);
          ref.read(appLanguageProvider.notifier).state = _language;
          await LanguagePreferenceStore.savePreference(_language);
          ref.read(appTimeFormatProvider.notifier).state =
              normalizeTimeFormatPreference(_timeFormat);
          await TimeFormatPreferenceStore.savePreference(_timeFormat);
          await VoiceSettingsStore.savePreference(_voiceSettings);
          setState(() {
            _me = _copyUserWithLocalPreferences(
              ApiCurrentUser(
                id: retry.id,
                handle: retry.handle,
                username: retry.username,
                displayName: retry.displayName,
                avatarUrl: retry.avatarUrl,
                themePreference: retry.themePreference,
                language: _language,
                timeFormat: _timeFormat,
                compactMode: _compactMode,
                showMessageTimestamps: _showMessageTimestamps,
                isPlatformAdmin: retry.isPlatformAdmin,
              ),
              _themePreference,
              _language,
              _timeFormat,
            );
            _initialThemePreference = _themePreference;
            _initialLanguage = _language;
            _initialTimeFormat = _timeFormat;
            _initialVoiceSettings = _voiceSettings;
            _saving = false;
            _didChange = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _strings()
                    .t('settings_updated', fallback: 'User settings updated.'),
              ),
            ),
          );
          return;
        } on ApiException catch (retryError) {
          if (!mounted) {
            return;
          }
          setState(() {
            _saving = false;
            _error = retryError.message;
          });
          return;
        } catch (_) {
          if (!mounted) {
            return;
          }
          setState(() {
            _saving = false;
            _error = _strings().t(
              'failed_update_settings',
              fallback: 'Failed to update user settings.',
            );
          });
          return;
        }
      }

      setState(() {
        _saving = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = _strings().t(
          'failed_update_settings',
          fallback: 'Failed to update user settings.',
        );
      });
    }
  }

  Future<void> _deleteAccount() async {
    if (_saving || _deleting) {
      return;
    }

    final password = _deletePasswordController.text.trim();
    if (password.isEmpty) {
      setState(() {
        _error = _strings().t(
          'delete_password_required',
          fallback: 'Current password is required to delete account.',
        );
      });
      return;
    }

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: Text(
                _strings().t('delete_account', fallback: 'Delete Account'),
              ),
              content: Text(
                _strings().t(
                  'delete_account_confirm',
                  fallback:
                      'This permanently deletes your account and cannot be undone.',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(_strings().t('cancel', fallback: 'Cancel')),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  ),
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(_strings().t('delete', fallback: 'Delete')),
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
      _deleting = true;
      _error = null;
    });

    try {
      await _client.deleteMe(
        accessToken: widget.session.accessToken,
        currentPassword: password,
      );

      if (!mounted) {
        return;
      }

      ref.read(backendSessionProvider.notifier).logout();
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _deleting = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _deleting = false;
        _error = _strings()
            .t('failed_delete_account', fallback: 'Failed to delete account.');
      });
    }
  }

  Future<void> _logout() async {
    if (_saving || _deleting) {
      return;
    }
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: Text(_strings().t('log_out', fallback: 'Log Out')),
              content: Text(
                _strings().t('log_out_confirm',
                    fallback: 'Log out from this session?'),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(_strings().t('cancel', fallback: 'Cancel')),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(_strings().t('log_out', fallback: 'Log Out')),
                ),
              ],
            );
          },
        ) ??
        false;
    if (!confirmed || !mounted) {
      return;
    }
    ref.read(backendSessionProvider.notifier).logout();
    Navigator.of(context).pop(false);
  }

  Future<void> _changeProfileImage() async {
    if (_loading || _saving || _deleting || _avatarWorking || _me == null) {
      return;
    }
    final strings = _strings();
    final picked = await pickAndCropSquareImage(
      context: context,
      strings: strings,
      withCircleUi: true,
    );
    if (picked == null) {
      return;
    }

    setState(() {
      _avatarWorking = true;
      _error = null;
    });
    try {
      final uploaded = await _client.uploadImageDirect(
        accessToken: widget.session.accessToken,
        contentType: picked.contentType,
        fileExtension: picked.fileExtension,
        data: picked.data,
      );
      final updated = await _client.updateMyAvatar(
        accessToken: widget.session.accessToken,
        imageUrl: uploaded.imageUrl,
        imageObjectKey: uploaded.imageObjectKey,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        final me = _me;
        if (me != null) {
          _me = ApiCurrentUser(
            id: me.id,
            handle: me.handle,
            username: me.username,
            displayName: me.displayName,
            avatarUrl: updated.avatarUrl,
            themePreference: me.themePreference,
            language: me.language,
            timeFormat: me.timeFormat,
            compactMode: me.compactMode,
            showMessageTimestamps: me.showMessageTimestamps,
            isPlatformAdmin: me.isPlatformAdmin,
          );
        }
        _didChange = true;
        _avatarWorking = false;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _avatarWorking = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _avatarWorking = false;
        _error = strings.t(
          'failed_update_profile_picture',
          fallback: 'Failed to update profile picture.',
        );
      });
    }
  }

  Future<void> _removeProfileImage() async {
    if (_loading || _saving || _deleting || _avatarWorking || _me == null) {
      return;
    }
    setState(() {
      _avatarWorking = true;
      _error = null;
    });
    try {
      final updated = await _client.clearMyAvatar(
        accessToken: widget.session.accessToken,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        final me = _me;
        if (me != null) {
          _me = ApiCurrentUser(
            id: me.id,
            handle: me.handle,
            username: me.username,
            displayName: me.displayName,
            avatarUrl: updated.avatarUrl,
            themePreference: me.themePreference,
            language: me.language,
            timeFormat: me.timeFormat,
            compactMode: me.compactMode,
            showMessageTimestamps: me.showMessageTimestamps,
            isPlatformAdmin: me.isPlatformAdmin,
          );
        }
        _didChange = true;
        _avatarWorking = false;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _avatarWorking = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _avatarWorking = false;
        _error = _strings().t(
          'failed_update_profile_picture',
          fallback: 'Failed to update profile picture.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = appStringsFor(ref.watch(appLanguageProvider));
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final compactLayout = viewportWidth < 980;
    final compactActions = viewportWidth < 520;
    if (!_loading &&
        _selectedSection == _SettingsSection.voiceAudio &&
        !_audioDevicesLoading &&
        _inputDevices.isEmpty &&
        _outputDevices.isEmpty &&
        _audioDevicesError == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _selectedSection != _SettingsSection.voiceAudio) {
          return;
        }
        unawaited(_loadAudioDevices());
      });
    }
    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          return;
        }
        _closeSettings();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: _closeSettings,
            icon: const Icon(Icons.arrow_back),
          ),
          title:
              Text(strings.t('user_settings_title', fallback: 'User Settings')),
          actions: [
            if (compactActions)
              IconButton(
                tooltip: strings.t('save_changes', fallback: 'Save Changes'),
                onPressed:
                    (_loading || _saving || _deleting) ? null : _saveSettings,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
              )
            else
              TextButton(
                onPressed:
                    (_loading || _saving || _deleting) ? null : _saveSettings,
                child: Text(
                  _saving
                      ? strings.t('saving', fallback: 'Saving...')
                      : strings.t('save_changes', fallback: 'Save Changes'),
                ),
              ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : compactLayout
                ? ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _SettingsSection.values.map((section) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(_sectionLabel(strings, section)),
                                selected: _selectedSection == section,
                                onSelected: (_) => _selectSection(section),
                              ),
                            );
                          }).toList(growable: false),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      _buildSelectedSectionContent(),
                    ],
                  )
                : Row(
                    children: [
                      Container(
                        width: 240,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFF1E1F22)
                            : const Color(0xFFE3E5E8),
                        child: ListView(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          children: [
                            _buildNavTile(
                              label: strings.t('my_account',
                                  fallback: 'My Account'),
                              section: _SettingsSection.account,
                              icon: Icons.person_outline,
                            ),
                            _buildNavTile(
                              label: strings.t('appearance',
                                  fallback: 'Appearance'),
                              section: _SettingsSection.appearance,
                              icon: Icons.palette_outlined,
                            ),
                            _buildNavTile(
                              label: strings.t('chat', fallback: 'Chat'),
                              section: _SettingsSection.chat,
                              icon: Icons.chat_bubble_outline,
                            ),
                            _buildNavTile(
                              label: strings.t(
                                'language_region',
                                fallback: 'Language & Region',
                              ),
                              section: _SettingsSection.languageRegion,
                              icon: Icons.language_outlined,
                            ),
                            _buildNavTile(
                              label: strings.t(
                                'voice_audio',
                                fallback: 'Voice & Audio',
                              ),
                              section: _SettingsSection.voiceAudio,
                              icon: Icons.graphic_eq_outlined,
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.all(20),
                          children: [
                            if (_error != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Text(
                                  _error!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                            _buildSelectedSectionContent(),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  String _sectionLabel(AppStrings strings, _SettingsSection section) {
    switch (section) {
      case _SettingsSection.account:
        return strings.t('my_account', fallback: 'My Account');
      case _SettingsSection.appearance:
        return strings.t('appearance', fallback: 'Appearance');
      case _SettingsSection.chat:
        return strings.t('chat', fallback: 'Chat');
      case _SettingsSection.languageRegion:
        return strings.t('language_region', fallback: 'Language & Region');
      case _SettingsSection.voiceAudio:
        return strings.t('voice_audio', fallback: 'Voice & Audio');
    }
  }

  Widget _buildSelectedSectionContent() {
    if (_selectedSection == _SettingsSection.account) {
      return _buildAccountSection();
    }
    if (_selectedSection == _SettingsSection.appearance) {
      return _buildAppearanceSection();
    }
    if (_selectedSection == _SettingsSection.chat) {
      return _buildChatSection();
    }
    if (_selectedSection == _SettingsSection.languageRegion) {
      return _buildLanguageRegionSection();
    }
    return _buildVoiceAudioSection();
  }

  void _selectSection(_SettingsSection section) {
    if (_selectedSection == section) {
      return;
    }
    if (_selectedSection == _SettingsSection.voiceAudio &&
        section != _SettingsSection.voiceAudio &&
        _voiceTestRunning) {
      _stopVoiceTest();
    }
    if (_selectedSection == _SettingsSection.voiceAudio &&
        section != _SettingsSection.voiceAudio) {
      unawaited(_stopMicLevelMonitor());
    }
    if (section == _SettingsSection.voiceAudio &&
        _selectedSection != _SettingsSection.voiceAudio) {
      unawaited(_loadAudioDevices());
    }
    setState(() {
      _selectedSection = section;
      _error = null;
    });
  }

  Widget _buildNavTile({
    required String label,
    required _SettingsSection section,
    required IconData icon,
  }) {
    return ListTile(
      selected: _selectedSection == section,
      leading: Icon(icon),
      title: Text(label),
      onTap: () => _selectSection(section),
    );
  }

  Widget _buildAccountSection() {
    final me = _me;
    final strings = _strings();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.t('my_account', fallback: 'My Account'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (me != null)
              Text(
                '${strings.t('handle', fallback: 'Handle')}: ${me.handle}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 620;
                final avatar = CircleAvatar(
                  radius: 36,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundImage: (me?.avatarUrl != null &&
                          me!.avatarUrl!.trim().isNotEmpty)
                      ? NetworkImage(me.avatarUrl!.trim())
                      : null,
                  child: Text(
                    (me?.username.isNotEmpty == true
                            ? me!.username.substring(0, 1)
                            : '?')
                        .toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                );
                final changeButton = FilledButton.tonalIcon(
                  onPressed: _avatarWorking ? null : _changeProfileImage,
                  icon: const Icon(Icons.image_outlined),
                  label: Text(
                    strings.t(
                      'change_profile_picture',
                      fallback: 'Change Profile Picture',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
                final removeButton = FilledButton.tonalIcon(
                  onPressed: (_avatarWorking || me?.avatarUrl == null)
                      ? null
                      : _removeProfileImage,
                  icon: const Icon(Icons.delete_outline),
                  label: Text(
                    strings.t(
                      'remove_profile_picture',
                      fallback: 'Remove Picture',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );

                if (stacked) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(child: avatar),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: changeButton,
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: removeButton,
                      ),
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    avatar,
                    const SizedBox(width: 12),
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          changeButton,
                          removeButton,
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _usernameController,
              decoration: InputDecoration(
                labelText: strings.t('username', fallback: 'Username'),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _displayNameController,
              decoration: InputDecoration(
                labelText: strings.t('display_name', fallback: 'Display Name'),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              strings.t('password', fallback: 'Password'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _currentPasswordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText:
                    strings.t('current_password', fallback: 'Current Password'),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _newPasswordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: strings.t('new_password', fallback: 'New Password'),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _confirmPasswordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: strings.t(
                  'confirm_new_password',
                  fallback: 'Confirm New Password',
                ),
              ),
            ),
            const SizedBox(height: 20),
            Divider(color: Theme.of(context).dividerColor),
            const SizedBox(height: 12),
            Text(
              strings.t('session', fallback: 'Session'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: _logout,
              icon: const Icon(Icons.logout),
              label: Text(strings.t('log_out', fallback: 'Log Out')),
            ),
            const SizedBox(height: 20),
            Divider(color: Theme.of(context).dividerColor),
            const SizedBox(height: 12),
            Text(
              strings.t('delete_account', fallback: 'Delete Account'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              strings.t(
                'delete_account_help',
                fallback:
                    'Enter your current password and confirm to permanently delete your account.',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _deletePasswordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: strings.t(
                  'delete_password_label',
                  fallback: 'Current Password (for delete)',
                ),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: _deleting ? null : _deleteAccount,
              child: Text(
                _deleting
                    ? strings.t('saving', fallback: 'Saving...')
                    : strings.t('delete_account', fallback: 'Delete Account'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppearanceSection() {
    final strings = _strings();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.t('appearance', fallback: 'Appearance'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('theme-$_themePreference'),
              initialValue: _themePreference,
              decoration: InputDecoration(
                labelText: strings.t('theme', fallback: 'Theme'),
              ),
              items: [
                DropdownMenuItem(
                  value: 'dark',
                  child: Text(strings.t('theme_dark', fallback: 'Dark')),
                ),
                DropdownMenuItem(
                  value: 'light',
                  child: Text(strings.t('theme_light', fallback: 'Light')),
                ),
                DropdownMenuItem(
                  value: 'system',
                  child: Text(
                      strings.t('theme_system', fallback: 'Sync with system')),
                ),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _themePreference = value;
                });
                ref.read(appThemeModeProvider.notifier).state =
                    themeModeFromPreference(value);
              },
            ),
            const SizedBox(height: 10),
            Text(
              strings.t(
                'appearance_help',
                fallback:
                    'Matches core appearance controls and can be expanded later.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageRegionSection() {
    final strings = _strings();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.t('language_region', fallback: 'Language & Region'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('language-$_language'),
              initialValue: _language,
              decoration: InputDecoration(
                labelText: strings.t('language', fallback: 'Language'),
              ),
              items: [
                DropdownMenuItem(
                  value: 'en-US',
                  child: Text(
                      strings.t('language_en_us', fallback: 'English (US)')),
                ),
                DropdownMenuItem(
                  value: 'zh-CN',
                  child: Text(
                    strings.t('language_zh_cn',
                        fallback: 'Chinese (Simplified)'),
                  ),
                ),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _language = normalizeLanguageCode(value);
                });
                ref.read(appLanguageProvider.notifier).state = _language;
              },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              key: ValueKey('time-format-$_timeFormat'),
              initialValue: _timeFormat,
              decoration: InputDecoration(
                labelText: strings.t('time_format', fallback: 'Time Format'),
              ),
              items: [
                DropdownMenuItem(
                  value: '24h',
                  child: Text(strings.t('time_24h', fallback: '24-hour')),
                ),
                DropdownMenuItem(
                  value: '12h',
                  child: Text(strings.t('time_12h', fallback: '12-hour')),
                ),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _timeFormat = value;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceSlider({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
    String? helper,
    double min = 0,
    double max = 200,
    int? divisions,
  }) {
    final rounded = value.round();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label)),
              Text('$rounded%'),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
          if (helper != null && helper.isNotEmpty)
            Text(
              helper,
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  Widget _buildVoicePanel({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF2B2D31)
            : const Color(0xFFF2F3F5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _buildVoiceAudioSection() {
    final strings = _strings();
    final selectedInputId = _voiceSettings.selectedInputDeviceId;
    final selectedOutputId = _voiceSettings.selectedOutputDeviceId;
    final hasSelectedInput = selectedInputId != null &&
        _inputDevices.any((d) => d.id == selectedInputId);
    final hasSelectedOutput = selectedOutputId != null &&
        _outputDevices.any((d) => d.deviceId == selectedOutputId);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.t('voice_audio', fallback: 'Voice & Audio'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (_audioDevicesLoading)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        strings.t(
                          'loading_audio_devices',
                          fallback: 'Loading audio devices...',
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            if (_audioDevicesError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  _audioDevicesError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            _buildVoicePanel(
              title: strings.t('voice_input', fallback: 'Input Settings'),
              children: [
                DropdownButtonFormField<String>(
                  key: ValueKey('voice-input-device-$selectedInputId'),
                  initialValue: hasSelectedInput ? selectedInputId : null,
                  decoration: InputDecoration(
                    labelText: strings.t(
                      'voice_input_device',
                      fallback: 'Input Device',
                    ),
                  ),
                  items: _inputDevices
                      .asMap()
                      .entries
                      .map(
                        (entry) => DropdownMenuItem<String>(
                          value: entry.value.id,
                          child:
                              Text(_inputDeviceLabel(entry.value, entry.key)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: _inputDevices.isEmpty
                      ? null
                      : (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _voiceSettings = _voiceSettings.copyWith(
                              selectedInputDeviceId: value,
                            );
                          });
                          unawaited(_restartMicMonitor());
                        },
                ),
                if (_inputDevices.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      strings.t(
                        'no_audio_input_devices',
                        fallback: 'No input devices found.',
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  key: ValueKey('voice-input-mode-${_voiceSettings.inputMode}'),
                  initialValue: _voiceSettings.inputMode,
                  decoration: InputDecoration(
                    labelText:
                        strings.t('voice_input_mode', fallback: 'Input Mode'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'voice_activity',
                      child: Text(
                        strings.t('voice_activity', fallback: 'Voice Activity'),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'push_to_talk',
                      child: Text(
                        strings.t('push_to_talk', fallback: 'Push to Talk'),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _voiceSettings =
                          _voiceSettings.copyWith(inputMode: value);
                    });
                  },
                ),
                const SizedBox(height: 12),
                _buildVoiceSlider(
                  label: strings.t('input_volume', fallback: 'Input Volume'),
                  value: _voiceSettings.inputVolume,
                  divisions: 40,
                  onChanged: (value) {
                    setState(() {
                      _voiceSettings =
                          _voiceSettings.copyWith(inputVolume: value);
                    });
                  },
                ),
                SwitchListTile.adaptive(
                  value: _voiceSettings.automaticInputSensitivity,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (value) {
                    setState(() {
                      _voiceSettings = _voiceSettings.copyWith(
                        automaticInputSensitivity: value,
                      );
                    });
                  },
                  title: Text(
                    strings.t(
                      'auto_input_sensitivity',
                      fallback: 'Automatically Determine Input Sensitivity',
                    ),
                  ),
                ),
                if (!_voiceSettings.automaticInputSensitivity)
                  _buildVoiceSlider(
                    label: strings.t(
                      'input_sensitivity',
                      fallback: 'Input Sensitivity',
                    ),
                    value: _voiceSettings.inputSensitivity,
                    onChanged: (value) {
                      setState(() {
                        _voiceSettings =
                            _voiceSettings.copyWith(inputSensitivity: value);
                      });
                    },
                    helper: strings.t(
                      'input_sensitivity_help',
                      fallback: 'Lower values pick up quieter voice input.',
                    ),
                    max: 100,
                    divisions: 20,
                  ),
                SwitchListTile.adaptive(
                  value: _voiceSettings.noiseSuppression,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (value) {
                    setState(() {
                      _voiceSettings =
                          _voiceSettings.copyWith(noiseSuppression: value);
                    });
                  },
                  title: Text(
                    strings.t(
                      'noise_suppression',
                      fallback: 'Noise Suppression',
                    ),
                  ),
                ),
                SwitchListTile.adaptive(
                  value: _voiceSettings.echoCancellation,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (value) {
                    setState(() {
                      _voiceSettings = _voiceSettings.copyWith(
                        echoCancellation: value,
                      );
                    });
                  },
                  title: Text(
                    strings.t(
                      'echo_cancellation',
                      fallback: 'Echo Cancellation',
                    ),
                  ),
                ),
              ],
            ),
            _buildVoicePanel(
              title: strings.t('voice_test', fallback: 'Mic Test'),
              children: [
                Wrap(
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _toggleVoiceTest,
                      icon: Icon(
                        _voiceTestRunning ? Icons.stop : Icons.play_arrow,
                      ),
                      label: Text(
                        _voiceTestRunning
                            ? strings.t('stop_test', fallback: 'Stop Test')
                            : strings.t('lets_check', fallback: "Let's Check"),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(
                        value: _micInputLevel.clamp(0, 1),
                        minHeight: 10,
                        borderRadius: BorderRadius.circular(999),
                        color: _micMeterError != null
                            ? Theme.of(context).colorScheme.error
                            : const Color(0xFF3BA55D),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text('${(_micInputLevel * 100).round()}%'),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _micMeterError ??
                      (_micMeterActive
                          ? strings.t('voice_mic_listening',
                              fallback: 'Listening...')
                          : strings.t('voice_mic_idle', fallback: 'Idle')),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _micMeterError != null
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).textTheme.bodySmall?.color,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  strings.t(
                    'voice_test_help',
                    fallback:
                        'Records your mic and plays it back so you can hear how it sounds.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (_voiceTestError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _voiceTestError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
            _buildVoicePanel(
              title: strings.t('voice_output', fallback: 'Output Settings'),
              children: [
                DropdownButtonFormField<String>(
                  key: ValueKey('voice-output-device-$selectedOutputId'),
                  initialValue: hasSelectedOutput ? selectedOutputId : null,
                  decoration: InputDecoration(
                    labelText: strings.t(
                      'voice_output_device',
                      fallback: 'Output Device',
                    ),
                  ),
                  items: _outputDevices
                      .asMap()
                      .entries
                      .map(
                        (entry) => DropdownMenuItem<String>(
                          value: entry.value.deviceId,
                          child:
                              Text(_outputDeviceLabel(entry.value, entry.key)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: _outputDevices.isEmpty
                      ? null
                      : (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _voiceSettings = _voiceSettings.copyWith(
                              selectedOutputDeviceId: value,
                            );
                          });
                          unawaited(_applySelectedOutputDevice());
                          unawaited(_restartMicLoopbackIfTesting());
                        },
                ),
                if (_outputDevices.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      strings.t(
                        'no_audio_output_devices',
                        fallback: 'No output devices found.',
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                _buildVoiceSlider(
                  label: strings.t('output_volume', fallback: 'Output Volume'),
                  value: _voiceSettings.outputVolume,
                  divisions: 40,
                  onChanged: (value) {
                    setState(() {
                      _voiceSettings =
                          _voiceSettings.copyWith(outputVolume: value);
                    });
                  },
                ),
              ],
            ),
            _buildVoicePanel(
              title: strings.t('voice_behavior', fallback: 'Behavior'),
              children: [
                SwitchListTile.adaptive(
                  value: _voiceSettings.playJoinLeaveSound,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (value) {
                    setState(() {
                      _voiceSettings =
                          _voiceSettings.copyWith(playJoinLeaveSound: value);
                    });
                  },
                  title: Text(
                    strings.t(
                      'voice_join_leave_sound',
                      fallback: 'Play Join/Leave Sound',
                    ),
                  ),
                ),
                SwitchListTile.adaptive(
                  value: _voiceSettings.playMuteDeafenSound,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (value) {
                    setState(() {
                      _voiceSettings = _voiceSettings.copyWith(
                        playMuteDeafenSound: value,
                      );
                    });
                  },
                  title: Text(
                    strings.t(
                      'voice_mute_deafen_sound',
                      fallback: 'Play Mute/Deafen Sound',
                    ),
                  ),
                ),
                SwitchListTile.adaptive(
                  value: _voiceSettings.startMutedOnJoin,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (value) {
                    setState(() {
                      _voiceSettings = _voiceSettings.copyWith(
                        startMutedOnJoin: value,
                      );
                    });
                  },
                  title: Text(
                    strings.t(
                      'voice_start_muted',
                      fallback: 'Start with Mic Muted',
                    ),
                  ),
                ),
                SwitchListTile.adaptive(
                  value: _voiceSettings.startDeafenedOnJoin,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (value) {
                    setState(() {
                      _voiceSettings = _voiceSettings.copyWith(
                        startDeafenedOnJoin: value,
                      );
                    });
                  },
                  title: Text(
                    strings.t(
                      'voice_start_deafened',
                      fallback: 'Start with Headphones Deafened',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatSection() {
    final strings = _strings();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.t('chat', fallback: 'Chat'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              value: _compactMode,
              contentPadding: EdgeInsets.zero,
              onChanged: (value) {
                setState(() {
                  _compactMode = value;
                });
              },
              title: Text(
                strings.t('compact_mode', fallback: 'Compact Message Display'),
              ),
              subtitle: Text(
                strings.t(
                  'compact_mode_help',
                  fallback: 'Reduce spacing between messages in compact mode.',
                ),
              ),
            ),
            SwitchListTile.adaptive(
              value: _showMessageTimestamps,
              contentPadding: EdgeInsets.zero,
              onChanged: (value) {
                setState(() {
                  _showMessageTimestamps = value;
                });
              },
              title: Text(
                strings.t('show_timestamps',
                    fallback: 'Show Message Timestamps'),
              ),
              subtitle: Text(
                strings.t(
                  'show_timestamps_help',
                  fallback: 'Display timestamp next to each message.',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
