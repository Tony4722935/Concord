import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:concord/core/time/time_format_provider.dart';

class TimeFormatPreferenceStore {
  static String _filePath() {
    return p.join(
      Directory.current.path,
      '.concord_data',
      'time_format_pref.txt',
    );
  }

  static Future<String?> loadPreference() async {
    try {
      final file = File(_filePath());
      if (!file.existsSync()) {
        return null;
      }
      final raw = (await file.readAsString()).trim();
      return normalizeTimeFormatPreference(raw);
    } catch (_) {
      return null;
    }
  }

  static Future<void> savePreference(String timeFormat) async {
    final normalized = normalizeTimeFormatPreference(timeFormat);
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

