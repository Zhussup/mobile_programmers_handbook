import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:mob_kurs/core/network/api_client.dart';
import 'package:mob_kurs/core/network/api_exception.dart';

/// Тесты сетевого слоя (КР_2_2, К10/К12): разбор `{"data":...}` и
/// `{"error":...}`, коды ошибок, таймаут/сеть, Bearer-заголовок.
void main() {
  const baseUrl = 'http://api.test/api';

  ApiClient build(
    Future<http.Response> Function(http.Request request) handler, {
    TokenStore? tokenStore,
    Duration timeout = const Duration(seconds: 10),
  }) {
    return ApiClient(
      baseUrl: baseUrl,
      tokenStore: tokenStore ?? MemoryTokenStore(),
      client: MockClient(handler),
      timeout: timeout,
    );
  }

  http.Response json(Object? payload, {int status = 200}) => http.Response(
    jsonEncode(payload),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  group('успешные ответы', () {
    test('GET возвращает поле data', () async {
      final client = build(
        (_) async => json({
          'data': [
            {'id': 1, 'title': 'Статья'},
          ],
        }),
      );

      final result = await client.get('/articles') as List<dynamic>;

      expect(result, hasLength(1));
      expect((result.first as Map<String, dynamic>)['title'], 'Статья');
    });

    test('ответ без обёртки data возвращается как есть', () async {
      final client = build((_) async => json({'ok': true}));

      expect(await client.get('/health'), {'ok': true});
    });

    test('204 No Content → null', () async {
      final client = build((_) async => http.Response('', 204));

      expect(await client.delete('/history'), isNull);
    });

    test('POST кодирует тело и Content-Type', () async {
      late http.Request captured;
      final client = build((request) async {
        captured = request;
        return json({
          'data': {'ok': true},
        }, status: 201);
      });

      await client.post('/auth/login', body: {'login': 'u', 'password': 'p'});

      expect(captured.method, 'POST');
      expect(captured.headers['Content-Type'], contains('application/json'));
      expect(jsonDecode(captured.body), {'login': 'u', 'password': 'p'});
    });

    test('Bearer-токен добавляется в Authorization', () async {
      late http.Request captured;
      final client = build((request) async {
        captured = request;
        return json({'data': null});
      }, tokenStore: MemoryTokenStore('secret-token'));

      await client.get('/auth/me');

      expect(captured.headers['Authorization'], 'Bearer secret-token');
    });

    test('гостевой запрос идёт без Authorization', () async {
      late http.Request captured;
      final client = build((request) async {
        captured = request;
        return json({'data': null});
      });

      await client.get('/categories');

      expect(captured.headers.containsKey('Authorization'), isFalse);
    });

    test('query-параметры попадают в URI, пустые — отбрасываются', () async {
      late http.Request captured;
      final client = build((request) async {
        captured = request;
        return json({'data': []});
      });

      await client.get(
        '/articles',
        query: {'q': 'цикл', 'category': '', 'difficulty': null},
      );

      expect(captured.url.queryParameters, {'q': 'цикл'});
    });
  });

  group('ошибки контракта', () {
    test('400 → validation с полями', () async {
      final client = build(
        (_) async => json({
          'error': {
            'code': 'validation_error',
            'message': 'Проверьте поля',
            'fields': {'email': 'Некорректный email'},
          },
        }, status: 400),
      );

      await expectLater(
        client.post('/auth/register'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.type, 'type', ApiErrorType.validation)
              .having((e) => e.message, 'message', 'Проверьте поля')
              .having((e) => e.fields['email'], 'email', 'Некорректный email'),
        ),
      );
    });

    test('401 при наличии токена вызывает onUnauthorized', () async {
      var called = 0;
      final client = build(
        (_) async => json({
          'error': {'code': 'unauthorized', 'message': 'Требуется вход'},
        }, status: 401),
        tokenStore: MemoryTokenStore('token'),
      )..onUnauthorized = () => called++;

      await expectLater(
        client.get('/auth/me'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.type,
            'type',
            ApiErrorType.unauthorized,
          ),
        ),
      );
      expect(called, 1);
    });

    test('401 без токена не дёргает onUnauthorized', () async {
      var called = 0;
      final client = build(
        (_) async => json({
          'error': {'code': 'unauthorized', 'message': 'Неверный пароль'},
        }, status: 401),
      )..onUnauthorized = () => called++;

      await expectLater(
        client.post('/auth/login'),
        throwsA(isA<ApiException>()),
      );
      expect(called, 0);
    });

    test('403 user_blocked вызывает onUserBlocked', () async {
      var called = 0;
      final client = build(
        (_) async => json({
          'error': {
            'code': 'user_blocked',
            'message': 'Учётная запись заблокирована',
          },
        }, status: 403),
        tokenStore: MemoryTokenStore('token'),
      )..onUserBlocked = () => called++;

      await expectLater(
        client.get('/auth/me'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.type, 'type', ApiErrorType.forbidden)
              .having((e) => e.isUserBlocked, 'isUserBlocked', isTrue),
        ),
      );
      expect(called, 1);
    });

    test('404/409/500 маппятся в свои типы', () async {
      Future<void> expectStatus(int status, ApiErrorType type) async {
        final client = build(
          (_) async => json({
            'error': {'code': 'x', 'message': 'Ошибка'},
          }, status: status),
        );
        await expectLater(
          client.get('/x'),
          throwsA(isA<ApiException>().having((e) => e.type, 'type', type)),
        );
      }

      await expectStatus(404, ApiErrorType.notFound);
      await expectStatus(409, ApiErrorType.conflict);
      await expectStatus(500, ApiErrorType.server);
    });

    test('ошибка без обёртки error тоже разбирается', () async {
      final client = build(
        (_) async =>
            json({'code': 'conflict', 'message': 'Занято'}, status: 409),
      );

      await expectLater(
        client.get('/x'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.type, 'type', ApiErrorType.conflict)
              .having((e) => e.message, 'message', 'Занято'),
        ),
      );
    });

    test('не-JSON в 2xx → parse', () async {
      final client = build((_) async => http.Response('<html>', 200));

      await expectLater(
        client.get('/x'),
        throwsA(
          isA<ApiException>().having((e) => e.type, 'type', ApiErrorType.parse),
        ),
      );
    });

    test('не-JSON в ошибке → сообщение по статусу', () async {
      final client = build((_) async => http.Response('oops', 502));

      await expectLater(
        client.get('/x'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.type,
            'type',
            ApiErrorType.server,
          ),
        ),
      );
    });
  });

  group('сетевые сбои', () {
    test('ClientException → network', () async {
      final client = build(
        (_) async => throw http.ClientException('нет соединения'),
      );

      await expectLater(
        client.get('/categories'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.type,
            'type',
            ApiErrorType.network,
          ),
        ),
      );
    });

    test('превышение таймаута → timeout', () async {
      final client = build((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return json({'data': null});
      }, timeout: const Duration(milliseconds: 20));

      await expectLater(
        client.get('/slow'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.type,
            'type',
            ApiErrorType.timeout,
          ),
        ),
      );
    });

    test('таймаут по умолчанию — 10 секунд', () {
      final client = ApiClient(
        baseUrl: baseUrl,
        tokenStore: MemoryTokenStore(),
        client: MockClient((_) async => http.Response('', 204)),
      );

      expect(client.timeout, const Duration(seconds: 10));
    });
  });
}
