import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'api_exception.dart';

/// Интерфейс сетевого клиента.
///
/// Абстракция нужна, чтобы в widget-тестах подменять сеть фейковой
/// реализацией и не обращаться к реальному backend.
abstract class ApiClient {
  String? get token;
  set token(String? value);

  /// Вызывается при ответе 401 для уже авторизованного клиента.
  set onUnauthorized(void Function()? callback);

  Future<dynamic> get(String path, {Map<String, dynamic>? query});
  Future<dynamic> post(String path, {Object? body});
  Future<dynamic> put(String path, {Object? body});
  Future<dynamic> patch(String path, {Object? body});
  Future<dynamic> delete(String path);
}

/// HTTP-клиент backend: JSON, Bearer-токен, таймаут 10 с.
class HttpApiClient implements ApiClient {
  HttpApiClient({
    String baseUrl = AppConfig.apiBaseUrl,
    http.Client? httpClient,
    this.token,
  }) : _baseUrl = baseUrl.endsWith('/')
           ? baseUrl.substring(0, baseUrl.length - 1)
           : baseUrl,
       _http = httpClient ?? http.Client();

  final String _baseUrl;
  final http.Client _http;

  @override
  String? token;
  void Function()? _onUnauthorized;

  @override
  set onUnauthorized(void Function()? callback) => _onUnauthorized = callback;

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send('GET', path, query: query);

  @override
  Future<dynamic> post(String path, {Object? body}) =>
      _send('POST', path, body: body);

  @override
  Future<dynamic> put(String path, {Object? body}) =>
      _send('PUT', path, body: body);

  @override
  Future<dynamic> patch(String path, {Object? body}) =>
      _send('PATCH', path, body: body);

  @override
  Future<dynamic> delete(String path) => _send('DELETE', path);

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async {
    final uri = _buildUri(path, query);
    final headers = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json; charset=utf-8',
      if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
    };

    http.Response response;
    try {
      final request = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) {
        request.body = jsonEncode(body);
      }
      final streamed = await _http
          .send(request)
          .timeout(AppConfig.requestTimeout);
      response = await http.Response.fromStream(streamed)
          .timeout(AppConfig.requestTimeout);
    } on TimeoutException {
      throw ApiException.timeout();
    } on http.ClientException {
      throw ApiException.network();
    } catch (_) {
      throw ApiException.network();
    }

    dynamic decoded;
    if (response.statusCode != 204 && response.bodyBytes.isNotEmpty) {
      try {
        decoded = jsonDecode(utf8.decode(response.bodyBytes));
      } catch (_) {
        if (response.statusCode >= 400) {
          throw ApiException.fromResponse(response.statusCode, null);
        }
        throw ApiException.parse();
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (decoded is Map && decoded.containsKey('data')) {
        return decoded['data'];
      }
      return decoded;
    }

    if (response.statusCode == 401 && token != null && token!.isNotEmpty) {
      _onUnauthorized?.call();
    }
    throw ApiException.fromResponse(response.statusCode, decoded);
  }

  Uri _buildUri(String path, Map<String, dynamic>? query) {
    final normalized = path.startsWith('/') ? path : '/$path';
    final params = <String, String>{};
    if (query != null) {
      query.forEach((key, value) {
        if (value == null) return;
        final text = value.toString();
        if (text.isEmpty) return;
        params[key] = text;
      });
    }
    return Uri.parse('$_baseUrl$normalized')
        .replace(queryParameters: params.isEmpty ? null : params);
  }
}
