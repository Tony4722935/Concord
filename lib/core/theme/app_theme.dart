import 'package:flutter/material.dart';

class AppTheme {
  static const PageTransitionsTheme _pageTransitionsTheme =
      PageTransitionsTheme(
    builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.fuchsia: FadeForwardsPageTransitionsBuilder(),
    },
  );

  static String _primaryFontForLanguage(String languageCode) {
    if (languageCode == 'zh-CN') {
      return 'Microsoft YaHei UI';
    }
    return 'Segoe UI';
  }

  static List<String> _fontFallbackForLanguage(String languageCode) {
    if (languageCode == 'zh-CN') {
      return const [
        'Microsoft YaHei',
        'PingFang SC',
        'Noto Sans CJK SC',
        'SimHei',
        'Segoe UI',
      ];
    }
    return const [
      'Segoe UI Variable',
      'gg sans',
      'Helvetica Neue',
      'Arial',
      'Noto Sans',
    ];
  }

  static ThemeData dark({String languageCode = 'en-US'}) {
    const canvas = Color(0xFF1E1F22);
    const surface = Color(0xFF2B2D31);
    const surfaceAlt = Color(0xFF313338);
    const accent = Color(0xFF5865F2);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: canvas,
      fontFamily: _primaryFontForLanguage(languageCode),
      fontFamilyFallback: _fontFallbackForLanguage(languageCode),
      colorScheme: const ColorScheme.dark(
        primary: accent,
        secondary: Color(0xFF57F287),
        surface: surface,
      ),
      pageTransitionsTheme: _pageTransitionsTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF212327),
        thickness: 1,
      ),
      listTileTheme: const ListTileThemeData(
        textColor: Color(0xFFDCDDDE),
        iconColor: Color(0xFFB5BAC1),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceAlt,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  static ThemeData light({String languageCode = 'en-US'}) {
    const canvas = Color(0xFFF2F3F5);
    const surface = Color(0xFFFFFFFF);
    const surfaceAlt = Color(0xFFE8EAED);
    const accent = Color(0xFF5865F2);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: canvas,
      fontFamily: _primaryFontForLanguage(languageCode),
      fontFamilyFallback: _fontFallbackForLanguage(languageCode),
      colorScheme: const ColorScheme.light(
        primary: accent,
        secondary: Color(0xFF2D7D46),
        surface: surface,
      ),
      pageTransitionsTheme: _pageTransitionsTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFFD9DBDF),
        thickness: 1,
      ),
      listTileTheme: const ListTileThemeData(
        textColor: Color(0xFF2E3338),
        iconColor: Color(0xFF4F5660),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceAlt,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
