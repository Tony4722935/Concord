import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:concord/l10n/language_provider.dart';

class LanguagePreferenceStore {
  static String _filePath() {
    return p.join(Directory.current.path, '.concord_data', 'language_pref.txt');
  }

  static Future<String?> loadPreference() async {
    try {
      final file = File(_filePath());
      if (!file.existsSync()) {
        return null;
      }
      final raw = (await file.readAsString()).trim();
      return normalizeLanguageCode(raw);
    } catch (_) {
      return null;
    }
  }

  static Future<void> savePreference(String languageCode) async {
    final normalized = normalizeLanguageCode(languageCode);
    try {
      final directory =
          Directory(p.join(Directory.current.path, '.concord_data'));
      if (!directory.existsSync()) {
        directory.createSync(recursive: true);
      }
      final file = File(_filePath());
      await file.writeAsString(normalized, flush: true);
    } catch (_) {
      // Best-effort local preference cache.
    }
  }
}
