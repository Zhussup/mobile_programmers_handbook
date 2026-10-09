import 'package:flutter/foundation.dart' show ChangeNotifier, immutable;

import 'auth_repository.dart';
import 'user_model.dart';

/// Статус авторизации (для redirect-guard).
enum AuthStatus {
  /// Сеанс ещё не восстановлен (restoreSession не вызван).
  unknown,

  /// Пользователь не вошёл.
  guest,

  /// Пользователь вошёл.
  authorized,
}

/// Состояние авторизации: статус + текущий пользователь.
///
/// Redirect-guard — чистая функция от (Location, AuthState) — см. план.
@immutable
class AuthState {
  /// Состояние с переданным статусом и пользователем.
  const AuthState({required this.status, this.user});

  /// Гость (нет пользователя).
  const AuthState.guest() : this(status: AuthStatus.guest);

  /// Вошедший пользователь.
  const AuthState.authorized(this.user) : status = AuthStatus.authorized;

  /// Текущий пользователь (null, кроме статуса authorized).
  final UserModel? user;

  /// Статус авторизации.
  final AuthStatus status;

  /// Вошёл ли пользователь.
  bool get isAuthorized => status == AuthStatus.authorized;

  /// Равенство по полям (для чистой функции redirect и тестов).
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AuthState && other.status == status && other.user == user;
  }

  @override
  int get hashCode => Object.hash(status, user);
}

/// Сессия пользователя: состояние входа + persist в shared_preferences
/// (ключ `session_user_id`).
///
/// Восстановление сессии ([restoreSession]) вызывается из main() ДО runApp —
/// иначе redirect-гонка и мигание (подводный камень №1 из плана).
class SessionProvider extends ChangeNotifier {
  /// Провайдер сессии поверх репозитория users.
  SessionProvider({required this.repository});

  /// Репозиторий users (sqflite).
  final AuthRepository repository;

  UserModel? _user;
  bool _initialized = false;

  /// Текущий пользователь (null — не вошёл).
  UserModel? get currentUser => _user;

  /// Восстановлена ли сессия при старте.
  bool get initialized => _initialized;

  /// Состояние авторизации (для redirect-guard).
  AuthState get state {
    if (!_initialized) return const AuthState(status: AuthStatus.unknown);
    return _user != null
        ? AuthState.authorized(_user!)
        : const AuthState.guest();
  }

  /// Восстановление сессии при старте (id из prefs → UserModel из БД).
  ///
  /// Если записи с таким id больше нет (например, снесён профиль) — сессия
  /// считается отсутствующей.
  Future<void> restoreSession() async {
    final id = repository.sessionId;
    if (id == null) {
      _user = null;
      _initialized = true;
      notifyListeners();
      return;
    }
    try {
      final user = await repository.getUserById(id);
      _user = user;
      // Записи в БД нет — сбрасываем «висящий» id в prefs.
      if (user == null) {
        await repository.logout();
      }
    } on Exception {
      // БД недоступна (маловероятно в бою): трактуем как гостя.
      _user = null;
    }
    _initialized = true;
    notifyListeners();
  }

  /// Регистрация: создаёт пользователя и сразу сохраняет сессию (вход).
  ///
  /// Бросает [AuthException] с русским сообщением (см. репозиторий).
  Future<UserModel> register({
    required String username,
    required String email,
    required String password,
  }) async {
    final user = await repository.register(
      username: username,
      email: email,
      password: password,
    );
    await repository.saveSession(user.id);
    _user = user;
    notifyListeners();
    return user;
  }

  /// Вход по логину/email + паролю: сессия сохраняется.
  ///
  /// Бросает [AuthException] «Неверный логин или пароль» при неудаче.
  Future<UserModel> login({
    required String loginOrEmail,
    required String password,
  }) async {
    final user = await repository.login(
      loginOrEmail: loginOrEmail,
      password: password,
    );
    await repository.saveSession(user.id);
    _user = user;
    notifyListeners();
    return user;
  }

  /// Выход: очистка сессии (prefs) через репозиторий; данные пользователя
  /// в БД не трогаются.
  Future<void> logout() async {
    await repository.logout();
    _user = null;
    notifyListeners();
  }
}
