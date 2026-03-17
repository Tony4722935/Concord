import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "package:concord/backend/backend_gate_screen.dart";
import "package:concord/core/theme/app_theme.dart";
import "package:concord/core/theme/theme_mode_provider.dart";
import "package:concord/l10n/language_provider.dart";

class ConcordApp extends ConsumerWidget {
  const ConcordApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(appThemeModeProvider);
    final languageCode = normalizeLanguageCode(ref.watch(appLanguageProvider));
    final languageParts = languageCode.split('-');
    final locale = languageParts.length == 2
        ? Locale(languageParts[0], languageParts[1])
        : const Locale('en', 'US');
    return MaterialApp(
      title: "Concord",
      debugShowCheckedModeBanner: false,
      locale: locale,
      theme: AppTheme.light(languageCode: languageCode),
      darkTheme: AppTheme.dark(languageCode: languageCode),
      themeMode: themeMode,
      home: const BackendGateScreen(),
    );
  }
}
