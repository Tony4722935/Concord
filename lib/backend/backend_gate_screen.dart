import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:concord/backend/backend_mobile_shell_screen.dart';
import 'package:concord/backend/backend_session.dart';
import 'package:concord/backend/backend_servers_screen.dart';
import 'package:concord/l10n/app_strings.dart';
import 'package:concord/l10n/language_provider.dart';

class BackendGateScreen extends ConsumerStatefulWidget {
  const BackendGateScreen({super.key});

  @override
  ConsumerState<BackendGateScreen> createState() => _BackendGateScreenState();
}

class _BackendGateScreenState extends ConsumerState<BackendGateScreen>
    with TickerProviderStateMixin {
  final TextEditingController _identifierController = TextEditingController();
  final TextEditingController _loginPasswordController =
      TextEditingController();
  final TextEditingController _registerUsernameController =
      TextEditingController();
  final TextEditingController _registerDisplayNameController =
      TextEditingController();
  final TextEditingController _registerTagController = TextEditingController();
  final TextEditingController _registerPasswordController =
      TextEditingController();
  final TextEditingController _registerConfirmPasswordController =
      TextEditingController();

  late final AnimationController _backgroundFlowController;
  late final AnimationController _orbDriftController;

  bool _registerMode = false;
  String? _localError;

  AppStrings _strings() => appStringsFor(ref.read(appLanguageProvider));

  String _t(String key, String fallback) {
    return _strings().t(key, fallback: fallback);
  }

  @override
  void initState() {
    super.initState();
    _backgroundFlowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();
    _orbDriftController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 11),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _backgroundFlowController.dispose();
    _orbDriftController.dispose();
    _identifierController.dispose();
    _loginPasswordController.dispose();
    _registerUsernameController.dispose();
    _registerDisplayNameController.dispose();
    _registerTagController.dispose();
    _registerPasswordController.dispose();
    _registerConfirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sessionState = ref.watch(backendSessionProvider);
    final controller = ref.read(backendSessionProvider.notifier);
    final strings = appStringsFor(ref.watch(appLanguageProvider));

    if (sessionState.session != null) {
      return LayoutBuilder(
        builder: (context, constraints) {
          const mobileBreakpoint = 900.0;
          if (constraints.maxWidth < mobileBreakpoint) {
            return BackendMobileShellScreen(
              session: sessionState.session!,
              baseUrl: sessionState.baseUrl,
            );
          }
          return BackendServersScreen(
            session: sessionState.session!,
            baseUrl: sessionState.baseUrl,
          );
        },
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: _AnimatedGateBackground(
              flow: _backgroundFlowController,
              drift: _orbDriftController,
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.08),
                    Colors.black.withValues(alpha: 0.24),
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF171B28).withValues(alpha: 0.78),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x66000000),
                            blurRadius: 30,
                            spreadRadius: 2,
                            offset: Offset(0, 14),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.fromLTRB(26, 24, 26, 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(13),
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF7A68FF),
                                      Color(0xFF4EC5FF),
                                    ],
                                  ),
                                ),
                                padding: const EdgeInsets.all(6),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(9),
                                  child: Image.asset(
                                    'assets/icons/icon-topbar.png',
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _registerMode
                                          ? strings.t(
                                              'backend_register_title',
                                              fallback: 'Concord Register',
                                            )
                                          : strings.t(
                                              'backend_login_title',
                                              fallback: 'Concord Login',
                                            ),
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall
                                          ?.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(13),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.08),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: FilledButton.tonal(
                                    onPressed: _registerMode
                                        ? () {
                                            setState(() {
                                              _registerMode = false;
                                              _localError = null;
                                            });
                                            controller.clearError();
                                          }
                                        : null,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: _registerMode
                                          ? Colors.transparent
                                          : const Color(0xFF5865F2),
                                      foregroundColor: Colors.white,
                                      disabledBackgroundColor:
                                          const Color(0xFF5865F2),
                                      disabledForegroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    child: Text(
                                      strings.t('sign_in', fallback: 'Sign In'),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: FilledButton.tonal(
                                    onPressed: !_registerMode
                                        ? () {
                                            setState(() {
                                              _registerMode = true;
                                              _localError = null;
                                            });
                                            controller.clearError();
                                          }
                                        : null,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: !_registerMode
                                          ? Colors.transparent
                                          : const Color(0xFF5865F2),
                                      foregroundColor: Colors.white,
                                      disabledBackgroundColor:
                                          const Color(0xFF5865F2),
                                      disabledForegroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    child: Text(
                                      strings.t('register', fallback: 'Register'),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          if (_registerMode) ...[
                            TextField(
                              controller: _registerUsernameController,
                              decoration: _fieldDecoration(
                                strings.t('username', fallback: 'Username'),
                                strings.t('username_hint', fallback: 'yourname'),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _registerDisplayNameController,
                              decoration: _fieldDecoration(
                                strings.t(
                                  'display_name_optional',
                                  fallback: 'Display Name (Optional)',
                                ),
                                '',
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _registerTagController,
                              keyboardType: TextInputType.number,
                              decoration: _fieldDecoration(
                                strings.t(
                                  'tag_number_optional',
                                  fallback: 'Tag Number (Optional)',
                                ),
                                strings.t('tag_number_hint', fallback: '0001'),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _registerPasswordController,
                              obscureText: true,
                              decoration: _fieldDecoration(
                                strings.t('password', fallback: 'Password'),
                                '',
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _registerConfirmPasswordController,
                              obscureText: true,
                              decoration: _fieldDecoration(
                                strings.t(
                                  'confirm_password',
                                  fallback: 'Confirm Password',
                                ),
                                '',
                              ),
                              onSubmitted: (_) => _submitRegister(controller),
                            ),
                          ] else ...[
                            TextField(
                              controller: _identifierController,
                              decoration: _fieldDecoration(
                                strings.t('identifier', fallback: 'Identifier'),
                                strings.t(
                                  'identifier_hint',
                                  fallback: 'username#0001',
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _loginPasswordController,
                              obscureText: true,
                              decoration: _fieldDecoration(
                                strings.t('password', fallback: 'Password'),
                                '',
                              ),
                              onSubmitted: (_) => _submitLogin(controller),
                            ),
                          ],
                          const SizedBox(height: 16),
                          if (_localError != null ||
                              sessionState.errorMessage != null) ...[
                            Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .error
                                    .withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .error
                                      .withValues(alpha: 0.32),
                                ),
                              ),
                              padding: const EdgeInsets.all(10),
                              child: Text(
                                _localError ?? sessionState.errorMessage!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: sessionState.isLoading
                                  ? null
                                  : () {
                                      if (_registerMode) {
                                        _submitRegister(controller);
                                      } else {
                                        _submitLogin(controller);
                                      }
                                    },
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF5865F2),
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                sessionState.isLoading
                                    ? (_registerMode
                                        ? strings.t(
                                            'registering',
                                            fallback: 'Registering...',
                                          )
                                        : strings.t(
                                            'signing_in',
                                            fallback: 'Signing In...',
                                          ))
                                    : (_registerMode
                                        ? strings.t(
                                            'create_account',
                                            fallback: 'Create Account',
                                          )
                                        : strings.t(
                                            'sign_in',
                                            fallback: 'Sign In',
                                          )),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: SafeArea(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.16),
                  ),
                ),
                child: IconButton(
                  tooltip: strings.t(
                    'connection_settings',
                    fallback: 'Connection Settings',
                  ),
                  onPressed: () =>
                      _showConnectionSettings(sessionState, controller),
                  icon: const Icon(Icons.tune_rounded),
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint.isEmpty ? null : hint,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.09),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: Color(0xFF6E7AFF),
          width: 1.4,
        ),
      ),
    );
  }

  Future<void> _showConnectionSettings(
    BackendSessionState sessionState,
    BackendSessionController controller,
  ) async {
    final strings = _strings();
    final currentBaseUrl = sessionState.baseUrl.trim();
    final startsAsDefault = currentBaseUrl == defaultBackendBaseUrl;
    final inputController = TextEditingController(
      text: startsAsDefault ? '' : currentBaseUrl,
    );

    final submitted = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: Text(
                strings.t(
                  'connection_settings',
                  fallback: 'Connection Settings',
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: inputController,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText:
                          strings.t('api_base_url', fallback: 'API Base URL'),
                      hintText: defaultBackendBaseUrl,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    strings.t(
                      'api_url_optional_help',
                      fallback: 'Leave blank to use the default server URL.',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(strings.t('cancel', fallback: 'Cancel')),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(strings.t('save', fallback: 'Save')),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!submitted) {
      inputController.dispose();
      return;
    }

    controller.setBaseUrl(inputController.text);
    inputController.dispose();
  }

  Future<void> _submitLogin(BackendSessionController controller) async {
    setState(() {
      _localError = null;
    });
    await controller.login(
      identifier: _identifierController.text,
      password: _loginPasswordController.text,
    );
  }

  Future<void> _submitRegister(BackendSessionController controller) async {
    setState(() {
      _localError = null;
    });
    final password = _registerPasswordController.text;
    final confirm = _registerConfirmPasswordController.text;
    if (password != confirm) {
      setState(() {
        _localError = _t('passwords_not_match', 'Passwords do not match.');
      });
      return;
    }

    await controller.register(
      username: _registerUsernameController.text,
      password: password,
      displayName: _registerDisplayNameController.text,
      preferredTag: _registerTagController.text,
    );
  }
}

class _AnimatedGateBackground extends StatelessWidget {
  const _AnimatedGateBackground({
    required this.flow,
    required this.drift,
  });

  final Animation<double> flow;
  final Animation<double> drift;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([flow, drift]),
      builder: (context, _) {
        final t = flow.value * math.pi * 2;
        final d = drift.value * math.pi * 2;
        return LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment(math.sin(t) * 0.65, -1),
                      end: Alignment(-math.cos(t * 0.8) * 0.65, 1),
                      colors: const [
                        Color(0xFF090B13),
                        Color(0xFF141A2C),
                        Color(0xFF1A1A34),
                      ],
                    ),
                  ),
                  child: const SizedBox.expand(),
                ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: _BackgroundMeshPainter(progress: flow.value),
                  ),
                ),
                _orb(
                  left: constraints.maxWidth * 0.08 + math.sin(d) * 18,
                  top: constraints.maxHeight * 0.10 + math.cos(d * 0.8) * 14,
                  size: 260,
                  color: const Color(0xFF7A68FF),
                ),
                _orb(
                  left: constraints.maxWidth * 0.72 + math.cos(d * 0.85) * 16,
                  top: constraints.maxHeight * 0.16 + math.sin(d * 1.1) * 16,
                  size: 220,
                  color: const Color(0xFF3AA2FF),
                ),
                _orb(
                  left: constraints.maxWidth * 0.62 + math.sin(d * 0.75) * 15,
                  top: constraints.maxHeight * 0.64 + math.cos(d) * 20,
                  size: 280,
                  color: const Color(0xFF4DD0C7),
                ),
                _orb(
                  left: constraints.maxWidth * 0.20 + math.cos(d * 0.9) * 18,
                  top: constraints.maxHeight * 0.72 + math.sin(d * 0.7) * 12,
                  size: 190,
                  color: const Color(0xFF5E75FF),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _orb({
    required double left,
    required double top,
    required double size,
    required Color color,
  }) {
    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.22),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.55),
                blurRadius: 90,
                spreadRadius: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackgroundMeshPainter extends CustomPainter {
  _BackgroundMeshPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.055);
    final glowPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF9BA8FF).withValues(alpha: 0.12);
    const spacing = 54.0;
    final driftX = math.sin(progress * math.pi * 2) * 22;
    final driftY = math.cos(progress * math.pi * 2) * 16;

    for (double x = -spacing; x <= size.width + spacing; x += spacing) {
      canvas.drawLine(
        Offset(x + driftX, 0),
        Offset(x - driftX * 0.7, size.height),
        linePaint,
      );
    }
    for (double y = -spacing; y <= size.height + spacing; y += spacing) {
      canvas.drawLine(
        Offset(0, y + driftY),
        Offset(size.width, y - driftY * 0.65),
        linePaint,
      );
    }

    final centerA = Offset(
      size.width * 0.26 + math.sin(progress * math.pi * 2.0) * 26,
      size.height * 0.30 + math.cos(progress * math.pi * 2.2) * 20,
    );
    final centerB = Offset(
      size.width * 0.74 + math.cos(progress * math.pi * 1.7) * 24,
      size.height * 0.63 + math.sin(progress * math.pi * 1.9) * 18,
    );
    canvas.drawCircle(centerA, 90, glowPaint);
    canvas.drawCircle(centerB, 70, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _BackgroundMeshPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
