import 'package:flutter_test/flutter_test.dart';
import 'package:mob_kurs/core/db/app_database.dart';
import 'package:mob_kurs/features/auth/auth_repository.dart';
import 'package:mob_kurs/features/auth/session_provider.dart';
import 'package:mob_kurs/features/auth/user_model.dart';
import 'package:mob_kurs/features/playground/snippet_model.dart';
import 'package:mob_kurs/features/playground/snippet_provider.dart';
import 'package:mob_kurs/features/playground/snippet_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Юнит-тесты провайдера сниппетов (P10): user-scoping (смена пользователя →
/// перезагрузка; чужое не видно) и CRUD с уведомлением слушателей.
///
/// in-memory SQLite через sqflite_common_ffi (подводный камень №3 из плана).
/// После каждой смены сессии слушатель провайдера запускает reload() без
/// ожидания — тесты дают ему завершиться (delay) или дожидаются явно.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late SessionProvider session;
  late SnippetProvider provider;

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
    final prefs = await SharedPreferences.getInstance();
    session = SessionProvider(
      repository: AuthRepository(db: db, prefs: prefs),
    );
    provider = SnippetProvider(
      repository: SnippetRepository(db: db),
      session: session,
    );
  });

  tearDown(() async {
    provider.dispose();
    await db.close();
  });

  Future<UserModel> register(String name) async {
    final user = await session.register(
      username: name,
      email: '$name@example.com',
      password: 'пароль123',
    );
    // Смена пользователя уведомила провайдер — дожидаемся его перезагрузки
    // явно (детерминизм: авто-reload не awaited).
    await provider.reload();
    return user;
  }

  group('user-scoping провайдера', () {
    test('гость: пустые entries, create — no-op (null)', () async {
      await provider.reload();
      expect(provider.currentUserId, isNull);
      expect(provider.entries, isEmpty);
      expect(provider.loading, isFalse);

      var notified = 0;
      provider.addListener(() => notified++);
      final created = await provider.create(
        title: 'Гостя',
        language: SnippetLanguage.cpp,
        code: 'int a;',
      );
      expect(created, isNull);
      expect(provider.entries, isEmpty);
      expect(notified, 0, reason: 'гостевая запись ничего не меняла');
    });

    test(
      'смена пользователя: провайдер сам перечитывает данные нового '
      '(слушатель сессии), а не держит чужое',
      () async {
        final first = await register('first');
        await provider.create(
          title: 'Только моё',
          language: SnippetLanguage.cpp,
          code: 'int a;',
        );
        expect(provider.entries.single.title, 'Только моё');

        // Выход: авто-reload по notify сессии → состояние очищается.
        await session.logout();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(provider.currentUserId, isNull);
        expect(provider.entries, isEmpty);

        // Второй пользователь: список его собственный (пусто у нового юзера).
        final second = await register('second');
        expect(second.id, isNot(first.id));
        expect(provider.currentUserId, second.id);
        expect(provider.entries, isEmpty);

        // Возврат первого: данные вернулись из БД под его user_id.
        await session.login(loginOrEmail: 'first', password: 'пароль123');
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(provider.currentUserId, first.id);
        expect(provider.entries.single.title, 'Только моё');
      },
    );

    test('loading-флаг: true до первой загрузки, false после неё', () async {
      expect(provider.loading, isTrue);
      await provider.reload();
      expect(provider.loading, isFalse);
    });
  });

  group('CRUD с уведомлением слушателей', () {
    test('create добавляет сниппет и уведомляет (список живой)', () async {
      await register('u1');
      var notified = 0;
      provider.addListener(() => notified++);

      final created = await provider.create(
        title: 'Новый',
        language: SnippetLanguage.dart,
        code: "void main() {}",
      );
      expect(created, isNotNull);
      expect(provider.entries.single.title, 'Новый');
      expect(provider.snippetById(created!.id)?.code, 'void main() {}');
      expect(notified, 1, reason: 'одна вставка — одно уведомление');
    });

    test('update: изменённые поля в списке, уведомление, наверх списка',
        () async {
      await register('u1');
      final first =
          (await provider.create(
                title: 'Старый',
                language: SnippetLanguage.cpp,
                code: 'int a;',
              ))!;
      await Future<void>.delayed(const Duration(milliseconds: 15));
      // Второй сниппет свежее первого (первым в списке).
      final second =
          (await provider.create(
                title: 'Второй',
                language: SnippetLanguage.cpp,
                code: 'int b;',
              ))!;
      expect(provider.entries.map((s) => s.id).toList(), [second.id, first.id]);

      var notified = 0;
      provider.addListener(() => notified++);
      final updated = await provider.update(
        first!,
        title: 'Переписанный',
        language: SnippetLanguage.dart,
        code: 'int c;',
      );
      expect(updated, isNotNull);
      expect(provider.entries.first.id, updated!.id);
      expect(provider.snippetById(first.id)!.title, 'Переписанный');
      expect(provider.snippetById(first.id)!.language, SnippetLanguage.dart);
      expect(notified, 1);
    });

    test('транзакция update — null для чужого/несуществующего id', () async {
      final u1 = await register('first');
      final first =
          (await provider.create(
                title: 'Свой',
                language: SnippetLanguage.cpp,
                code: 'int a;',
              ))!;

      // Второй пользователь пытается обновить чужой сниппет по id.
      await session.logout();
      await register('second');
      final stolen = await provider.update(
        Snippet(
          id: first.id,
          userId: u1.id,
          title: 'x',
          language: SnippetLanguage.cpp,
          code: 'x',
          expectedOutput: null,
          createdAt: first.createdAt,
          updatedAt: first.updatedAt,
        ),
        title: 'Взломан',
        language: SnippetLanguage.dart,
        code: 'hacked',
      );
      expect(stolen, isNull);

      // Сниппет первого не изменился (после повторного входа).
      await session.logout();
      await session.login(loginOrEmail: 'first', password: 'пароль123');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(provider.entries.single.title, 'Свой');
    });

    test('delete: true у владельца, false у чужого и повторно', () async {
      final u1 = await register('first');
      final created =
          await provider.create(
                title: 'Свой',
                language: SnippetLanguage.cpp,
                code: 'a',
              ) ??
              fail('create вернул null');

      var notified = 0;
      provider.addListener(() => notified++);

      // Чужой id не удаляется.
      expect(await provider.delete(created.id + 999), isFalse);
      expect(notified, 0);
      expect(provider.entries.single.id, created.id);

      // Владелец удаляет — запись уходит, уведомление есть.
      expect(await provider.delete(created.id), isTrue);
      expect(provider.entries, isEmpty);
      expect(notified, 1);

      // Повторное удаление — no-op.
      expect(await provider.delete(created.id), isFalse);
      expect(notified, 1);

      // В БД записи тоже нет (именно удаление, а не скрытие).
      expect(await snippetCountForUser(db, u1.id), 0);
    });
  });
}