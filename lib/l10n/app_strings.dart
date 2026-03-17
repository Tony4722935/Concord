import 'package:concord/l10n/en_us_strings.dart';
import 'package:concord/l10n/zh_cn_strings.dart';

class AppStrings {
  const AppStrings(this._values);

  final Map<String, String> _values;

  String t(String key, {String fallback = ''}) {
    return _values[key] ?? fallback;
  }

  String tf(
    String key,
    Map<String, String> values, {
    String fallback = '',
  }) {
    var template = t(key, fallback: fallback);
    values.forEach((name, value) {
      template = template.replaceAll('{$name}', value);
    });
    return template;
  }
}

AppStrings appStringsFor(String languageCode) {
  switch (languageCode.trim()) {
    case 'zh-CN':
      return const AppStrings(zhCnStrings);
    case 'en-US':
    default:
      return const AppStrings(enUsStrings);
  }
}
