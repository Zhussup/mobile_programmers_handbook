import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/session_provider.dart';
import 'features/profile/theme_provider.dart';
import 'router/app_router.dart';

/// Корневой виджет приложения.
///
/// Провайдеры: [SessionProvider] (восстановлен в main() до runApp) и
/// [ThemeProvider]. Тема инициализируется ДО runApp — не мигает и сохраняется
/// при перезапуске (подводный камень №1 из плана).
class MobKursApp extends StatefulWidget {
  const MobKursApp({
    super.key,
    required this.prefs,
    required this.initialThemeMode,
    required this.session,
    this.initialLocation,
  });

  /// Общий экземпляр SharedPreferences (загружен один раз в main()).
  final SharedPreferences prefs;

  /// Тема, сохранённая при прошлых запусках (из ключа `session_theme`).
  final ThemeMode initialThemeMode;

  /// Сессия (восстановлена в main() до runApp).
  final SessionProvider session;

  /// Стартовый маршрут — параметр для виджет-тестов (в приложении — /splash).
  final String? initialLocation;

  @override
  State<MobKursApp> createState() => _MobKursAppState();
}

class _MobKursAppState extends State<MobKursApp> {
  // Роутер создаётся один раз (не в build — иначе пересоздание при смене
  // темы сбрасывало бы навигацию).
  late final GoRouter _router = buildAppRouter(
    widget.session,
    initialLocation: widget.initialLocation,
  );

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // .value: сессия создана и восстановлена в main(), а не здесь.
        ChangeNotifierProvider.value(value: widget.session),
        ChangeNotifierProvider(
          create: (_) => ThemeProvider(
            prefs: widget.prefs,
            initialMode: widget.initialThemeMode,
          ),
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) => MaterialApp.router(
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: themeProvider.mode,
          routerConfig: _router,
        ),
      ),
    );
  }
}
