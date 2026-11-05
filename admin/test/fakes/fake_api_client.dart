import 'dart:async';

import 'package:mob_kurs_admin/core/network/api_client.dart';
import 'package:mob_kurs_admin/core/network/api_exception.dart';

/// Запрос, зафиксированный фейковым клиентом.
class FakeRequest {
  FakeRequest({
    required this.method,
    required this.path,
    this.query,
    this.body,
  });

  final String method;
  final String path;
  final Map<String, dynamic>? query;
  final Object? body;
}

typedef FakeHandler = FutureOr<dynamic> Function(FakeRequest request);

/// API-клиент без сети: обработчики задаются в тесте по ключу «METHOD /path».
class FakeApiClient implements ApiClient {
  FakeApiClient({this.token});

  final Map<String, FakeHandler> _handlers = <String, FakeHandler>{};

  /// Все выполненные запросы — для проверок в тестах.
  final List<FakeRequest> requests = <FakeRequest>[];

  @override
  String? token;

  @override
  void Function()? onUnauthorized;

  void on(String method, String path, FakeHandler handler) {
    _handlers['$method $path'] = handler;
  }

  /// Добавляет простой ответ (не функцию).
  void onData(String method, String path, dynamic data) {
    _handlers['$method $path'] = (_) => data;
  }

  /// Добавляет ошибку API для запроса.
  void onError(String method, String path, ApiException error) {
    _handlers['$method $path'] = (_) => throw error;
  }

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _handle(FakeRequest(method: 'GET', path: path, query: query));

  @override
  Future<dynamic> post(String path, {Object? body}) =>
      _handle(FakeRequest(method: 'POST', path: path, body: body));

  @override
  Future<dynamic> put(String path, {Object? body}) =>
      _handle(FakeRequest(method: 'PUT', path: path, body: body));

  @override
  Future<dynamic> patch(String path, {Object? body}) =>
      _handle(FakeRequest(method: 'PATCH', path: path, body: body));

  @override
  Future<dynamic> delete(String path) =>
      _handle(FakeRequest(method: 'DELETE', path: path));

  Future<dynamic> _handle(FakeRequest request) async {
    requests.add(request);
    final handler = _handlers['${request.method} ${request.path}'];
    if (handler == null) {
      throw ApiException(
        kind: ApiErrorKind.notFound,
        statusCode: 404,
        message: 'Нет обработчика ${request.method} ${request.path}',
      );
    }
    return handler(request);
  }
}
