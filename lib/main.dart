import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:concord/app.dart';
import 'package:concord/core/time/time_format_preference_store.dart';
import 'package:concord/core/time/time_format_provider.dart';
import 'package:concord/core/theme/theme_mode_provider.dart';
import 'package:concord/core/theme/theme_preference_store.dart';
import 'package:concord/data/db/concord_database.dart';
import 'package:concord/data/state/concord_controller.dart';
import 'package:concord/l10n/language_preference_store.dart';
import 'package:concord/l10n/language_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('en_US');
  await initializeDateFormatting('zh_CN');

  final database = await ConcordDatabase.openDefault();
  final cachedThemePreference = await ThemePreferenceStore.loadPreference();
  final cachedLanguagePreference =
      await LanguagePreferenceStore.loadPreference();
  final cachedTimeFormatPreference =
      await TimeFormatPreferenceStore.loadPreference();
  final initialThemeMode = cachedThemePreference == null
      ? ThemeMode.dark
      : themeModeFromPreference(cachedThemePreference);
  final initialLanguage = cachedLanguagePreference == null
      ? 'en-US'
      : normalizeLanguageCode(cachedLanguagePreference);
  final initialTimeFormat = cachedTimeFormatPreference == null
      ? '24h'
      : normalizeTimeFormatPreference(cachedTimeFormatPreference);

  runApp(
    ProviderScope(
      overrides: [
        concordDatabaseProvider.overrideWithValue(database),
        appThemeModeProvider.overrideWith((ref) => initialThemeMode),
        appLanguageProvider.overrideWith((ref) => initialLanguage),
        appTimeFormatProvider.overrideWith((ref) => initialTimeFormat),
      ],
      child: const ConcordApp(),
    ),
  );
}
