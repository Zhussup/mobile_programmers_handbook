import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' show Database;

import 'core/config/app_config.dart';
import 'core/constants/app_constants.dart';
import 'core/db/app_database.dart';
import 'core/network/api_client.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/session_provider.dart';
import 'features/playground/playground_draft_provider.dart';
import 'features/playground/remote_snippet_repository.dart';
import 'features/playground/snippet_data_source.dart';
import 'features/playground/snippet_provider.dart';
import 'features/playground/snippet_repository.dart';
import 'features/profile/profile_data_source.dart';
import 'features/profile/profile_repository.dart';
import 'features/profile/remote_profile_repository.dart';
import 'features/profile/theme_provider.dart';
import 'features/reference/article_repository.dart';
import 'features/reference/favorites_data_source.dart';
import 'features/reference/favorites_provider.dart';
import 'features/reference/favorites_repository.dart';
import 'features/reference/history_data_source.dart';
import 'features/reference/history_provider.dart';
import 'features/reference/history_repository.dart';
import 'features/reference/reference_cache.dart';
import 'features/reference/reference_content_repository.dart';
import 'features/reference/reference_provider.dart';
import 'features/reference/remote_favorites_repository.dart';
import 'features/reference/remote_history_repository.dart';
import 'features/reference/remote_reference_repository.dart';
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
    this.apiClient,
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
  final ReferenceContentRepository? referenceRepository;

  /// БД пользовательских данных (favorites/history — P9).
  ///
  /// Production: null → AppDatabase.instance (открыта в main() до runApp,
  /// подводный камень №3). В тестах каркас передаёт свою in-memory базу.
  final Database? database;

  /// API-клиент backend.
  ///
  /// null → локальный режим (JSON-ассеты + sqflite) — так работают тесты
  /// и офлайн-демонстрация. main() передаёт клиент при `AppConfig.useApi`.
  final ApiClient? apiClient;

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

  /// Использовать удалённые репозитории (API) вместо локальных.
  ///
  /// Тесты передают готовый [referenceRepository] и не передают [apiClient]
  /// — для них всегда локальный режим, как до КР_2_2.
  late final bool useApi = AppConfig.useApi && widget.apiClient != null;

  /// БД пользовательских данных (в тестах — in-memory база каркаса).
  late final Database userDb = widget.database ?? AppDatabase.instance.db;

  /// Источник контента: тестовый (fromRaw), локальные ассеты или API.
  late final ReferenceContentRepository referenceRepository =
      widget.referenceRepository ??
      (useApi
          ? RemoteReferenceRepository(
              apiClient: widget.apiClient!,
              cache: ReferenceCache(db: userDb),
            )
          : ArticleRepository());

  /// Источник избранного: API (с кэшем sqflite) или локальная таблица.
  late final FavoritesDataSource favoritesRepository = useApi
      ? RemoteFavoritesRepository(
          apiClient: widget.apiClient!,
          cache: FavoritesRepository(db: userDb),
        )
      : FavoritesRepository(db: userDb);

  /// Источник истории: API (с кэшем sqflite) или локальная таблица.
  late final HistoryDataSource historyRepository = useApi
      ? RemoteHistoryRepository(
          apiClient: widget.apiClient!,
          cache: HistoryRepository(db: userDb),
        )
      : HistoryRepository(db: userDb);

  /// Источник сниппетов: API (с кэшем sqflite) или локальная таблица.
  late final SnippetDataSource snippetRepository = useApi
      ? RemoteSnippetRepository(
          apiClient: widget.apiClient!,
          cache: SnippetRepository(db: userDb),
        )
      : SnippetRepository(db: userDb);

  /// Репозиторий профиля: API или локальная БД.
  late final ProfileDataSource profileRepository = useApi
      ? RemoteProfileRepository(apiClient: widget.apiClient!)
      : ProfileRepository(db: userDb);

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
              repository: favoritesRepository,
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
              repository: historyRepository,
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
              repository: snippetRepository,
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
        // updateProfile — API или локальная БД пользовательских данных).
        Provider<ProfileDataSource>(create: (_) => profileRepository),
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
