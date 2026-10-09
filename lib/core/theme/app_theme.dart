import 'package:flutter/material.dart';

/// Фирменные цвета проекта: единые для тем приложения, нативного сплэша и лого.
class BrandColors {
  BrandColors._();

  /// Фирменный тёмный фон (фон нативного сплэша — см. flutter_native_splash
  /// в pubspec.yaml).
  static const Color background = Color(0xFF1E2A37);

  /// Бирюзовый акцент (символ «</>» в лого).
  static const Color accent = Color(0xFF66E2D5);

  /// Единая seed-палитра для светлой и тёмной темы (ColorScheme.fromSeed).
  static const Color seed = Color(0xFF2AA79B);
}

/// Темы приложения (Material 3): светлая и тёмная строится из одной seed-палитры.
class AppTheme {
  AppTheme._();

  /// Светлая тема.
  static ThemeData light() => _base(Brightness.light);

  /// Тёмная тема.
  static ThemeData dark() => _base(Brightness.dark);

  /// Общая база тем: Material 3 + ColorScheme.fromSeed + общие компоненты.
  static ThemeData _base(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: BrandColors.seed,
      brightness: brightness,
    );

    final dark = brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // Заголовки на тёмном фоне — читаемые, но не «висящие» (заголовок AppBar).
      scaffoldBackgroundColor: dark ? BrandColors.background : scheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: dark ? BrandColors.background : scheme.primary,
        foregroundColor: dark ? scheme.onSurface : scheme.onPrimary,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: scheme.primaryContainer,
        backgroundColor: dark ? const Color(0xFF26323F) : null,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
