import 'dart:async';
import 'dart:convert';
import 'dart:io' show HandshakeException, SocketException;

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';
import 'api_exception.dart';

/// Хранилище токена авторизации (Bearer).
///
/// В приложении — [PrefsTokenStore] (shared_preferences, ключ `auth_token`);
/// в unit-тестах удобен [MemoryTokenStore] без платформенных зависимостей.
abstract class TokenStore {
  /// Текущий токен (null — гость).
  String? get token;

  /// Сохранить токен или удалить его (null).
  Future<void> save(String? value);
}

/// Токен в shared_preferences (ключ `auth_token`).
class PrefsTokenStore implements TokenStore {
  /// Хранилище поверх общего экземпляра prefs.
  PrefsTokenStore(this._prefs);

  final SharedPreferences _prefs;

  @override
  String? get token => _prefs.getString(AppConstants.prefAuthToken);

  @override
  Future<void> save(String? value) async {
    if (value == null || value.isEmpty) {
      await _prefs.remove(AppConstants.prefAuthToken);
    } else {
      await _prefs.setString(AppConstants.prefAuthToken, value);
    }
  }
}

/// Токен в памяти (unit-тесты).
class MemoryTokenStore implements TokenStore {
  /// Создание хранилища с необязательным начальным токеном.
  MemoryTokenStore([this._token]);

  String? _token;

  @override
  String? get token => _token;

  @override
  Future<void> save(String? value) async => _token = value;
}

/// HTTP-клиент backend API (КР_2_2, раздел 6 контракта).
///
/// Возможности:
/// - GET/POST/PUT/PATCH/DELETE;
/// - заголовок `Authorization: Bearer <token>`;
/// - таймаут 10 секунд ([AppConfig.apiTimeout] передаётся снаружи);
/// - разбор успешного ответа `{"data": ...}` и ошибки `{"error": ...}`;
/// - все сбои приводятся к [ApiException] с русским сообщением.
///
/// 401 при наличии токена и 403 `user_blocked` дополнительно вызывают
/// колбэки [onUnauthorized]/[onUserBlocked] — приложение завершает сессию
/// и уводит пользователя на экран входа.
class ApiClient {
  /// Клиент поверх базового URL и хранилища токена.
  ApiClient({
    required this.baseUrl,
    required this._tokenStore,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client();

  /// Базовый URL с префиксом `/api` (без завершающего слэша).
  final String baseUrl;

  /// Таймаут одного запроса.
  final Duration timeout;

  final TokenStore _tokenStore;
  final http.Client _client;

  /// Вызывается при 401, если запрос был с токеном (сессия истекла).
  void Function()? onUnauthorized;

  /// Вызывается при 403 с кодом `user_blocked`.
  void Function()? onUserBlocked;

  /// GET-запрос. [query] — необязательные параметры строки запроса.
  Future<Object?> get(String path, {Map<String, String?>? query}) =>
      _send('GET', path, query: query);

  /// POST-запрос с JSON-телом.
  Future<Object?> post(String path, {Object? body}) =>
      _send('POST', path, body: body);

  /// PUT-запрос с JSON-телом.
  Future<Object?> put(String path, {Object? body}) =>
      _send('PUT', path, body: body);

  /// PATCH-запрос с JSON-телом.
  Future<Object?> patch(String path, {Object? body}) =>
      _send('PATCH', path, body: body);

  /// DELETE-запрос (тело не передаётся).
  Future<Object?> delete(String path) => _send('DELETE', path);

  /// Единая отправка запроса и разбор ответа.
  Future<Object?> _send(
    String method,
    String path, {
    Map<String, String?>? query,
    Object? body,
  }) async {
    final token = _tokenStore.token;
    final headers = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json; charset=utf-8',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };

    var uri = Uri.parse('$baseUrl$path');
    if (query != null && query.isNotEmpty) {
      final params = <String, String>{
        for (final entry in query.entries)
          if (entry.value != null && entry.value!.isNotEmpty)
            entry.key: entry.value!,
      };
      if (params.isNotEmpty) uri = uri.replace(queryParameters: params);
    }

    final request = http.Request(method, uri)..headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);

    http.Response response;
    try {
      response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout);
    } on TimeoutException {
      throw ApiException.timeout();
    } on SocketException {
      throw ApiException.network();
    } on http.ClientException {
      throw ApiException.network();
    } on HandshakeException {
      throw ApiException.network();
    }

    return _parseResponse(response, token: token);
  }

  /// Разбор HTTP-ответа: `data` для 2xx и [ApiException] для остальных.
  Object? _parseResponse(http.Response response, {String? token}) {
    final status = response.statusCode;

    // 204 No Content — успех без тела (logout, delete).
    if (status == 204 || response.body.trim().isEmpty) {
      if (status >= 200 && status < 300) return null;
      throw ApiException.fromResponse(status, null);
    }

    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      if (status >= 200 && status < 300) throw ApiException.parse();
      throw ApiException.fromResponse(status, null);
    }

    if (status >= 200 && status < 300) {
      // Контракт: успешный ответ — объект/массив в поле `data`.
      if (decoded is Map<String, dynamic> && decoded.containsKey('data')) {
        return decoded['data'];
      }
      return decoded;
    }

    // Ошибка: `{"error": {...}}`; при отсутствии обёртки пробуем весь JSON.
    final error =
        decoded is Map<String, dynamic> && decoded.containsKey('error')
        ? decoded['error']
        : decoded;
    final exception = ApiException.fromResponse(status, error);

    final hadToken = token != null && token.isNotEmpty;
    if (exception.isUnauthorized && hadToken) {
      onUnauthorized?.call();
    } else if (exception.isUserBlocked && hadToken) {
      onUserBlocked?.call();
    }
    throw exception;
  }
}
