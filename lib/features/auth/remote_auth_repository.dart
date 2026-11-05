import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import 'auth_repository.dart';
import 'auth_repository_base.dart';
import 'user_model.dart';

/// Удалённый репозиторий авторизации (КР_2_2, К10).
///
/// - `register`/`login` → `POST /auth/register` / `POST /auth/login`;
/// - `getUserById` → `GET /auth/me` (id в запросе не участвует — сервер
///   определяет пользователя по токену);
/// - токен хранится в shared_preferences под ключом `auth_token`;
/// - профиль кэшируется в shared_preferences (`auth_user`) — при отсутствии
///   сети сессия восстанавливается из последнего ответа `/auth/me`.
class RemoteAuthRepository implements AuthRepositoryBase {
  /// Репозиторий поверх API-клиента и prefs.
  RemoteAuthRepository({required this._apiClient, required this._prefs});

  final ApiClient _apiClient;
  final SharedPreferences _prefs;

  /// Id-заглушка: удалённая сессия определяется токеном, а не номером.
  ///
  /// Контракт [SessionProvider] проверяет только «есть ли сессия» и затем
  /// вызывает [getUserById] — сервер вернёт пользователя по токену.
  @override
  int? get sessionId {
    final token = _prefs.getString(AppConstants.prefAuthToken);
    return token == null || token.isEmpty ? null : 1;
  }

  @override
  Future<UserModel> register({
    required String username,
    required String email,
    required String password,
  }) async {
    try {
      final data = await _apiClient.post(
        '/auth/register',
        body: {
          'username': username.trim(),
          'email': email.trim(),
          'password': password,
        },
      );
      return await _acceptAuthPayload(data);
    } on ApiException catch (e) {
      throw _mapAuthError(e);
    }
  }

  @override
  Future<UserModel> login({
    required String loginOrEmail,
    required String password,
  }) async {
    try {
      final data = await _apiClient.post(
        '/auth/login',
        body: {'login': loginOrEmail.trim(), 'password': password},
      );
      return await _acceptAuthPayload(data);
    } on ApiException catch (e) {
      throw _mapAuthError(e, isLogin: true);
    }
  }

  @override
  Future<UserModel?> getUserById(int id) async {
    if (sessionId == null) return null;
    try {
      final data = await _apiClient.get('/auth/me');
      final user = _parseUser(data);
      await _saveCachedUser(user);
      return user;
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        await clearSession();
        return null;
      }
      if (e.isNetwork) {
        // Нет связи — используем последний профиль, если он сохранён.
        return _readCachedUser();
      }
      debugPrint('Профиль: /auth/me недоступен (${e.code})');
      return null;
    }
  }

  /// Токен сохраняется при register/login; отдельный id не нужен.
  @override
  Future<void> saveSession(int id) async {}

  @override
  Future<void> logout() async {
    // Серверный logout — best-effort: даже при ошибке локальная сессия
    // должна завершиться, иначе пользователь «застрянет» в приложении.
    try {
      await _apiClient.post('/auth/logout');
    } on ApiException catch (e) {
      debugPrint('Выход: сервер недоступен (${e.code})');
    } finally {
      await clearSession();
    }
  }

  @override
  Future<void> clearSession() async {
    await _prefs.remove(AppConstants.prefAuthToken);
    await _prefs.remove(AppConstants.prefAuthUser);
  }

  /// Разбор `{"token": "...", "user": {...}}`, сохранение токена и профиля.
  Future<UserModel> _acceptAuthPayload(Object? data) async {
    if (data is! Map) throw ApiException.parse();
    final map = Map<String, dynamic>.from(data);
    final token = map['token'];
    final userRaw = map['user'];
    if (token is! String || token.isEmpty || userRaw is! Map) {
      throw ApiException.parse();
    }
    final user = _parseUser(userRaw);
    await _prefs.setString(AppConstants.prefAuthToken, token);
    await _saveCachedUser(user);
    return user;
  }

  /// Пользователь из ответа API (принимает и `{user: {...}}`).
  UserModel _parseUser(Object? data) {
    Object? raw = data;
    if (data is Map && data['user'] is Map) raw = data['user'];
    if (raw is! Map) throw ApiException.parse();
    return UserModel.fromJson(Map<String, dynamic>.from(raw));
  }

  /// Кэш профиля для восстановления сессии при сетевой ошибке.
  Future<void> _saveCachedUser(UserModel user) async {
    try {
      await _prefs.setString(
        AppConstants.prefAuthUser,
        jsonEncode(user.toJson()),
      );
    } catch (e) {
      debugPrint('Профиль: не удалось сохранить кэш ($e)');
    }
  }

  /// Последний сохранённый профиль (null — кэша нет).
  UserModel? _readCachedUser() {
    final raw = _prefs.getString(AppConstants.prefAuthUser);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return UserModel.fromJson(Map<String, dynamic>.from(decoded));
      }
    } on FormatException {
      // Битый кэш — просто нет профиля.
    }
    return null;
  }

  /// Приведение [ApiException] к русской [AuthException] с полем формы.
  AuthException _mapAuthError(ApiException e, {bool isLogin = false}) {
    if (isLogin && e.isUnauthorized) {
      // Единая формулировка, не раскрывающая существование пользователя.
      return const AuthException('Неверный логин или пароль');
    }

    if (e.type == ApiErrorType.validation) {
      final username = e.fields['username'];
      if (username != null && username.isNotEmpty) {
        return AuthException(username, field: AuthField.username);
      }
      final email = e.fields['email'];
      if (email != null && email.isNotEmpty) {
        return AuthException(email, field: AuthField.email);
      }
    }

    if (e.type == ApiErrorType.conflict) {
      final lower = e.message.toLowerCase();
      if (lower.contains('email') || lower.contains('почт')) {
        return AuthException(e.message, field: AuthField.email);
      }
      if (lower.contains('имен') ||
          lower.contains('username') ||
          lower.contains('логин')) {
        return AuthException(e.message, field: AuthField.username);
      }
    }

    if (e.isUserBlocked) {
      return const AuthException(
        'Учётная запись заблокирована администратором.',
      );
    }
    return AuthException(e.message);
  }
}
