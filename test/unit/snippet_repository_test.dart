import 'package:flutter_test/flutter_test.dart';
import 'package:mob_kurs/core/constants/app_constants.dart';
import 'package:mob_kurs/core/db/app_database.dart';
import 'package:mob_kurs/features/playground/snippet_model.dart';
import 'package:mob_kurs/features/playground/snippet_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Юнит-тесты репозитория сниппетов (P10, план → «Тестирование → Юнит»):
/// in-memory SQLite через sqflite_common_ffi (подводный камень №3 из плана).
///
/// Ключевые кейсы: полный CRUD-цикл; изоляция по user_id (чужой сниппет
/// нельзя прочитать/изменить/удалить, даже зная id); update поднимает
/// updated_at (список сортируется «свежие раньше»).
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late SnippetRepository repository;

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
    repository = SnippetRepository(db: db);
  });

  tearDown(() async {
    await db.close();
  });

  group('create + getById: все поля сохраняются', () {
    test('create возвращает модель с id из БД, getById её же', () async {
      final created = await repository.create(
        userId: 1,
        title: 'Hello, World',
        language: SnippetLanguage.cpp,
        code: '#include <iostream>\nint main() { return 0; }',
        expectedOutput: '',
      );

      expect(created.id, greaterThan(0));
      expect(created.userId, 1);
      expect(created.title, 'Hello, World');
      expect(created.language, SnippetLanguage.cpp);
      expect(created.code, '#include <iostream>\nint main() { return 0; }');
      // Пустой текст «ожидаемого вывода» хранится как в переданном виде
      // (пустое поле не обязательно): здесь передали ''.
      expect(created.expectedOutput, '');

      final read = await repository.getById(1, created.id);
      expect(read, isNotNull);
      expect(read!.title, created.title);
      expect(read.createdAt, created.createdAt);
      expect(read.updatedAt, created.updatedAt);
    });

    test(
      'Dart-сниппет: язык сохраняется по raw-имени варианта enum',
      () async {
        final created = await repository.create(
          userId: 1,
          title: 'Dart example',
          language: SnippetLanguage.dart,
          code: "void main() { print('hi'); }",
          expectedOutput: 'hi',
        );

        final row = await db.query(
          AppConstants.tableUserSnippets,
          where: 'id = ?',
          whereArgs: [created.id],
        );
        expect(row.single['language'], 'dart');

        final read = await repository.getById(1, created.id);
        expect(read!.language, SnippetLanguage.dart);
        expect(read.expectedOutput, 'hi');
      },
    );

    test('title триммится при сохранении', () async {
      final created = await repository.create(
        userId: 1,
        title: '  С пробелами  ',
        language: SnippetLanguage.cpp,
        code: 'int x;',
      );
      expect(created.title, 'С пробелами');
      expect((await repository.getById(1, created.id))!.title, 'С пробелами');
    });
  });

  group('update: изменение полей и updated_at', () {
    test('CRUD-цикл: создать → изменить → прочитать новое → удалить', () async {
      final created = await repository.create(
        userId: 1,
        title: 'Первый',
        language: SnippetLanguage.cpp,
        code: 'int a;',
      );
      final oldUpdatedAt = created.updatedAt;

      // Заметная пауза: ISO-время должно вырасти, чтобы список сортировался.
      await Future<void>.delayed(const Duration(milliseconds: 15));
      final updated = await repository.update(
        userId: 1,
        id: created.id,
        title: 'Обновлённый',
        language: SnippetLanguage.dart,
        code: 'int b;',
        expectedOutput: 'ok',
      );

      expect(updated, isNotNull);
      expect(updated!.title, 'Обновлённый');
      expect(updated.language, SnippetLanguage.dart);
      expect(updated.code, 'int b;');
      expect(updated.expectedOutput, 'ok');
      expect(updated.createdAt, created.createdAt, reason: 'created_at сохранён');
      expect(
        updated.updatedAt.isAfter(oldUpdatedAt),
        isTrue,
        reason: 'update поднимает updated_at',
      );

      // Прочитали изменённое из БД.
      final read = await repository.getById(1, created.id);
      expect(read!.title, 'Обновлённый');

      // Удаление.
      expect(await repository.delete(1, created.id), isTrue);
      expect(await repository.getById(1, created.id), isNull);
    });

    test('несуществующий id → null (ничего не изменилось)', () async {
      final created = await repository.create(
        userId: 1,
        title: 'Один',
        language: SnippetLanguage.cpp,
        code: 'int a;',
      );
      final unchanged = await repository.update(
        userId: 1,
        id: created.id + 999,
        title: 'Никогда',
        language: SnippetLanguage.cpp,
        code: '',
      );
      expect(unchanged, isNull);
      expect((await repository.listForUser(1)).single.title, 'Один');
    });
  });

  group('изоляция user_id (мультиюзер)', () {
    test(
      'чужой сниппет нельзя прочитать, изменить или удалить, даже зная id',
      () async {
        final first = await repository.create(
          userId: 1,
          title: 'Свой',
          language: SnippetLanguage.cpp,
          code: 'int a;',
        );

        // Второй пользователь: ничего не видит.
        expect(await repository.getById(2, first.id), isNull);
        expect(await repository.listForUser(2), isEmpty);

        // …и не может изменить.
        final foreignUpdate = await repository.update(
          userId: 2,
          id: first.id,
          title: 'Взломан',
          language: SnippetLanguage.dart,
          code: 'hacked',
        );
        expect(foreignUpdate, isNull);
        final untouched = await repository.getById(1, first.id);
        expect(untouched!.title, 'Свой');

        // …и не может удалить.
        expect(await repository.delete(2, first.id), isFalse);
        expect(await repository.getById(1, first.id), isNotNull);
      },
    );

    test('списки пользователей независимы', () async {
      await repository.create(
        userId: 1,
        title: 'У первого',
        language: SnippetLanguage.cpp,
        code: 'a',
      );
      await repository.create(
        userId: 2,
        title: 'У второго',
        language: SnippetLanguage.dart,
        code: 'b',
      );
      await repository.create(
        userId: 2,
        title: 'Второй-2',
        language: SnippetLanguage.cpp,
        code: 'c',
      );

      final user1 = await repository.listForUser(1);
      final user2 = await repository.listForUser(2);
      expect(user1.single.title, 'У первого');
      expect(user2.map((s) => s.title), ['Второй-2', 'У второго']);
      expect(await snippetCountForUser(db, 1), 1);
      expect(await snippetCountForUser(db, 2), 2);
    });
  });

  group('listForUser: сортировка и удаление', () {
    test('свежие изменения раньше (updated_at DESC)', () async {
      final first = await repository.create(
        userId: 1,
        title: 'A',
        language: SnippetLanguage.cpp,
        code: 'a',
      );
      await Future<void>.delayed(const Duration(milliseconds: 15));
      final second = await repository.create(
        userId: 1,
        title: 'B',
        language: SnippetLanguage.cpp,
        code: 'b',
      );

      // Свежий (созданный позже) — первым.
      var list = await repository.listForUser(1);
      expect(list.map((s) => s.title), ['B', 'A']);

      // Изменили старый A — он поднимается наверх.
      await Future<void>.delayed(const Duration(milliseconds: 15));
      await repository.update(
        userId: 1,
        id: first.id,
        title: 'A',
        language: SnippetLanguage.cpp,
        code: 'a2',
      );
      list = await repository.listForUser(1);
      expect(list.map((s) => s.title).toList(), ['A', 'B']);

      // Удалили второй — остался только A.
      expect(await repository.delete(1, second.id), isTrue);
      list = await repository.listForUser(1);
      expect(list.single.title, 'A');
    });

    test('preview(count) — только первые строки кода', () {
      final snippet = Snippet(
        id: 1,
        userId: 1,
        title: 't',
        language: SnippetLanguage.cpp,
        code: '1\n2\n3\n4\n5\n6\n7',
        expectedOutput: null,
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );
      expect(snippet.preview(), ['1', '2', '3', '4', '5']);
      expect(snippet.preview(count: 3), ['1', '2', '3']);
    });
  });
}