import 'dart:convert';
import 'dart:io';

import 'package:mob_kurs_backend/api/router.dart';
import 'package:mob_kurs_backend/core/db.dart';
import 'package:shelf/shelf.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

late Database db;
late Handler handler;

/// Каталог seed-контента: тесты запускаются из каталога backend/.
String _seedDir() {
  for (final candidate in [
    '../assets/content/reference',
    'assets/content/reference',
  ]) {
    if (Directory(candidate).existsSync()) return candidate;
  }
  return '../assets/content/reference';
}

Future<Response> api(
  String method,
  String path, {
  Object? body,
  String? token,
  Map<String, String>? headers,
}) async {
  final requestHeaders = <String, String>{...?headers};
  if (body != null) requestHeaders['content-type'] = 'application/json';
  if (token != null) requestHeaders['authorization'] = 'Bearer $token';
  return handler(
    Request(
      method,
      Uri.parse('http://localhost:8080$path'),
      headers: requestHeaders,
      body: body == null ? null : jsonEncode(body),
    ),
  );
}

Future<Map<String, dynamic>> jsonOf(Response response) async {
  final text = await response.readAsString();
  return jsonDecode(text) as Map<String, dynamic>;
}

Future<Object?> dataOf(Response response) async {
  final json = await jsonOf(response);
  return json['data'];
}

Future<String> errorCode(Response response) async {
  final json = await jsonOf(response);
  return (json['error'] as Map<String, dynamic>)['code'] as String;
}

Future<Map<String, dynamic>> loginRaw(String login, String password) async {
  final response = await api(
    'POST',
    '/api/auth/login',
    body: {'login': login, 'password': password},
  );
  expect(response.statusCode, 200, reason: 'вход $login');
  return (await dataOf(response))! as Map<String, dynamic>;
}

Future<String> loginToken(String login, String password) async {
  final data = await loginRaw(login, password);
  return data['token']! as String;
}

Future<Map<String, dynamic>> registerUser(
  String username, {
  String? email,
  String password = 'secret123',
}) async {
  final response = await api(
    'POST',
    '/api/auth/register',
    body: {
      'username': username,
      'email': email ?? '$username@example.com',
      'password': password,
    },
  );
  expect(response.statusCode, 201, reason: 'регистрация $username');
  return (await dataOf(response))! as Map<String, dynamic>;
}

Future<List<Map<String, dynamic>>> articleList(String token) async {
  final response = await api('GET', '/api/articles', token: token);
  expect(response.statusCode, 200);
  final data = await dataOf(response) as List<dynamic>;
  return data.cast<Map<String, dynamic>>();
}

void main() {
  setUpAll(sqfliteFfiInit);

  setUp(() async {
    db = await openAppDatabase(
      path: inMemoryDatabasePath,
      seed: true,
      seedDir: _seedDir(),
    );
    handler = createHandler(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('health и маршрутизация', () {
    test('GET /api/health публичный и возвращает status ok', () async {
      final response = await api('GET', '/api/health');
      expect(response.statusCode, 200);
      final data = await dataOf(response) as Map<String, dynamic>;
      expect(data['status'], 'ok');
      expect(response.headers['access-control-allow-origin'], '*');
    });

    test('OPTIONS возвращает 204 и заголовки CORS', () async {
      final response = await api('OPTIONS', '/api/articles');
      expect(response.statusCode, 204);
      expect(response.headers['access-control-allow-origin'], '*');
      expect(
        response.headers['access-control-allow-methods'],
        contains('PATCH'),
      );
    });

    test('неизвестный маршрут — 404 not_found', () async {
      final response = await api('GET', '/api/unknown');
      expect(response.statusCode, 404);
      expect(await errorCode(response), 'not_found');
    });

    test('закрытый маршрут без токена — 401 unauthorized', () async {
      final response = await api('GET', '/api/articles');
      expect(response.statusCode, 401);
      expect(await errorCode(response), 'unauthorized');
    });
  });

  group('регистрация и вход', () {
    test('успешная регистрация, вход по имени и почте', () async {
      final registered = await registerUser('newuser');
      final token = registered['token']! as String;
      final user = registered['user']! as Map<String, dynamic>;
      expect(token.length, 64);
      expect(user['username'], 'newuser');
      expect(user['email'], 'newuser@example.com');
      expect(user['role'], 'user');
      expect(user['is_blocked'], false);

      final byUsername = await loginRaw('newuser', 'secret123');
      final byEmail = await loginRaw('newuser@example.com', 'secret123');
      expect(byUsername['token'], isA<String>());
      expect(byEmail['user'], isA<Map<String, dynamic>>());
    });

    test('неверный пароль — 401 unauthorized', () async {
      final response = await api(
        'POST',
        '/api/auth/login',
        body: {'login': 'user', 'password': 'wrong-password'},
      );
      expect(response.statusCode, 401);
      expect(await errorCode(response), 'unauthorized');
    });

    test('занятые username и email — 409 conflict с полями', () async {
      final response = await api(
        'POST',
        '/api/auth/register',
        body: {
          'username': 'USER',
          'email': 'User@Example.com',
          'password': 'secret123',
        },
      );
      expect(response.statusCode, 409);
      final json = await jsonOf(response);
      final error = json['error'] as Map<String, dynamic>;
      expect(error['code'], 'conflict');
      final fields = error['fields'] as Map<String, dynamic>;
      expect(fields.containsKey('username'), isTrue);
      expect(fields.containsKey('email'), isTrue);
    });

    test('валидация регистрации — 400 и fields', () async {
      final response = await api(
        'POST',
        '/api/auth/register',
        body: {'username': 'ab', 'email': 'bad-email', 'password': '123'},
      );
      expect(response.statusCode, 400);
      final json = await jsonOf(response);
      final error = json['error'] as Map<String, dynamic>;
      expect(error['code'], 'validation_error');
      final fields = error['fields'] as Map<String, dynamic>;
      expect(fields.keys, containsAll(['username', 'email', 'password']));
    });

    test('me, logout и повторный me — 204 и 401', () async {
      final token = await loginToken('user', 'user123');
      final me = await api('GET', '/api/auth/me', token: token);
      expect(me.statusCode, 200);
      expect((await dataOf(me) as Map<String, dynamic>)['username'], 'user');

      final logout = await api('POST', '/api/auth/logout', token: token);
      expect(logout.statusCode, 204);

      final afterLogout = await api('GET', '/api/auth/me', token: token);
      expect(afterLogout.statusCode, 401);
    });

    test('недействительный токен — 401', () async {
      final response = await api('GET', '/api/auth/me', token: 'a' * 64);
      expect(response.statusCode, 401);
    });
  });

  group('блокировка и роли', () {
    test('блокировка удаляет сессии и запрещает вход', () async {
      final admin = await loginToken('admin', 'admin123');
      final userData = await loginRaw('user', 'user123');
      final userToken = userData['token']! as String;
      final userId = (userData['user']! as Map<String, dynamic>)['id'];

      final block = await api(
        'PATCH',
        '/api/admin/users/$userId/block',
        token: admin,
        body: {'blocked': true},
      );
      expect(block.statusCode, 200);
      expect((await dataOf(block) as Map<String, dynamic>)['is_blocked'], true);

      final me = await api('GET', '/api/auth/me', token: userToken);
      expect(me.statusCode, 401);

      final blockedLogin = await api(
        'POST',
        '/api/auth/login',
        body: {'login': 'user', 'password': 'user123'},
      );
      expect(blockedLogin.statusCode, 403);
      expect(await errorCode(blockedLogin), 'user_blocked');

      final unblock = await api(
        'PATCH',
        '/api/admin/users/$userId/block',
        token: admin,
        body: {'blocked': false},
      );
      expect(unblock.statusCode, 200);
      await loginRaw('user', 'user123');
    });

    test('обычный пользователь не попадает в admin — 403 forbidden', () async {
      final token = await loginToken('user', 'user123');
      final response = await api('GET', '/api/admin/users', token: token);
      expect(response.statusCode, 403);
      expect(await errorCode(response), 'forbidden');
    });

    test('нельзя заблокировать и понизить самого себя', () async {
      final adminData = await loginRaw('admin', 'admin123');
      final adminToken = adminData['token']! as String;
      final adminId = (adminData['user']! as Map<String, dynamic>)['id'];

      final selfBlock = await api(
        'PATCH',
        '/api/admin/users/$adminId/block',
        token: adminToken,
        body: {'blocked': true},
      );
      expect(selfBlock.statusCode, 400);

      final selfDemote = await api(
        'PATCH',
        '/api/admin/users/$adminId/role',
        token: adminToken,
        body: {'role': 'user'},
      );
      expect(selfDemote.statusCode, 400);
    });
  });

  group('администрирование пользователей', () {
    test('список, поиск, создание, изменение, роль и блокировка', () async {
      final admin = await loginToken('admin', 'admin123');

      final list = await api('GET', '/api/admin/users', token: admin);
      expect(list.statusCode, 200);
      expect((await dataOf(list) as List<dynamic>).length, 2);

      final search = await api(
        'GET',
        '/api/admin/users?q=admin@',
        token: admin,
      );
      final found = (await dataOf(search) as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(found.length, 1);
      expect(found.first['username'], 'admin');

      final created = await api(
        'POST',
        '/api/admin/users',
        token: admin,
        body: {
          'username': 'created',
          'email': 'created@example.com',
          'password': 'secret123',
          'role': 'user',
        },
      );
      expect(created.statusCode, 201);
      final createdUser = await dataOf(created) as Map<String, dynamic>;
      final createdId = createdUser['id'];

      final duplicate = await api(
        'POST',
        '/api/admin/users',
        token: admin,
        body: {
          'username': 'created',
          'email': 'other@example.com',
          'password': 'secret123',
          'role': 'user',
        },
      );
      expect(duplicate.statusCode, 409);

      final updated = await api(
        'PUT',
        '/api/admin/users/$createdId',
        token: admin,
        body: {
          'username': 'renamed',
          'email': 'renamed@example.com',
          'avatar_color': '#112233',
        },
      );
      expect(updated.statusCode, 200);
      final updatedUser = await dataOf(updated) as Map<String, dynamic>;
      expect(updatedUser['username'], 'renamed');
      expect(updatedUser['avatar_color'], '#112233');

      final promoted = await api(
        'PATCH',
        '/api/admin/users/$createdId/role',
        token: admin,
        body: {'role': 'admin'},
      );
      expect(promoted.statusCode, 200);
      expect((await dataOf(promoted) as Map<String, dynamic>)['role'], 'admin');

      final blocked = await api(
        'PATCH',
        '/api/admin/users/$createdId/block',
        token: admin,
        body: {'blocked': true},
      );
      expect(blocked.statusCode, 200);

      final missing = await api(
        'PUT',
        '/api/admin/users/9999',
        token: admin,
        body: {'username': 'nobody'},
      );
      expect(missing.statusCode, 404);
    });
  });

  group('контент', () {
    test('seed: 6 категорий и 46 опубликованных статей', () async {
      final token = await loginToken('user', 'user123');
      final categories = await api('GET', '/api/categories', token: token);
      expect(categories.statusCode, 200);
      final categoryData = await dataOf(categories) as List<dynamic>;
      expect(categoryData.length, 6);

      final articles = await articleList(token);
      expect(articles.length, 46);
      expect(
        articles.every((article) => article['is_published'] == true),
        isTrue,
      );
    });

    test('фильтры category, difficulty и поиск q', () async {
      final token = await loginToken('user', 'user123');

      final syntax = await articleList(token);
      final byCategory = await api(
        'GET',
        '/api/articles?category=syntax',
        token: token,
      );
      final syntaxList = (await dataOf(byCategory) as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(syntaxList, isNotEmpty);
      expect(
        syntaxList.every((article) => article['category_id'] == 'syntax'),
        isTrue,
      );
      expect(syntaxList.length, lessThan(syntax.length));

      final byDifficulty = await api(
        'GET',
        '/api/articles?difficulty=advanced',
        token: token,
      );
      final advanced = (await dataOf(byDifficulty) as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(advanced, isNotEmpty);
      expect(
        advanced.every((article) => article['difficulty'] == 'advanced'),
        isTrue,
      );

      final search = await api('GET', '/api/articles?q=hello', token: token);
      final found = (await dataOf(search) as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(found, isNotEmpty);
      expect(
        found.any((article) => article['id'] == 'cpp_syn_hello_world'),
        isTrue,
      );
    });

    test('детальная статья и 404 для неизвестной', () async {
      final token = await loginToken('user', 'user123');
      final detail = await api(
        'GET',
        '/api/articles/cpp_syn_hello_world',
        token: token,
      );
      expect(detail.statusCode, 200);
      final article = await dataOf(detail) as Map<String, dynamic>;
      expect(article['title'], isNotEmpty);
      expect(article['tags'], isA<List<dynamic>>());
      expect(article['blocks'], isA<List<dynamic>>());

      final missing = await api(
        'GET',
        '/api/articles/does_not_exist',
        token: token,
      );
      expect(missing.statusCode, 404);
    });
  });

  group('администрирование статей', () {
    test('создание, изменение, публикация и удаление', () async {
      final admin = await loginToken('admin', 'admin123');
      final created = await api(
        'POST',
        '/api/admin/articles',
        token: admin,
        body: {
          'id': 'test_article',
          'title': 'Тестовая статья',
          'summary': 'Краткое описание',
          'category_id': 'syntax',
          'difficulty': 'intermediate',
          'tags': ['тест', 'api'],
          'blocks': [
            {'type': 'text', 'text': 'Первый блок'},
          ],
          'is_published': false,
        },
      );
      expect(created.statusCode, 201);
      final article = await dataOf(created) as Map<String, dynamic>;
      expect(article['id'], 'test_article');
      expect(article['is_published'], false);
      expect(article['tags'], ['тест', 'api']);

      final duplicate = await api(
        'POST',
        '/api/admin/articles',
        token: admin,
        body: {'id': 'test_article', 'title': 'Дубликат', 'category': 'syntax'},
      );
      expect(duplicate.statusCode, 409);

      final userToken = await loginToken('user', 'user123');
      final hidden = await api(
        'GET',
        '/api/articles/test_article',
        token: userToken,
      );
      expect(hidden.statusCode, 404);
      final visibleForAdmin = await api(
        'GET',
        '/api/articles/test_article',
        token: admin,
      );
      expect(visibleForAdmin.statusCode, 200);

      final published = await api(
        'PATCH',
        '/api/admin/articles/test_article/publish',
        token: admin,
        body: {'published': true},
      );
      expect(published.statusCode, 200);
      expect(
        (await dataOf(published) as Map<String, dynamic>)['is_published'],
        true,
      );
      expect(
        (await api(
          'GET',
          '/api/articles/test_article',
          token: userToken,
        )).statusCode,
        200,
      );

      // Пользовательские данные, связанные со статьёй: при удалении статьи
      // они должны исчезнуть по ON DELETE CASCADE.
      expect(
        (await api(
          'POST',
          '/api/favorites/test_article',
          token: userToken,
        )).statusCode,
        201,
      );
      expect(
        (await api(
          'POST',
          '/api/history/test_article',
          token: userToken,
        )).statusCode,
        201,
      );

      final updated = await api(
        'PUT',
        '/api/admin/articles/test_article',
        token: admin,
        body: {
          'title': 'Обновлённая статья',
          'difficulty': 'advanced',
          'tags': ['обновлено'],
          'blocks': [
            {'type': 'heading', 'text': 'Заголовок'},
          ],
        },
      );
      expect(updated.statusCode, 200);
      final updatedArticle = await dataOf(updated) as Map<String, dynamic>;
      expect(updatedArticle['title'], 'Обновлённая статья');
      expect(updatedArticle['difficulty'], 'advanced');
      expect(updatedArticle['tags'], ['обновлено']);

      final unpublished = await api(
        'PATCH',
        '/api/admin/articles/test_article/publish',
        token: admin,
        body: {'published': false},
      );
      expect(
        (await dataOf(unpublished) as Map<String, dynamic>)['is_published'],
        false,
      );
      expect(
        (await api(
          'GET',
          '/api/articles/test_article',
          token: userToken,
        )).statusCode,
        404,
      );

      final deleted = await api(
        'DELETE',
        '/api/admin/articles/test_article',
        token: admin,
      );
      expect(deleted.statusCode, 204);

      final favoriteRows = await db.query(
        'favorites',
        where: 'article_id = ?',
        whereArgs: ['test_article'],
      );
      final historyRows = await db.query(
        'history',
        where: 'article_id = ?',
        whereArgs: ['test_article'],
      );
      expect(favoriteRows, isEmpty);
      expect(historyRows, isEmpty);

      expect(
        (await api(
          'GET',
          '/api/admin/articles?q=test_article',
          token: admin,
        )).statusCode,
        200,
      );
      expect(
        (await api(
          'PUT',
          '/api/admin/articles/test_article',
          token: admin,
          body: {'title': 'Нет'},
        )).statusCode,
        404,
      );
    });

    test('валидация статьи — 400 и fields', () async {
      final admin = await loginToken('admin', 'admin123');
      final missingTitle = await api(
        'POST',
        '/api/admin/articles',
        token: admin,
        body: {'title': '', 'category_id': 'syntax'},
      );
      expect(missingTitle.statusCode, 400);
      final error =
          (await jsonOf(missingTitle))['error'] as Map<String, dynamic>;
      expect(
        (error['fields'] as Map<String, dynamic>).containsKey('title'),
        isTrue,
      );

      final badCategory = await api(
        'POST',
        '/api/admin/articles',
        token: admin,
        body: {
          'title': 'Статья',
          'category_id': 'unknown',
          'difficulty': 'expert',
          'tags': 'not-a-list',
        },
      );
      expect(badCategory.statusCode, 400);
      final fields =
          ((await jsonOf(badCategory))['error']
                  as Map<String, dynamic>)['fields']
              as Map<String, dynamic>;
      expect(fields.keys, containsAll(['category_id', 'difficulty', 'tags']));
    });

    test('админский список статей фильтруется по published', () async {
      final admin = await loginToken('admin', 'admin123');
      await api(
        'POST',
        '/api/admin/articles',
        token: admin,
        body: {
          'id': 'draft_article',
          'title': 'Черновик',
          'category_id': 'syntax',
          'is_published': false,
        },
      );

      final drafts = await api(
        'GET',
        '/api/admin/articles?published=false',
        token: admin,
      );
      expect(drafts.statusCode, 200);
      final draftList = (await dataOf(drafts) as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(draftList.length, 1);
      expect(draftList.first['id'], 'draft_article');

      final all = await api('GET', '/api/admin/articles', token: admin);
      expect((await dataOf(all) as List<dynamic>).length, 47);
    });
  });

  group('администрирование категорий', () {
    test('создание, изменение, запрет удаления непустой и удаление', () async {
      final admin = await loginToken('admin', 'admin123');
      final created = await api(
        'POST',
        '/api/admin/categories',
        token: admin,
        body: {
          'id': 'test_category',
          'title': 'Тестовая категория',
          'description': 'Описание',
          'icon': 'book',
          'sort_order': 100,
        },
      );
      expect(created.statusCode, 201);
      expect(
        (await dataOf(created) as Map<String, dynamic>)['id'],
        'test_category',
      );

      final duplicate = await api(
        'POST',
        '/api/admin/categories',
        token: admin,
        body: {'id': 'test_category', 'title': 'Ещё одна'},
      );
      expect(duplicate.statusCode, 409);

      final invalid = await api(
        'POST',
        '/api/admin/categories',
        token: admin,
        body: {'id': 'bad id', 'title': ''},
      );
      expect(invalid.statusCode, 400);

      final updated = await api(
        'PUT',
        '/api/admin/categories/test_category',
        token: admin,
        body: {'title': 'Переименована', 'sort_order': 5},
      );
      expect(updated.statusCode, 200);
      expect(
        (await dataOf(updated) as Map<String, dynamic>)['title'],
        'Переименована',
      );

      final nonEmpty = await api(
        'DELETE',
        '/api/admin/categories/syntax',
        token: admin,
      );
      expect(nonEmpty.statusCode, 409);

      final deleted = await api(
        'DELETE',
        '/api/admin/categories/test_category',
        token: admin,
      );
      expect(deleted.statusCode, 204);
      final list = await api('GET', '/api/admin/categories', token: admin);
      final ids = (await dataOf(list) as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((category) => category['id']);
      expect(ids, isNot(contains('test_category')));
    });
  });

  group('избранное', () {
    test('добавление идемпотентно, список и удаление', () async {
      final token = await loginToken('user', 'user123');
      const articleId = 'cpp_syn_hello_world';

      final first = await api(
        'POST',
        '/api/favorites/$articleId',
        token: token,
      );
      expect(first.statusCode, 201);
      final second = await api(
        'POST',
        '/api/favorites/$articleId',
        token: token,
      );
      expect(second.statusCode, 200);

      final list = await api('GET', '/api/favorites', token: token);
      final favorites = (await dataOf(list) as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(favorites.length, 1);
      expect(favorites.first['id'], articleId);
      expect(favorites.first['favorited_at'], isA<String>());

      final removed = await api(
        'DELETE',
        '/api/favorites/$articleId',
        token: token,
      );
      expect(removed.statusCode, 204);
      final empty = await api('GET', '/api/favorites', token: token);
      expect((await dataOf(empty) as List<dynamic>), isEmpty);

      final missing = await api(
        'POST',
        '/api/favorites/unknown_article',
        token: token,
      );
      expect(missing.statusCode, 404);
    });
  });

  group('история', () {
    test('просмотры не дублируются, limit и очистка', () async {
      final token = await loginToken('user', 'user123');
      final first = await api(
        'POST',
        '/api/history/cpp_syn_hello_world',
        token: token,
      );
      expect(first.statusCode, 201);
      final repeat = await api(
        'POST',
        '/api/history/cpp_syn_hello_world',
        token: token,
      );
      expect(repeat.statusCode, 200);

      var list = await api('GET', '/api/history', token: token);
      var history = (await dataOf(list) as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(history.length, 1);
      expect(history.first['viewed_at'], isA<String>());

      await api('POST', '/api/history/cpp_syn_variables', token: token);
      await api('POST', '/api/history/cpp_syn_operators', token: token);

      list = await api('GET', '/api/history?limit=2', token: token);
      history = (await dataOf(list) as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(history.length, 2);

      final cleared = await api('DELETE', '/api/history', token: token);
      expect(cleared.statusCode, 204);
      list = await api('GET', '/api/history', token: token);
      expect((await dataOf(list) as List<dynamic>), isEmpty);

      final missing = await api(
        'POST',
        '/api/history/unknown_article',
        token: token,
      );
      expect(missing.statusCode, 404);
    });
  });

  group('сниппеты', () {
    test('CRUD, валидация и изоляция пользователей', () async {
      final token = await loginToken('user', 'user123');
      final created = await api(
        'POST',
        '/api/snippets',
        token: token,
        body: {
          'title': 'Мой сниппет',
          'language': 'cpp',
          'code': 'int main() { return 0; }',
          'expected_output': '',
        },
      );
      expect(created.statusCode, 201);
      final snippet = await dataOf(created) as Map<String, dynamic>;
      final snippetId = snippet['id'];
      expect(snippet['language'], 'cpp');

      final list = await api('GET', '/api/snippets', token: token);
      expect((await dataOf(list) as List<dynamic>).length, 1);

      final got = await api('GET', '/api/snippets/$snippetId', token: token);
      expect(got.statusCode, 200);

      final updated = await api(
        'PUT',
        '/api/snippets/$snippetId',
        token: token,
        body: {
          'title': 'Обновлённый',
          'language': 'dart',
          'code': 'void main() {}',
          'expected_output': 'ok',
        },
      );
      expect(updated.statusCode, 200);
      final updatedSnippet = await dataOf(updated) as Map<String, dynamic>;
      expect(updatedSnippet['title'], 'Обновлённый');
      expect(updatedSnippet['language'], 'dart');

      final invalid = await api(
        'POST',
        '/api/snippets',
        token: token,
        body: {'title': '', 'language': 'python'},
      );
      expect(invalid.statusCode, 400);

      final other = await registerUser('second');
      final otherToken = other['token']! as String;
      final foreign = await api(
        'GET',
        '/api/snippets/$snippetId',
        token: otherToken,
      );
      expect(foreign.statusCode, 404);

      final deleted = await api(
        'DELETE',
        '/api/snippets/$snippetId',
        token: token,
      );
      expect(deleted.statusCode, 204);
      expect(
        (await api('GET', '/api/snippets/$snippetId', token: token)).statusCode,
        404,
      );
      expect(
        (await api(
          'DELETE',
          '/api/snippets/$snippetId',
          token: token,
        )).statusCode,
        404,
      );
    });
  });

  group('профиль', () {
    test('изменение данных и смена пароля', () async {
      final token = await loginToken('user', 'user123');

      final updated = await api(
        'PUT',
        '/api/profile',
        token: token,
        body: {
          'username': 'newlogin',
          'email': 'newlogin@example.com',
          'avatar_color': '#AABBCC',
        },
      );
      expect(updated.statusCode, 200);
      final profile = await dataOf(updated) as Map<String, dynamic>;
      expect(profile['username'], 'newlogin');
      expect(profile['avatar_color'], '#AABBCC');
      await loginRaw('newlogin', 'user123');

      final conflict = await api(
        'PUT',
        '/api/profile',
        token: token,
        body: {'email': 'admin@example.com'},
      );
      expect(conflict.statusCode, 409);

      final wrongOld = await api(
        'PUT',
        '/api/profile/password',
        token: token,
        body: {'old_password': 'wrong', 'new_password': 'newsecret'},
      );
      expect(wrongOld.statusCode, 400);

      final changed = await api(
        'PUT',
        '/api/profile/password',
        token: token,
        body: {'old_password': 'user123', 'new_password': 'newsecret'},
      );
      expect(changed.statusCode, 200);

      final oldPassword = await api(
        'POST',
        '/api/auth/login',
        body: {'login': 'newlogin', 'password': 'user123'},
      );
      expect(oldPassword.statusCode, 401);
      await loginRaw('newlogin', 'newsecret');
    });
  });
}
