import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' hide DatabaseException;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mob_kurs/core/db/app_database.dart';
import 'package:mob_kurs/features/auth/auth_repository.dart';

/// Юнит-тесты репозитория пользователей: in-memory БД через
/// sqflite_common_ffi (подводный камень №3 из плана).
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late SharedPreferences prefs;
  late AuthRepository repository;

  setUp(() async {
    // Свежая изолированная in-memory БД на каждый тест.
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

  Future<int> usersCount() async {
    final result = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM users'),
    );
    return result ?? 0;
  }

  group('register + login (связка)', () {
    test('регистрация создаёт пользователя, повторный вход успешен', () async {
      final user = await repository.register(
        username: 'Иван',
        email: 'ivan@example.com',
        password: 'пароль123',
      );
      expect(user.username, 'Иван');
      expect(user.email, 'ivan@example.com');
      expect(user.id, greaterThan(0));

      // Повторная авторизация — теми же данными.
      final loggedIn = await repository.login(
        loginOrEmail: 'Иван',
        password: 'пароль123',
      );
      expect(loggedIn.id, user.id);

      // Логин по email тоже работает.
      final byEmail = await repository.login(
        loginOrEmail: 'ivan@example.com',
        password: 'пароль123',
      );
      expect(byEmail.id, user.id);
    });

    test(
      'пароль хранится только как хэш + соль (не в открытом виде)',
      () async {
        await repository.register(
          username: 'user1',
          email: 'user1@example.com',
          password: 'секретныйПароль',
        );
        final rows = await db.query('users');
        final row = rows.single;
        expect(
          row['password_hash'] as String,
          isNot(contains('секретныйПароль')),
        );
        expect(row['password_hash'] as String, hasLength(64));
        expect((row['salt'] as String).length, 32);
      },
    );

    test(
      'соль: у двух пользователей одинаковый пароль — разные хэши',
      () async {
        await repository.register(
          username: 'user1',
          email: 'user1@example.com',
          password: 'общийПароль',
        );
        await repository.register(
          username: 'user2',
          email: 'user2@example.com',
          password: 'общийПароль',
        );
        final rows = await db.query('users');
        expect(
          (rows[0]['password_hash'] as String),
          isNot(rows[1]['password_hash']),
        );
      },
    );
  });

  group('login: ошибки', () {
    test(
      'неверный пароль → AuthException «Неверный логин или пароль»',
      () async {
        await repository.register(
          username: 'user1',
          email: 'user1@example.com',
          password: 'пароль123',
        );
        expect(
          () =>
              repository.login(loginOrEmail: 'user1', password: 'другойпароль'),
          throwsA(
            isA<AuthException>().having(
              (e) => e.message,
              'message',
              'Неверный логин или пароль',
            ),
          ),
        );
      },
    );

    test('несуществующий пользователь → AuthException', () async {
      expect(
        () => repository.login(loginOrEmail: 'нетакого', password: 'пароль123'),
        throwsA(isA<AuthException>()),
      );
    });
  });

  group('register: дубликаты (без учёта регистра)', () {
    test(
      'дубликат username в другом регистре → ошибка поля username',
      () async {
        await repository.register(
          username: 'Иван',
          email: 'ivan@example.com',
          password: 'пароль123',
        );
        expect(
          () => repository.register(
            username: 'иван',
            email: 'другой@example.com',
            password: 'пароль456',
          ),
          throwsA(
            isA<AuthException>()
                .having((e) => e.field, 'field', AuthField.username)
                .having(
                  (e) => e.message,
                  'message',
                  'Имя пользователя уже занято',
                ),
          ),
        );
      },
    );

    test('дубликат email в другом регистре → ошибка поля email', () async {
      await repository.register(
        username: 'user1',
        email: 'ivan@example.com',
        password: 'пароль123',
      );
      expect(
        () => repository.register(
          username: 'user2',
          email: 'IVAN@EXAMPLE.COM',
          password: 'пароль456',
        ),
        throwsA(
          isA<AuthException>()
              .having((e) => e.field, 'field', AuthField.email)
              .having((e) => e.message, 'message', 'Email уже зарегистрирован'),
        ),
      );
    });

    test(
      'UNIQUE-ограничение схемы как страховка (прямой INSERT дубля)',
      () async {
        await repository.register(
          username: 'user1',
          email: 'user1@example.com',
          password: 'пароль123',
        );
        // Вставка мимо _assertUnique: проверяет работу самой схемы (NOCASE).
        expect(
          () => db.insert('users', {
            'username': 'USER1',
            'email': 'user2@example.com',
            'password_hash': 'hash',
            'salt': 'salt',
            'avatar_color': '#2AA79B',
            'created_at': '2026-01-01T00:00:00.000',
          }),
          throwsA(isA<DatabaseException>()),
        );
      },
    );
  });

  group('logout + сессия', () {
    test('logout сохраняет данные в БД и сбрасывает сессию', () async {
      final user = await repository.register(
        username: 'user1',
        email: 'user1@example.com',
        password: 'пароль123',
      );
      await repository.saveSession(user.id);
      expect(repository.sessionId, user.id);

      // До выхода.
      await expectLater(await usersCount(), 1);

      // Выход.
      await repository.logout();

      // Сессия сброшена, данные в БД НЕ удалены.
      expect(repository.sessionId, isNull);
      await expectLater(await usersCount(), 1);

      // Повторный вход тем же пользователем работает.
      final loggedIn = await repository.login(
        loginOrEmail: 'user1',
        password: 'пароль123',
      );
      expect(loggedIn.id, user.id);
    });

    test('getUserById возвращает сохранённого пользователя', () async {
      final user = await repository.register(
        username: 'user1',
        email: 'user1@example.com',
        password: 'пароль123',
      );
      final loaded = await repository.getUserById(user.id);
      expect(loaded, isNotNull);
      expect(loaded!.username, 'user1');
      // Несуществующий id → null.
      expect(await repository.getUserById(user.id + 100), isNull);
    });
  });

  group('login: регистрозависимость вхождения', () {
    test('вход по имени в другом регистре работает', () async {
      final registered = await repository.register(
        username: 'IvanPetrov',
        email: 'ivan@example.com',
        password: 'пароль123',
      );
      final loggedIn = await repository.login(
        loginOrEmail: 'ivanpetrov',
        password: 'пароль123',
      );
      expect(loggedIn.id, registered.id);
    });
  });
}
