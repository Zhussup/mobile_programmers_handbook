import 'user_model.dart';

/// Общий контракт репозитория авторизации.
///
/// Реализации: локальная [AuthRepository] (sqflite, режим тестов/офлайна) и
/// [RemoteAuthRepository] (backend API, КР_2_2). Провайдеры работают через
/// этот интерфейс и не знают, откуда пришли данные.
abstract class AuthRepositoryBase {
  /// Регистрация нового пользователя.
  Future<UserModel> register({
    required String username,
    required String email,
    required String password,
  });

  /// Вход по логину/email + паролю.
  Future<UserModel> login({
    required String loginOrEmail,
    required String password,
  });

  /// Пользователь по сохранённой сессии (null — сессии/пользователя нет).
  ///
  /// Локально — строка БД по id; удалённо — `GET /auth/me` по токену.
  Future<UserModel?> getUserById(int id);

  /// Сохранить сессию после входа/регистрации.
  Future<void> saveSession(int id);

  /// Признак наличия сохранённой сессии (id в prefs / токен).
  int? get sessionId;

  /// Выход (удаление локальной сессии; удалённо — ещё и токена на сервере).
  Future<void> logout();

  /// Локальная очистка сессии без обращения к серверу (401/403 user_blocked).
  Future<void> clearSession();
}
