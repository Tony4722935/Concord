import 'package:flutter_riverpod/flutter_riverpod.dart';

final appLanguageProvider = StateProvider<String>((ref) => 'en-US');

String normalizeLanguageCode(String raw) {
  final trimmed = raw.trim();
  if (trimmed == 'zh-CN') {
    return 'zh-CN';
  }
  return 'en-US';
}
