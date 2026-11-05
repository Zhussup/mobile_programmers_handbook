import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';
import '../../core/models/admin_user.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/json_utils.dart';

/// Состояние авторизации администратора.
///
/// Токен хранится в `shared_preferences`, сессия восстанавливается через
/// `GET /auth/me`. При 401 клиент вызывает [forceLogout], и роутер уводит
/// пользователя на `/login`.
class AuthProvider extends ChangeNotifier {
  AuthProvider(this._api, this._prefs) {
    _api.onUnauthorized = forceLogout;
  }

  final ApiClient _api;
  final SharedPreferences _prefs;

  AdminUser? _user;
  bool _initialized = false;
  bool _loading = false;
  String? _errorMessage;

  AdminUser? get user => _user;
  bool get initialized => _initialized;
  bool get loading => _loading;
  String? get errorMessage => _errorMessage;
  int? get currentUserId => _user?.id;

  bool get isAuthenticated => _user != null && _api.token != null;

  /// Восстанавливает сессию по сохранённому токену.
  Future<void> restoreSession() async {
    final savedToken = _prefs.getString(AppConfig.tokenKey);
    if (savedToken == null || savedToken.isEmpty) {
      _initialized = true;
      notifyListeners();
      return;
    }

    _api.token = savedToken;
    try {
      final data = await _api.get('/auth/me');
      final restored = AdminUser.fromJson(data);
      if (!restored.isAdmin) {
        await _clearLocalSession();
        _errorMessage = 'Доступ только для администратора';
      } else {
        _user = restored;
      }
    } on ApiException catch (error) {
      if (error.kind == ApiErrorKind.unauthorized) {
        await _clearLocalSession();
        _errorMessage = 'Сессия истекла. Войдите снова.';
      } else {
        _errorMessage = error.message;
      }
    } finally {
      _initialized = true;
      notifyListeners();
    }
  }

  /// Вход администратора. Возвращает `true` при успехе.
  Future<bool> login(String login, String password) async {
    _loading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final data = await _api.post(
        '/auth/login',
        body: <String, dynamic>{'login': login.trim(), 'password': password},
      );
      final map = asJsonMap(data);
      final token = asString(map['token']);
      final parsedUser = map['user'];
      if (token.isEmpty || parsedUser == null) {
        _errorMessage = 'Сервер вернул некорректный ответ.';
        return false;
      }

      final candidate = AdminUser.fromJson(parsedUser);
      if (!candidate.isAdmin) {
        // Не даём сессии не-администратора попасть в панель.
        _api.token = token;
        try {
          await _api.post('/auth/logout');
        } on ApiException {
          // Игнорируем: локальная сессия всё равно не сохраняется.
        }
        _api.token = null;
        _errorMessage = 'Доступ только для администратора';
        return false;
      }

      _api.token = token;
      await _prefs.setString(AppConfig.tokenKey, token);
      _user = candidate;
      _errorMessage = null;
      return true;
    } on ApiException catch (error) {
      _errorMessage = error.message;
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Выход: пытаемся удалить токен на сервере и всегда чистим локально.
  Future<void> logout() async {
    if (_api.token != null) {
      try {
        await _api.post('/auth/logout');
      } on ApiException {
        // Сервер может быть недоступен — локальный выход всё равно нужен.
      }
    }
    await _clearLocalSession();
    _errorMessage = null;
    notifyListeners();
  }

  /// Принудительный выход по истёкшему/недействительному токену (401).
  Future<void> forceLogout() async {
    if (_user == null && _api.token == null) return;
    await _clearLocalSession();
    _errorMessage = 'Сессия истекла. Войдите снова.';
    notifyListeners();
  }

  /// Обновляет данные текущего пользователя после редактирования профиля.
  void updateCurrentUser(AdminUser updated) {
    if (_user == null || _user!.id != updated.id) return;
    _user = updated;
    notifyListeners();
  }

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> _clearLocalSession() async {
    _user = null;
    _api.token = null;
    await _prefs.remove(AppConfig.tokenKey);
  }
}
