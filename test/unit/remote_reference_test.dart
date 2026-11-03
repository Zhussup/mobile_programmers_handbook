import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:mob_kurs/core/db/app_database.dart';
import 'package:mob_kurs/core/network/api_client.dart';
import 'package:mob_kurs/core/network/api_exception.dart';
import 'package:mob_kurs/features/reference/article_model.dart';
import 'package:mob_kurs/features/reference/reference_cache.dart';
import 'package:mob_kurs/features/reference/remote_reference_repository.dart';

/// Тесты удалённого репозитория справочника (КР_2_2, К8/К18): маппинг
/// JSON API в модели и отдача кэша sqflite при сетевой ошибке.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const baseUrl = 'http://api.test/api';

  late Database db;

  setUp(() async {
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

  final categories = [
    {
      'id': 'syntax',
      'title': 'Синтаксис',
      'icon': 'code',
      'description': 'Основы языка',
    },
  ];

  final articles = [
    {
      'id': 'a1',
      'category_id': 'syntax',
      'title': 'Переменные',
      'summary': 'Объявление переменных',
      'difficulty': 'beginner',
      'tags': ['var'],
      'blocks': [
        {'type': 'text', 'text': 'Переменная хранит значение.'},
      ],
    },
  ];

  http.Response json(Object? payload, {int status = 200}) => http.Response(
    jsonEncode(payload),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  ApiClient apiWith(
    Future<http.Response> Function(http.Request request) handler,
  ) => ApiClient(
    baseUrl: baseUrl,
    tokenStore: MemoryTokenStore(),
    client: MockClient(handler),
  );

  ApiClient okApi() => apiWith((request) async {
    if (request.url.path.endsWith('/categories')) {
      return json({'data': categories});
    }
    return json({'data': articles});
  });

  test('loadFromAssets разбирает категории и статьи из API', () async {
    final repo = RemoteReferenceRepository(
      apiClient: okApi(),
      cache: ReferenceCache(db: db),
    );

    await repo.loadFromAssets();

    expect(repo.isLoaded, isTrue);
    expect(repo.isFromCache, isFalse);
    expect(repo.categories.map((c) => c.id), ['syntax']);
    expect(repo.articlesForCategory('syntax').single.title, 'Переменные');
    expect(repo.articleById('a1')?.difficulty, Difficulty.beginner);
    expect(repo.categoryOfArticle('a1')?.title, 'Синтаксис');
  });

  test('сетевая ошибка → загрузка из кэша sqflite, isFromCache', () async {
    // Первый запуск — успешная загрузка и запись кэша.
    final online = RemoteReferenceRepository(
      apiClient: okApi(),
      cache: ReferenceCache(db: db),
    );
    await online.loadFromAssets();

    // Второй запуск без сети — те же данные из кэша.
    final offline = RemoteReferenceRepository(
      apiClient: apiWith(
        (_) async => throw http.ClientException('нет соединения'),
      ),
      cache: ReferenceCache(db: db),
    );
    await offline.loadFromAssets();

    expect(offline.isLoaded, isTrue);
    expect(offline.isFromCache, isTrue);
    expect(offline.categories.single.title, 'Синтаксис');
    expect(offline.articleById('a1')?.title, 'Переменные');
  });

  test('без кэша сетевая ошибка пробрасывается', () async {
    final repo = RemoteReferenceRepository(
      apiClient: apiWith(
        (_) async => throw http.ClientException('нет соединения'),
      ),
      cache: ReferenceCache(db: db),
    );

    await expectLater(
      repo.loadFromAssets(),
      throwsA(isA<ApiException>().having((e) => e.isNetwork, 'network', true)),
    );
  });

  test('ошибка 500 не подменяется кэшем — пробрасывается', () async {
    final online = RemoteReferenceRepository(
      apiClient: okApi(),
      cache: ReferenceCache(db: db),
    );
    await online.loadFromAssets();

    final repo = RemoteReferenceRepository(
      apiClient: apiWith(
        (_) async => json({
          'error': {'code': 'internal_error', 'message': 'Сбой сервера'},
        }, status: 500),
      ),
      cache: ReferenceCache(db: db),
    );

    await expectLater(
      repo.loadFromAssets(),
      throwsA(
        isA<ApiException>().having((e) => e.type, 'type', ApiErrorType.server),
      ),
    );
  });

  test('fetchArticles передаёт q/category/difficulty в query', () async {
    late http.Request captured;
    final repo = RemoteReferenceRepository(
      apiClient: apiWith((request) async {
        captured = request;
        return json({'data': articles});
      }),
      cache: ReferenceCache(db: db),
    );

    final result = await repo.fetchArticles(
      q: 'перем',
      categoryId: 'syntax',
      difficulty: Difficulty.beginner,
    );

    expect(captured.url.queryParameters, {
      'q': 'перем',
      'category': 'syntax',
      'difficulty': 'beginner',
    });
    expect(result.single.id, 'a1');
  });
}
