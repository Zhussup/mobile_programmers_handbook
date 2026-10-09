import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' hide DatabaseException;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mob_kurs/core/constants/app_constants.dart';
import 'package:mob_kurs/core/db/app_database.dart';
import 'package:mob_kurs/features/auth/auth_repository.dart';
import 'package:mob_kurs/features/auth/session_provider.dart';

/// Юнит-тесты сессии: persist `session_user_id` и восстановление при
/// «перезапуске» (новый провайдер + те же prefs).
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late SharedPreferences prefs;
  late AuthRepository repository;

  setUp(() async {
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
    repository = AuthRepository(db: db, prefs: prefs);
  });

  test('до restoreSession состояние unknown (сессия ещё не восстановлена)',
      () {
    final session = SessionProvider(repository: repository);
    expect(session.state.status, AuthStatus.unknown);
  });

  test('restoreSession без сохранённого id → guest', () async {
    final session = SessionProvider(repository: repository);
    await session.restoreSession();
    expect(session.initialized, isTrue);
    expect(session.state.status, AuthStatus.guest);
    expect(session.currentUser, isNull);
  });

  test('register сохраняет сессию и пользователя', () async {
    final session = SessionProvider(repository: repository);
    await session.restoreSession();
    final user = await session.register(
      username: 'user1',
      email: 'user1@example.com',
      password: 'пароль123',
    );

    expect(session.currentUser?.id, user.id);
    expect(session.state.isAuthorized, isTrue);
    expect(
      prefs.getInt(AppConstants.prefSessionUserId),
      user.id,
    );
  });

  test('restoreSession «после перезапуска» восстанавливает пользователя',
      () async {
    // «Прошлый запуск»: регистрация + persist.
    final previous = SessionProvider(repository: repository);
    await previous.restoreSession();
    final user = await previous.register(
      username: 'user1',
      email: 'user1@example.com',
      password: 'пароль123',
    );

    // «Новый запуск» (prefs те же, provider новый) — восстановление.
    final restored = SessionProvider(repository: repository);
    await restored.restoreSession();
    expect(restored.state.isAuthorized, isTrue);
    expect(restored.currentUser?.id, user.id);
    expect(restored.currentUser?.username, 'user1');
  });

  test('restoreSession с «висящим» id (запись удалена) → guest', () async {
    // Регистрируем пользователя, удаляем его запись из БД напрямую.
    final previous = SessionProvider(repository: repository);
    await previous.restoreSession();
    final user = await previous.register(
      username: 'user1',
      email: 'user1@example.com',
      password: 'пароль123',
    );
    await db.delete('users', where: 'id = ?', whereArgs: [user.id]);

    // Восстановление: id в prefs есть, записи в БД нет → гость, ключ сброшен.
    final restored = SessionProvider(repository: repository);
    await restored.restoreSession();
    expect(restored.state.isAuthorized, isFalse);
    expect(prefs.getInt(AppConstants.prefSessionUserId), isNull);
  });

  test('logout сбрасывает currentUser, БД и вход остаются рабочими', () async {
    final session = SessionProvider(repository: repository);
    await session.restoreSession();
    final user = await session.register(
      username: 'user1',
      email: 'user1@example.com',
      password: 'пароль123',
    );
    await session.logout();

    expect(session.currentUser, isNull);
    expect(session.state.isAuthorized, isFalse);
    expect(prefs.getInt(AppConstants.prefSessionUserId), isNull);

    // Выход не удалил пользователя из БД.
    final loaded = await repository.getUserById(user.id);
    expect(loaded, isNotNull);
  });
}
