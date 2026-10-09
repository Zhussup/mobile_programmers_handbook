import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mob_kurs/app.dart';
import 'package:mob_kurs/core/db/app_database.dart';
import 'package:mob_kurs/features/auth/auth_repository.dart';
import 'package:mob_kurs/features/auth/session_provider.dart';

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
  Future<void> pumpApp(
    WidgetTester tester, {
    required String initialLocation,
  }) async {
    await tester.pumpWidget(
      MobKursApp(
        prefs: prefs,
        initialThemeMode: ThemeMode.light,
        session: session,
        initialLocation: initialLocation,
      ),
    );
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
