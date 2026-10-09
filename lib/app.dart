import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' show Database;

import 'core/constants/app_constants.dart';
import 'core/db/app_database.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/session_provider.dart';
import 'features/playground/playground_draft_provider.dart';
import 'features/playground/snippet_provider.dart';
import 'features/playground/snippet_repository.dart';
import 'features/profile/profile_repository.dart';
import 'features/profile/theme_provider.dart';
import 'features/reference/article_repository.dart';
import 'features/reference/favorites_provider.dart';
import 'features/reference/favorites_repository.dart';
import 'features/reference/history_provider.dart';
import 'features/reference/history_repository.dart';
import 'features/reference/reference_provider.dart';
import 'features/search/search_provider.dart';
import 'router/app_router.dart';

/// Корневой виджет приложения.
///
/// Провайдеры: [SessionProvider] (восстановлен в main() до runApp),
/// [ThemeProvider] и [ReferenceProvider] (контент справочника). Тема
/// инициализируется ДО runApp — не мигает и сохраняется (подводный камень
/// №1 из плана).
class MobKursApp extends StatefulWidget {
  const MobKursApp({
    super.key,
    required this.prefs,
    required this.initialThemeMode,
    required this.session,
    this.initialLocation,
    this.referenceRepository,
    this.database,
  });

  /// Общий экземпляр SharedPreferences (загружен один раз в main()).
  final SharedPreferences prefs;

  /// Тема, сохранённая при прошлых запусках (из ключа `session_theme`).
  final ThemeMode initialThemeMode;

  /// Сессия (восстановлена в main() до runApp).
  final SessionProvider session;

  /// Стартовый маршрут — параметр для виджет-тестов (в приложении — /splash).
  final String? initialLocation;

  /// Репозиторий справочника.
  ///
  /// Production: null → обычный репозиторий (JSON из ассетов через
  /// rootBundle). Тесты передают репозиторий из сырых строк
  /// ([ArticleRepository.fromRaw]) — rootBundle IO недоступен в fake-async.
  final ArticleRepository? referenceRepository;

  /// БД пользовательских данных (favorites/history — P9).
  ///
  /// Production: null → AppDatabase.instance (открыта в main() до runApp,
  /// подводный камень №3). В тестах каркас передаёт свою in-memory базу.
  final Database? database;

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

  /// Репозиторий справочника: тестовый (fromRaw) или production (ассеты).
  late final ArticleRepository referenceRepository =
      widget.referenceRepository ?? ArticleRepository();

  /// БД пользовательских данных (в тестах — in-memory база каркаса).
  late final Database userDb = widget.database ?? AppDatabase.instance.db;

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
        // Справочник: контент грузится один раз при первом обращении.
        // Тесты дают здесь готовый repository (уже разобранный fromRaw).
        ChangeNotifierProvider<ReferenceProvider>(
          create: (_) {
            final provider = ReferenceProvider(repository: referenceRepository);
            unawaited(provider.load());
            return provider;
          },
        ),
        // P8: поиск (content-scoped — не зависит от сессии).
        ChangeNotifierProvider<SearchProvider>(
          create: (_) => SearchProvider(referenceRepository),
        ),
        // P9: избранное и история (user-scoped — слушают SessionProvider).
        // Начальная загрузка — при первом обращении любого экрана.
        ChangeNotifierProvider<FavoritesProvider>(
          create: (_) {
            final provider = FavoritesProvider(
              articles: referenceRepository,
              repository: FavoritesRepository(db: userDb),
              session: widget.session,
            );
            unawaited(provider.reload());
            return provider;
          },
        ),
        ChangeNotifierProvider<HistoryProvider>(
          create: (_) {
            final provider = HistoryProvider(
              articles: referenceRepository,
              repository: HistoryRepository(db: userDb),
              session: widget.session,
            );
            unawaited(provider.reload());
            return provider;
          },
        ),
        // P10: сниппеты песочницы (user-scoped — слушает SessionProvider) и
        // одноразовый черновик «Открыть в песочнице».
        ChangeNotifierProvider<SnippetProvider>(
          create: (_) {
            final provider = SnippetProvider(
              repository: SnippetRepository(db: userDb),
              session: widget.session,
            );
            unawaited(provider.reload());
            return provider;
          },
        ),
        ChangeNotifierProvider<PlaygroundDraftProvider>(
          create: (_) => PlaygroundDraftProvider(),
        ),
        // P11: репозиторий профиля для экрана редактирования (changePassword,
        // updateProfile — поверх той же БД пользовательских данных).
        Provider<ProfileRepository>(
          create: (_) => ProfileRepository(db: userDb),
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
