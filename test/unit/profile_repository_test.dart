import 'package:flutter_test/flutter_test.dart';
import 'package:mob_kurs/core/db/app_database.dart';
import 'package:mob_kurs/features/auth/auth_repository.dart';
import 'package:mob_kurs/features/auth/user_model.dart';
import 'package:mob_kurs/features/profile/profile_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Юнит-тесты репозитория профиля 2.0 (P11): изменение username/email с
/// проверкой уникальности (кириллица — ручное сравнение в Дарте), смена
/// пароля (старый проверяется, новый — с новой солью) и цвет аватара.
///
/// in-memory SQLite через sqflite_common_ffi (подводный камень №3 из плана).
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late SharedPreferences prefs;
  late AuthRepository auth;
  late ProfileRepository repository;

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
    auth = AuthRepository(db: db, prefs: prefs);
    repository = ProfileRepository(db: db);
  });

  tearDown(() async {
    await db.close();
  });

  group('updateProfile: username/email', () {
    test('изменение имени и email сохраняется, модель обновлена', () async {
      final user = await auth.register(
        username: 'Иван',
        email: 'ivan@example.com',
        password: 'пароль123',
      );

      final updated = await repository.updateProfile(
        user.id,
        username: 'Пётр',
        email: 'petr@example.com',
      );

      expect(updated.username, 'Пётр');
      expect(updated.email, 'petr@example.com');
      expect(updated.id, user.id);
      // created_at и цвет аватара не трогаются.
      expect(updated.createdAt, user.createdAt);
      expect(updated.avatarColor, user.avatarColor);

      // Прочитано из БД свежим запросом (не только возвращённая модель).
      final read = await repository.getUserRow(user.id);
      expect(read!.username, 'Пётр');
    });

    test(
      'конфликт имени (латиница, без учёта регистра) → ошибка поля username',
      () async {
        final first = await auth.register(
          username: 'first',
          email: 'first@example.com',
          password: 'пароль123',
        );
        await auth.register(
          username: 'second',
          email: 'second@example.com',
          password: 'пароль123',
        );

        expect(
          () => repository.updateProfile(
            first.id,
            username: 'SECOND',
            email: 'still-first@example.com',
          ),
          throwsA(
            isA<ProfileException>()
                .having((e) => e.field, 'field', ProfileField.username)
                .having(
                  (e) => e.message,
                  'message',
                  'Имя пользователя уже занято',
                ),
          ),
        );
      },
    );

    test(
      'конфликт имени кириллицей (NOCASE не работает — ловим в Дарте)',
      () async {
        await auth.register(
          username: 'иван',
          email: 'ivan1@example.com',
          password: 'пароль123',
        );
        final other = await auth.register(
          username: 'Пётр',
          email: 'petr1@example.com',
          password: 'пароль123',
        );

        expect(
          () => repository.updateProfile(other.id, username: 'Иван'),
          throwsA(
            isA<ProfileException>().having(
              (e) => e.field,
              'field',
              ProfileField.username,
            ),
          ),
        );
      },
    );

    test('конфликт email уже зарегистрирован → ошибка поля email', () async {
      final first = await auth.register(
        username: 'first',
        email: 'shared@example.com',
        password: 'пароль123',
      );
      final second = await auth.register(
        username: 'second',
        email: 'second@example.com',
        password: 'пароль123',
      );

      expect(
        () => repository.updateProfile(second.id, email: 'SHARED@example.com'),
        throwsA(
          isA<ProfileException>().having(
            (e) => e.field,
            'field',
            ProfileField.email,
          ),
        ),
      );
      // first цел после неудачной попытки второго.
      expect(
        (await repository.getUserRow(first.id))!.email,
        'shared@example.com',
      );
    });

    test(
      'свой текущий username/email не конфликтуют (без изменений)',
      () async {
        final user = await auth.register(
          username: 'myself',
          email: 'myself@example.com',
          password: 'пароль123',
        );

        final same = await repository.updateProfile(
          user.id,
          username: 'MYSELF',
          email: 'myself@example.com',
        );
        expect(same.username, 'MYSELF');
      },
    );

    test('несуществующий пользователь → ProfileException без поля', () async {
      await auth.register(
        username: 'u1',
        email: 'u1@example.com',
        password: 'пароль123',
      );
      // Id 9999 не существует (после AUTOINCREMENT реальный id маленький).
      expect(
        () => repository.updateProfile(9999, username: 'ghost'),
        throwsA(isA<ProfileException>()),
      );
    });
  });

  group('changePassword', () {
    Future<UserModel> createUser() => auth.register(
      username: 'user1',
      email: 'user1@example.com',
      password: 'пароль123',
    );

    test('неверный старый пароль → ошибка поля oldPassword', () async {
      final user = await createUser();
      expect(
        () => repository.changePassword(
          userId: user.id,
          oldPassword: 'НЕВЕРНЫЙ',
          newPassword: 'новыйПароль456',
        ),
        throwsA(
          isA<ProfileException>()
              .having((e) => e.field, 'field', ProfileField.oldPassword)
              .having((e) => e.message, 'message', 'Неверный старый пароль'),
        ),
      );
      // Пароль не изменился: старый всё ещё подходит.
      final loggedIn = await auth.login(
        loginOrEmail: 'user1',
        password: 'пароль123',
      );
      expect(loggedIn.id, user.id);
    });

    test(
      'корректная смена: новый пароль входит, старый больше не работает',
      () async {
        final user = await createUser();

        await repository.changePassword(
          userId: user.id,
          oldPassword: 'пароль123',
          newPassword: 'новыйПароль456',
        );

        // Старый больше не работает.
        expect(
          () => auth.login(loginOrEmail: 'user1', password: 'пароль123'),
          throwsA(isA<AuthException>()),
        );
        // Новый работает.
        final loggedIn = await auth.login(
          loginOrEmail: 'user1',
          password: 'новыйПароль456',
        );
        expect(loggedIn.id, user.id);
      },
    );

    test('смена пароля даёт новую соль (не переиспользуя старую)', () async {
      final user = await createUser();
      final before = await db.query(
        'users',
        where: 'id = ?',
        whereArgs: [user.id],
      );
      final oldSalt = before.single['salt']! as String;

      await repository.changePassword(
        userId: user.id,
        oldPassword: 'пароль123',
        newPassword: 'новыйПароль456',
      );

      final after = await db.query(
        'users',
        where: 'id = ?',
        whereArgs: [user.id],
      );
      expect(after.single['salt'], isNot(oldSalt));
      expect(
        after.single['password_hash'],
        isNot(before.single['password_hash']),
      );
    });
  });

  group('updateAvatarColor', () {
    test('цвет обновляется и в БД, и в модели', () async {
      final user = await auth.register(
        username: 'u1',
        email: 'u1@example.com',
        password: 'пароль123',
      );

      final updated = await repository.updateAvatarColor(user.id, '#8C6FF0');
      expect(updated.avatarColor, '#8C6FF0');

      final row = await db.query(
        'users',
        where: 'id = ?',
        whereArgs: [user.id],
      );
      expect(row.single['avatar_color'], '#8C6FF0');
    });

    test('несуществующий пользователь → ProfileException', () async {
      await auth.register(
        username: 'u1',
        email: 'u1@example.com',
        password: 'пароль123',
      );
      expect(
        () => repository.updateAvatarColor(9999, '#8C6FF0'),
        throwsA(isA<ProfileException>()),
      );
    });
  });
}
