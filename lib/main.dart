import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/constants/app_constants.dart';
import 'core/db/app_database.dart';
import 'core/network/api_client.dart';
import 'features/auth/auth_repository.dart';
import 'features/auth/auth_repository_base.dart';
import 'features/auth/remote_auth_repository.dart';
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

  // 4. БД: открытие + CREATE TABLE при первом запуске. В API-режиме та же
  //    база используется как кэш контента/пользовательских данных.
  final db = await AppDatabase.instance.open();

  // 5. API-клиент и auth-слой. `AppConfig.useApi` — переключатель режима:
  //    true (по умолчанию в приложении) — backend, false — локальные
  //    репозитории (офлайн-демонстрация).
  final useApi = AppConfig.useApi;
  ApiClient? apiClient;
  AuthRepositoryBase authRepository;
  if (useApi) {
    apiClient = ApiClient(
      baseUrl: AppConfig.apiBaseUrl,
      tokenStore: PrefsTokenStore(prefs),
      timeout: AppConfig.apiTimeout,
    );
    authRepository = RemoteAuthRepository(apiClient: apiClient, prefs: prefs);
  } else {
    authRepository = AuthRepository(db: db, prefs: prefs);
  }

  // 6. Сессия: восстановление ДО runApp — redirect-guard сразу знает статус.
  //    В API-режиме при наличии токена выполняется GET /auth/me.
  final session = SessionProvider(repository: authRepository);

  // 401 → выход на /login, 403 user_blocked → сообщение и выход.
  if (apiClient != null) {
    apiClient.onUnauthorized = session.handleUnauthorized;
    apiClient.onUserBlocked = session.handleBlocked;
  }

  await session.restoreSession();

  runApp(
    MobKursApp(
      prefs: prefs,
      initialThemeMode: initialThemeMode,
      session: session,
      apiClient: apiClient,
    ),
  );
}
