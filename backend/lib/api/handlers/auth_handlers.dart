import 'package:shelf/shelf.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/auth.dart';
import '../../core/errors.dart';
import '../../core/http_utils.dart';
import '../../core/validation.dart';
import '../../models/user.dart';

/// Обработчики авторизации и профиля.
class AuthHandlers {
  AuthHandlers(this.db, this.auth);

  /// Открытая БД.
  final Database db;

  /// Сервис авторизации.
  final AuthService auth;

  /// `POST /api/auth/register` — регистрация пользователя.
  Future<Response> register(Request request) async {
    final body = await readJsonBody(request);
    final validator = FormValidator();
    validator.check(validateUsername(body['username']), 'username');
    validator.check(validateEmail(body['email']), 'email');
    validator.check(validatePassword(body['password']), 'password');
    if (validator.hasErrors) validator.fail();

    final username = (body['username']! as String).trim();
    final email = (body['email']! as String).trim();
    final password = body['password']! as String;

    final conflicts = <String, String>{};
    if (await auth.findUserByField('username', username) != null) {
      conflicts['username'] = 'Такое имя пользователя уже занято';
    }
    if (await auth.findUserByField('email', email) != null) {
      conflicts['email'] = 'Такая почта уже зарегистрирована';
    }
    if (conflicts.isNotEmpty) {
      throw ApiError.conflict(
        'Имя пользователя или почта уже заняты',
        fields: conflicts,
      );
    }

    final salt = AuthService.generateSalt();
    final createdAt = DateTime.now().toUtc().toIso8601String();
    late final int id;
    try {
      id = await db.insert('users', {
        'username': username,
        'email': email,
        'password_hash': AuthService.hashPassword(password, salt),
        'salt': salt,
        'role': 'user',
        'is_blocked': 0,
        'avatar_color': pickAvatarColor(username),
        'created_at': createdAt,
      });
    } on Exception catch (error) {
      if (_isUniqueViolation(error)) {
        throw ApiError.conflict('Имя пользователя или почта уже заняты');
      }
      rethrow;
    }

    final token = await auth.createSession(id);
    final user = await auth.findUserById(id);
    return jsonResponse({
      'token': token,
      'user': userToJson(user!),
    }, status: 201);
  }

  /// `POST /api/auth/login` — вход по username или email.
  Future<Response> login(Request request) async {
    final body = await readJsonBody(request);
    final validator = FormValidator();
    final login = stringValue(body['login']);
    final password = body['password'];
    if (login == null || login.isEmpty) {
      validator.add('login', 'Укажите имя пользователя или почту');
    }
    if (password is! String || password.isEmpty) {
      validator.add('password', 'Укажите пароль');
    }
    if (validator.hasErrors) validator.fail();

    final user = await auth.findUserByLogin(login!);
    if (user == null ||
        !AuthService.verifyPassword(
          password as String,
          user['salt']! as String,
          user['password_hash']! as String,
        )) {
      throw ApiError.unauthorized('Неверный логин или пароль');
    }
    if ((user['is_blocked']! as int) != 0) {
      throw ApiError.forbidden('user_blocked', 'Учётная запись заблокирована');
    }

    final token = await auth.createSession(user['id']! as int);
    return jsonResponse({'token': token, 'user': userToJson(user)});
  }

  /// `POST /api/auth/logout` — удаление текущего токена.
  Future<Response> logout(Request request) async {
    final context = await auth.authenticate(request);
    await db.delete('sessions', where: 'token = ?', whereArgs: [context.token]);
    return emptyResponse();
  }

  /// `GET /api/auth/me` — текущий пользователь.
  Future<Response> me(Request request) async {
    final context = await auth.authenticate(request);
    return jsonResponse(userToJson(context.user));
  }

  /// `PUT /api/profile` — изменение имени, почты и цвета аватара.
  Future<Response> updateProfile(Request request) async {
    final context = await auth.authenticate(request);
    final body = await readJsonBody(request);
    final validator = FormValidator();

    String? username;
    String? email;
    String? avatarColor;

    if (body.containsKey('username')) {
      validator.check(validateUsername(body['username']), 'username');
      username = stringValue(body['username']);
    }
    if (body.containsKey('email')) {
      validator.check(validateEmail(body['email']), 'email');
      email = stringValue(body['email']);
    }
    if (body.containsKey('avatar_color')) {
      validator.check(
        validateAvatarColor(body['avatar_color']),
        'avatar_color',
      );
      avatarColor = stringValue(body['avatar_color']);
    }
    if (validator.hasErrors) validator.fail();

    final conflicts = <String, String>{};
    if (username != null) {
      final existing = await auth.findUserByField('username', username);
      if (existing != null && existing['id'] != context.userId) {
        conflicts['username'] = 'Такое имя пользователя уже занято';
      }
    }
    if (email != null) {
      final existing = await auth.findUserByField('email', email);
      if (existing != null && existing['id'] != context.userId) {
        conflicts['email'] = 'Такая почта уже зарегистрирована';
      }
    }
    if (conflicts.isNotEmpty) {
      throw ApiError.conflict(
        'Имя пользователя или почта уже заняты',
        fields: conflicts,
      );
    }

    final updates = <String, Object?>{
      if (username != null) 'username': username,
      if (email != null) 'email': email,
      if (avatarColor != null) 'avatar_color': avatarColor,
    };
    if (updates.isNotEmpty) {
      try {
        await db.update(
          'users',
          updates,
          where: 'id = ?',
          whereArgs: [context.userId],
        );
      } on Exception catch (error) {
        if (_isUniqueViolation(error)) {
          throw ApiError.conflict('Имя пользователя или почта уже заняты');
        }
        rethrow;
      }
    }

    final updated = await auth.findUserById(context.userId);
    return jsonResponse(userToJson(updated!));
  }

  /// `PUT /api/profile/password` — смена пароля.
  Future<Response> changePassword(Request request) async {
    final context = await auth.authenticate(request);
    final body = await readJsonBody(request);
    final validator = FormValidator();
    final oldPassword = body['old_password'];
    final newPassword = body['new_password'];
    if (oldPassword is! String || oldPassword.isEmpty) {
      validator.add('old_password', 'Укажите текущий пароль');
    }
    validator.check(validatePassword(newPassword), 'new_password');
    if (validator.hasErrors) validator.fail();

    final user = context.user;
    if (!AuthService.verifyPassword(
      oldPassword as String,
      user['salt']! as String,
      user['password_hash']! as String,
    )) {
      throw ApiError.validation(
        'Текущий пароль указан неверно',
        fields: {'old_password': 'Текущий пароль указан неверно'},
      );
    }

    final salt = AuthService.generateSalt();
    await db.update(
      'users',
      {
        'salt': salt,
        'password_hash': AuthService.hashPassword(newPassword as String, salt),
      },
      where: 'id = ?',
      whereArgs: [context.userId],
    );
    return jsonResponse({'changed': true});
  }

  bool _isUniqueViolation(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('unique') || text.contains('constraint');
  }
}
