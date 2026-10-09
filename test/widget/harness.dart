import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' hide DatabaseException;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mob_kurs/app.dart';
import 'package:mob_kurs/core/db/app_database.dart';
import 'package:mob_kurs/features/auth/auth_repository.dart';
import 'package:mob_kurs/features/auth/session_provider.dart';

/// Тестовый каркас виджет-тестов: in-memory БД (sqflite_common_ffi) +
/// mock-SharedPreferences +_SessionProvider + MobKursApp.
///
/// Подводный камень №3 из плана: в тестах фабрика sqflite подменяется на
/// FFI, БД in-memory (каждый тест — своя чистая база).
class AppHarness {
  /// Готовая сессия.
  late SessionProvider session;

  /// Открытая in-memory БД.
  late Database db;

  /// Mock-prefs (один экземпляр на тест).
  late SharedPreferences prefs;

  /// Инициализация среды теста (вызывается в setUp).
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

  /// Зарегистрировать пользователя (как при прошлых запусках).
  Future<void> registerUser({
    String username = 'user1',
    String email = 'user1@example.com',
    String password = 'пароль123',
  }) {
    return session.register(
      username: username,
      email: email,
      password: password,
    );
  }
}
