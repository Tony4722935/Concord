import 'package:flutter_riverpod/flutter_riverpod.dart';

final appTimeFormatProvider = StateProvider<String>((ref) => '24h');

String normalizeTimeFormatPreference(String raw) {
  final normalized = raw.trim().toLowerCase();
  if (normalized == '12h') {
    return '12h';
  }
  return '24h';
}

