import 'dart:io';

import 'package:path/path.dart' as p;

class ThemePreferenceStore {
  static String _filePath() {
    return p.join(Directory.current.path, '.concord_data', 'theme_pref.txt');
  }

  static Future<String?> loadPreference() async {
    try {
      final file = File(_filePath());
      if (!file.existsSync()) {
        return null;
      }
      final raw = (await file.readAsString()).trim().toLowerCase();
      if (raw == 'dark' || raw == 'light' || raw == 'system') {
        return raw;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> savePreference(String preference) async {
    final normalized = preference.trim().toLowerCase();
    if (normalized != 'dark' &&
        normalized != 'light' &&
        normalized != 'system') {
      return;
    }

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
