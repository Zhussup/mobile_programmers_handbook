import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mob_kurs_admin/core/network/api_client.dart';
import 'package:mob_kurs_admin/core/network/api_exception.dart';

http.Response _jsonResponse(Object body, int status) {
  return http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    status,
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );
}

void main() {
  test('успешный ответ разворачивает поле data и передаёт токен', () async {
    late http.Request captured;
    final api = HttpApiClient(
      baseUrl: 'http://test/api',
      token: 'secret',
      httpClient: MockClient((request) async {
        captured = request;
        return _jsonResponse(<String, dynamic>{
          'data': <String, dynamic>{'status': 'ok'},
        }, 200);
      }),
    );

    final result = await api.get('/health');

    expect(result, <String, dynamic>{'status': 'ok'});
    expect(captured.url.toString(), 'http://test/api/health');
    expect(captured.headers['Authorization'], 'Bearer secret');
  });

  test('ошибка 400 разбирается в ApiException с полями', () async {
    final api = HttpApiClient(
      baseUrl: 'http://test/api',
      httpClient: MockClient(
        (_) async => _jsonResponse(<String, dynamic>{
          'error': <String, dynamic>{
            'code': 'validation_error',
            'message': 'Поле email обязательно',
            'fields': <String, dynamic>{'email': 'Введите email'},
          },
        }, 400),
      ),
    );

    await expectLater(
      api.post('/auth/register', body: <String, dynamic>{'email': ''}),
      throwsA(
        isA<ApiException>()
            .having((e) => e.kind, 'kind', ApiErrorKind.validation)
            .having((e) => e.message, 'message', 'Поле email обязательно')
            .having((e) => e.statusCode, 'statusCode', 400)
            .having((e) => e.fields['email'], 'field email', 'Введите email'),
      ),
    );
  });

  test('401 с токеном вызывает onUnauthorized', () async {
    var unauthorizedCalled = false;
    final api = HttpApiClient(
      baseUrl: 'http://test/api',
      token: 'expired',
      httpClient: MockClient(
        (_) async => _jsonResponse(<String, dynamic>{
          'error': <String, dynamic>{
            'code': 'unauthorized',
            'message': 'Токен недействителен',
          },
        }, 401),
      ),
    )..onUnauthorized = () => unauthorizedCalled = true;

    await expectLater(
      api.get('/admin/users'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.kind,
          'kind',
          ApiErrorKind.unauthorized,
        ),
      ),
    );
    expect(unauthorizedCalled, isTrue);
  });

  test('204 возвращает null', () async {
    final api = HttpApiClient(
      baseUrl: 'http://test/api',
      token: 'secret',
      httpClient: MockClient((_) async => http.Response('', 204)),
    );

    expect(await api.delete('/admin/articles/1'), isNull);
  });
}
