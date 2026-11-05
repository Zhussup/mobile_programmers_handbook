import 'package:flutter_test/flutter_test.dart';
import 'package:mob_kurs/core/db/app_database.dart';
import 'package:mob_kurs/features/auth/auth_repository.dart';
import 'package:mob_kurs/features/auth/session_provider.dart';
import 'package:mob_kurs/features/auth/user_model.dart';
import 'package:mob_kurs/features/reference/article_repository.dart';
import 'package:mob_kurs/features/reference/favorites_provider.dart';
import 'package:mob_kurs/features/reference/favorites_repository.dart';
import 'package:mob_kurs/features/reference/history_provider.dart';
import 'package:mob_kurs/features/reference/history_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../widget/fixtures.dart';

/// Юнит-тесты избранного и истории (P9, план → «Тестирование → Юнит:
/// favorites_history»): in-memory SQLite через sqflite_common_ffi
/// (подводный камень №3 из плана).
///
/// Ключевые кейсы: toggle идемпотентен; топ-20 истории (25 → 20 свежих);
/// изоляция по user_id (данные второго пользователя не видны); очистка;
/// user-scoping провайдеров при смене пользователя.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;

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
  });

  tearDown(() async {
    await db.close();
  });

  group('FavoritesRepository: toggle идемпотентен', () {
    test('toggle → добавлено; повторный toggle → удалено (исходное)', () async {
      final repository = FavoritesRepository(db: db);

      expect(await repository.isFavorite(1, 'cpp_syn_hello_world'), isFalse);
      expect(
        await repository.toggle(1, 'cpp_syn_hello_world'),
        isTrue,
        reason: 'первый toggle — добавлено',
      );
      expect(await repository.isFavorite(1, 'cpp_syn_hello_world'), isTrue);
      expect(
        await repository.toggle(1, 'cpp_syn_hello_world'),
        isFalse,
        reason: 'второй toggle — удалено (toggle идемпотентен)',
      );
      expect(await repository.isFavorite(1, 'cpp_syn_hello_world'), isFalse);
    });

    test('двойной toggle не оставляет дубликатов строк таблицы', () async {
      final repository = FavoritesRepository(db: db);

      await repository.toggle(1, 'cpp_syn_hello_world');
      await repository.toggle(1, 'cpp_syn_hello_world');
      await repository.toggle(1, 'cpp_syn_hello_world'); // снова добавили

      final rows = await db.query(
        AppDbTables.favorites,
        where: 'user_id = ? AND article_id = ?',
        whereArgs: [1, 'cpp_syn_hello_world'],
      );
      expect(rows, hasLength(1));
    });

    test(
      'изоляция user_id: избранное пользователя 1 не видно второму',
      () async {
        final repository = FavoritesRepository(db: db);

        await repository.toggle(1, 'cpp_syn_variables');
        await repository.toggle(1, 'cpp_syn_operators');

        expect(await repository.isFavorite(2, 'cpp_syn_variables'), isFalse);
        expect(await repository.listForUser(2), isEmpty);

        await repository.toggle(2, 'cpp_ds_vector');
        // Списки пользователей независимы.
        expect((await repository.listForUser(1)).length, 2);
        expect((await repository.listForUser(2)).length, 1);

        // Удаление у первого не трогает ту же статью у второго.
        await repository.toggle(1, 'cpp_ds_vector'); // добавили
        expect(await repository.isFavorite(2, 'cpp_ds_vector'), isTrue);
        await repository.toggle(1, 'cpp_ds_vector'); // удалили
        expect(await repository.isFavorite(2, 'cpp_ds_vector'), isTrue);
      },
    );

    test('listForUser: свежие записи раньше', () async {
      final repository = FavoritesRepository(db: db);

      await repository.toggle(1, 'cpp_syn_hello_world');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await repository.toggle(1, 'cpp_syn_variables');

      final list = await repository.listForUser(1);
      expect(list, hasLength(2));
      expect(list.first.articleId, 'cpp_syn_variables');
      expect(list.last.articleId, 'cpp_syn_hello_world');
      expect(list.first.createdAt.isAfter(list.last.createdAt), isTrue);
    });
  });

  group('HistoryRepository: запись и топ-20', () {
    test('запись просмотра видна в listTop как самая свежая', () async {
      final repository = HistoryRepository(db: db);

      await repository.record(1, 'cpp_syn_hello_world');
      final top = await repository.listTop(1);
      expect(top, hasLength(1));
      expect(top.single.articleId, 'cpp_syn_hello_world');
    });

    test(
      'повторное открытие не дублирует, а поднимает статью наверх',
      () async {
        final repository = HistoryRepository(db: db);

        await repository.record(1, 'cpp_syn_hello_world');
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await repository.record(1, 'cpp_syn_variables');
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await repository.record(1, 'cpp_syn_hello_world'); // повторный просмотр

        final top = await repository.listTop(1);
        expect(top, hasLength(2));
        expect(top.first.articleId, 'cpp_syn_hello_world');
        expect(top.last.articleId, 'cpp_syn_variables');
      },
    );

    test('25 записей → в истории топ-20, самые свежие', () async {
      final repository = HistoryRepository(db: db);

      // 25 статей с уникальным временем: поздние записи — свежее.
      for (var i = 1; i <= 25; i++) {
        await repository.record(1, 'cpp_test_article_$i');
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      final top = await repository.listTop(1);
      expect(top, hasLength(20), reason: 'лимит топ-20 из плана');

      // Остались самые свежие: статьи 6..25; статьи 1..5 подрезаны.
      expect(top.first.articleId, 'cpp_test_article_25');
      expect(top.last.articleId, 'cpp_test_article_6');
      for (var i = 1; i <= 5; i++) {
        expect(
          top.map((r) => r.articleId).contains('cpp_test_article_$i'),
          isFalse,
          reason: 'статья $i должна быть подрезана',
        );
      }

      // В самой таблице тоже ровно 20 строк пользователя 1 (подрезка
      // DELETE не входящих в топ-20).
      final rows = await db.query(
        AppDbTables.history,
        where: 'user_id = ?',
        whereArgs: [1],
      );
      expect(rows, hasLength(20));
    });

    test('изоляция: история первого пользователя не видна второму', () async {
      final repository = HistoryRepository(db: db);

      await repository.record(1, 'cpp_syn_variables');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await repository.record(1, 'cpp_ds_vector');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await repository.record(2, 'cpp_alg_recursion');

      final user1 = await repository.listTop(1);
      final user2 = await repository.listTop(2);
      expect(user1.map((r) => r.articleId).toList(), [
        'cpp_ds_vector',
        'cpp_syn_variables',
      ]);
      expect(user2.map((r) => r.articleId).toList(), ['cpp_alg_recursion']);
    });

    test('clear() очищает только историю текущего пользователя', () async {
      final repository = HistoryRepository(db: db);

      await repository.record(1, 'cpp_syn_variables');
      await repository.record(2, 'cpp_ds_vector');

      await repository.clear(1);

      expect(await repository.listTop(1), isEmpty);
      expect((await repository.listTop(2)).single.articleId, 'cpp_ds_vector');
    });
  });

  group('Провайдеры user-scoped (сессия → данные пользователя)', () {
    late SessionProvider session;
    late ArticleRepository articles;
    late SharedPreferences prefs;

    setUp(() async {
      // Фикстуры P8/P9 (test/widget/fixtures.dart): статьи fx_syn_var и
      // fx_stl_vector сшиваются с записями БД по id.
      articles = ArticleRepository.fromRaw(p8p9ReferenceFixtures);

      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      session = SessionProvider(
        repository: AuthRepository(db: db, prefs: prefs),
      );
    });

    Future<UserModel> register(String name) => session.register(
      username: name,
      email: '$name@example.com',
      password: 'пароль123',
    );

    test('toggle → сердечко/список; после logout данные скрыты', () async {
      final favorites = FavoritesProvider(
        articles: articles,
        repository: FavoritesRepository(db: db),
        session: session,
      );
      await favorites.reload();

      await register('u1');
      await favorites.reload();
      expect(favorites.currentUserId, isNotNull);
      expect(favorites.loading, isFalse);

      final added = await favorites.toggle('fx_syn_var');
      expect(added, isTrue);
      expect(favorites.isFavorite('fx_syn_var'), isTrue);
      expect(favorites.entries.map((entry) => entry.article.id).toList(), [
        'fx_syn_var',
      ]);

      // Выход: user-scoping — данные выгружаются (но в БД остаются).
      await session.logout();
      await favorites.reload();
      expect(favorites.currentUserId, isNull);
      expect(favorites.isFavorite('fx_syn_var'), isFalse);
      expect(favorites.entries, isEmpty);

      // Возврат пользователя: избранное восстановилось из БД.
      await session.login(loginOrEmail: 'u1', password: 'пароль123');
      await favorites.reload();
      expect(favorites.isFavorite('fx_syn_var'), isTrue);
      expect(favorites.entries.map((entry) => entry.article.id).toList(), [
        'fx_syn_var',
      ]);
    });

    test('смена пользователя: чужое избранное не видно', () async {
      final favorites = FavoritesProvider(
        articles: articles,
        repository: FavoritesRepository(db: db),
        session: session,
      );
      await favorites.reload();

      final first = await register('first');
      await favorites.reload();
      await favorites.toggle('fx_syn_var');

      // Второй пользователь: register сам логинит — выйдем и зарегистрируем.
      await session.logout();
      final second = await register('second');
      await favorites.reload();

      expect(second.id, isNot(first.id));
      expect(favorites.currentUserId, second.id);
      expect(favorites.isFavorite('fx_syn_var'), isFalse);
      expect(favorites.entries, isEmpty);

      // «Мёртвый» id (нет в контенте) не появляется в списке, но в БД есть.
      await favorites.toggle('fx_dead_id');
      expect(favorites.isFavorite('fx_dead_id'), isTrue);
      expect(
        favorites.entries,
        isEmpty,
        reason: 'список сшит только с контентом',
      );
    });

    test('история: record виден в топе, clear опустошает БД', () async {
      final history = HistoryProvider(
        articles: articles,
        repository: HistoryRepository(db: db),
        session: session,
      );
      await history.reload();

      await register('u1');
      await history.reload();

      await history.record('fx_syn_var');
      expect(history.entries.map((entry) => entry.article.id).toList(), [
        'fx_syn_var',
      ]);

      await history.record('fx_stl_vector');
      expect(history.entries.first.article.id, 'fx_stl_vector');
      expect(history.entries.last.article.id, 'fx_syn_var');

      // recent(count) — для секции «Продолжить» на home.
      expect(history.recent(), hasLength(2));
      expect(history.recent(count: 1).single.article.id, 'fx_stl_vector');

      await history.clear();
      expect(history.entries, isEmpty);

      // Данные реально удалены из БД (не только из состояния).
      final repository = HistoryRepository(db: db);
      expect(await repository.listTop(session.currentUser!.id), isEmpty);
    });

    test('гость: record и clear — no-op, состояние пустое', () async {
      final history = HistoryProvider(
        articles: articles,
        repository: HistoryRepository(db: db),
        session: session,
      );
      await history.reload();

      expect(history.currentUserId, isNull);
      await history.record('fx_syn_var');
      await history.clear();
      expect(history.entries, isEmpty);
      expect(history.loading, isFalse);
    });

    test(
      'clear при сбое БД пробрасывает Exception, а не молчит (P13)',
      () async {
        // Отдельное in-memory соединение: оно независимо от общей «db» теста
        // (каждый :memory: — своя база), закрытие ломает только этот провайдер.
        final broken = await databaseFactory.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(
            version: AppDatabase.dbVersion,
            onCreate: AppDatabase.onCreate,
          ),
        );
        final brokenSession = SessionProvider(
          repository: AuthRepository(db: broken, prefs: prefs),
        );
        await brokenSession.restoreSession();
        final user = await brokenSession.register(
          username: 'u_clearfail',
          email: 'u_clearfail@example.com',
          password: 'пароль123',
        );

        final history = HistoryProvider(
          articles: articles,
          repository: HistoryRepository(db: broken),
          session: brokenSession,
        );
        await history.reload();
        await history.record('fx_syn_var');
        expect(history.entries, hasLength(1));
        expect(user.id, isNotNull);

        // Ломаем соединение — clear обязан дать НАБЛЮДАЕМУЮ ошибку для
        // снекбара экрана, а не тихое «История очищена».
        await broken.close();
        await expectLater(history.clear(), throwsException);
        // Состояние провайдера при этом не испорчено.
        expect(history.entries, hasLength(1));
      },
    );
  });
}
