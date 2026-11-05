import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mob_kurs/app.dart';
import 'package:mob_kurs/core/db/app_database.dart';
import 'package:mob_kurs/features/auth/auth_repository.dart';
import 'package:mob_kurs/features/auth/session_provider.dart';
import 'package:mob_kurs/features/reference/article_repository.dart';

/// Тестовый каркас виджет-тестов: in-memory БД (sqflite_common_ffi) +
/// SharedPreferences-моки + SessionProvider + MobKursApp.
///
/// Подводный камень №3 из плана: в тестах фабрика sqflite подменяется на
/// FFI, БД in-memory (каждый тест — своя чистая база).
///
/// ВАЖНО: реальная IO (SQLite ffi) не завершается внутри fake-async
/// zone виджет-теста — все обращения к БД из тела теста оборачиваются в
/// [WidgetTester.runAsync] (см. registerUser/tapAndWaitReal).
class AppHarness {
  /// Готовая сессия.
  late SessionProvider session;

  /// Открытая in-memory БД.
  late Database db;

  /// Mock-prefs (один экземпляр на тест).
  late SharedPreferences prefs;

  /// Инициализация среды теста (вызывается в setUp — вне fake-async).
  Future<void> setUp() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    await databaseFactory.deleteDatabase(inMemoryDatabasePath);
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.dbVersion,
        onCreate: AppDatabase.onCreate,
      ),
    );

    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();

    session = SessionProvider(
      repository: AuthRepository(db: db, prefs: prefs),
    );
    await session.restoreSession();
  }

  /// Закрытие БД после теста.
  Future<void> tearDown() async {
    await db.close();
  }

  /// Запуск приложения на заданном маршруте.
  ///
  /// [referenceRepository] — репозиторий справочника для экранов P6/P8/P9:
  /// по умолчанию контент ЧИТАЕТСЯ С ДИСКА (dart:io, синхронно; вне
  /// fake-async это допустимо), поэтому виджет-тесты идут по реальному
  /// JSON; подменить контент можно, передав [ArticleRepository.fromRaw]
  /// явно (P8/P9 чаще используют inline-фикстуры — fixtures.dart).
  ///
  /// БД пользовательских данных (favorites/history, P9) — in-memory база
  /// [db], открытая в [setUp].
  Future<void> pumpApp(
    WidgetTester tester, {
    required String initialLocation,
    ArticleRepository? referenceRepository,
    ThemeMode themeMode = ThemeMode.light,
  }) async {
    await tester.pumpWidget(
      MobKursApp(
        prefs: prefs,
        initialThemeMode: themeMode,
        session: session,
        initialLocation: initialLocation,
        referenceRepository:
            referenceRepository ?? _defaultReferenceRepository(),
        database: db,
      ),
    );
  }

  /// Программный переход (push) по роутеру приложения.
  ///
  /// [initialLocation] учитывается только на первом pump: повторный
  /// pumpWidget переиспользует State и созданный ранее роутер, поэтому
  /// последующие переходы делаются напрямую через роутер. Именно push, а не
  /// go: go() меняет параметр текущей страницы — ArticleScreen
  /// переиспользует состояние (без initState) — постфрейм-запись истории не
  /// срабатывает; в приложении между статьями ходят только push (карточки,
  /// «Продолжить», поисковая выдача).
  void goRoute(WidgetTester tester, String location) {
    final context = tester.element(find.byType(Navigator).first);
    GoRouter.of(context).push(location);
  }

  /// Синхронное чтение файлов контента с диска + разбор (fromRaw).
  ///
  /// rootBundle-IO недоступен внутри fake-async-зоны виджет-теста, поэтому
  /// реальный контент подаётся так. Отсутствующие файлы (контент
  /// расширяется параллельно: cpp_stl/cpp_oop/dart_flutter ещё не на диске)
  /// пропускаются — репозиторий в production так же терпим к ним.
  ArticleRepository _defaultReferenceRepository() {
    return ArticleRepository.fromRaw([
      for (final name in ArticleRepository.contentFiles)
        if (File('assets/content/reference/$name').existsSync())
          File('assets/content/reference/$name').readAsStringSync(),
    ]);
  }

  /// Дать реальному циклу событий завершить БД-операции, запущенные из
  /// колбэков фрейма (запись истории в postFrame при открытии статьи, P9).
  ///
  /// После реального ожидания один pump — обработать завершившиеся
  /// микрозадачи и уведомления провайдеров.
  Future<void> settleRealIo(WidgetTester tester) async {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pump();
  }

  /// Нажать кнопку, чей обработчик ждёт реальной IO (SQLite ffi), и
  /// дождаться её завершения в РЕАЛЬНОМ цикле событий (runAsync).
  ///
  /// После реального ожидания один pump финализирует состояние
  /// (setState/SnackBar/навигация) — дальше тест пульсирует как обычно.
  Future<void> tapAndWaitReal(
    WidgetTester tester,
    Key buttonKey, {
    Duration realWait = const Duration(milliseconds: 300),
  }) async {
    await tester.runAsync(() async {
      await tester.tap(find.byKey(buttonKey));
      await Future<void>.delayed(realWait);
    });
    await tester.pump();
  }

  /// Зарегистрировать пользователя ЧЕРЕЗ СЕССИЮ (вход сразу после
  /// регистрации — как при живом сценарии «Регистрация → Главная»).
  ///
  /// [tester] обязателен: операция завершается реальной SQLite-IO, которая
  /// требует [WidgetTester.runAsync].
  Future<void> registerUser(
    WidgetTester tester, {
    String username = 'user1',
    String email = 'user1@example.com',
    String password = 'пароль123',
  }) async {
    await tester.runAsync(() async {
      await session.register(
        username: username,
        email: email,
        password: password,
      );
    });
    // Дать fake-async зоне обработать завершение реальной IO-операции.
    await tester.pump();
  }

  /// Регистрация в БД через репозиторий БЕЗ установления сессии —
  /// имитирует пользователя «прошлого запуска» при не сохранённом входе.
  /// Используется в тестах экрана авторизации: форма входа должна остаться
  /// доступной (session остаётся guest).
  Future<void> seedUser(
    WidgetTester tester, {
    String username = 'user1',
    String email = 'user1@example.com',
    String password = 'пароль123',
  }) async {
    final repository = AuthRepository(db: db, prefs: prefs);
    await tester.runAsync(() async {
      await repository.register(
        username: username,
        email: email,
        password: password,
      );
    });
  }
}
