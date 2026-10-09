import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/constants/app_constants.dart';
import 'core/db/app_database.dart';
import 'features/auth/auth_repository.dart';
import 'features/auth/session_provider.dart';
import 'features/profile/theme_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ВАЖНО (подводный камень №1 из плана): ВСЯ инициализация — строго ДО runApp.
  // В противном случае возможны мигание темы (сначала дефолтная, потом
  // сохранённая) и гонка с редиректами go_router.

  // 1. Подмена фабрики sqflite на desktop (подводный камень №3): на Linux/
  //    Windows фабрика sqflite_common_ffi, на Android/iOS — штатная.
  AppDatabase.configureDatabaseFactory();

  // 2. Сессия и настройки: один общий экземпляр prefs для всего приложения.
  final prefs = await SharedPreferences.getInstance();

  // 3. Тема из сохранённых настроек (ключ `session_theme`).
  final initialThemeMode = ThemeProvider.modeFromString(
    prefs.getString(AppConstants.prefSessionTheme),
  );

  // 4. БД: открытие + CREATE TABLE при первом запуске (схема v1).
  final db = await AppDatabase.instance.open();

  // 5. Auth-слой: репозиторий + сессия; восстановление сессии ДО runApp —
  //    тогда redirect-guard сразу знает, вошёл пользователь или гость.
  final authRepository = AuthRepository(db: db, prefs: prefs);
  final session = SessionProvider(repository: authRepository);
  await session.restoreSession();

  runApp(
    MobKursApp(
      prefs: prefs,
      initialThemeMode: initialThemeMode,
      session: session,
    ),
  );
}
