import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'errors.dart';

/// Контекст авторизованного запроса: действующий токен и строка пользователя.
class AuthContext {
  const AuthContext({required this.token, required this.user});

  /// Токен из заголовка `Authorization: Bearer ...`.
  final String token;

  /// Свежая строка таблицы `users`.
  final Map<String, Object?> user;

  /// Идентификатор пользователя.
  int get userId => user['id']! as int;

  /// Роль (`admin` или `user`).
  String get role => user['role']! as String;

  /// Является ли пользователь администратором.
  bool get isAdmin => role == 'admin';
}

/// Работа с паролями, токенами и проверкой Bearer-заголовка.
///
/// Пароль хранится как солёный SHA-256 (16 байт соли + 32 байта токена),
/// как и в локальной версии приложения. Для учебного проекта этого
/// достаточно; для продакшена следует использовать bcrypt/argon2.
class AuthService {
  /// Сервис поверх открытой базы.
  AuthService(this.db);

  /// Открытая SQLite-база.
  final Database db;

  /// Срок жизни сессии в днях.
  static const int sessionDurationDays = 30;

  /// Длина соли в байтах.
  static const int saltLengthBytes = 16;

  /// Длина токена в байтах.
  static const int tokenLengthBytes = 32;

  /// Случайная соль в hex (32 символа).
  static String generateSalt() => _randomHex(saltLengthBytes);

  /// Случайный токен в hex (64 символа).
  static String generateToken() => _randomHex(tokenLengthBytes);

  /// Солёный SHA-256: `sha256(пароль + соль)` в hex.
  static String hashPassword(String password, String salt) {
    return sha256.convert(_utf8Bytes('$password$salt')).toString();
  }

  /// Проверка пароля по сохранённым соли и хэшу.
  static bool verifyPassword(
    String password,
    String salt,
    String expectedHash,
  ) {
    return hashPassword(password, salt) == expectedHash;
  }

  /// Создание сессии и возврат нового токена.
  Future<String> createSession(int userId) async {
    final token = generateToken();
    final now = DateTime.now().toUtc();
    final expiresAt = now.add(const Duration(days: sessionDurationDays));
    await db.insert('sessions', {
      'token': token,
      'user_id': userId,
      'created_at': now.toIso8601String(),
      'expires_at': expiresAt.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return token;
  }

  /// Проверка Bearer-токена. Возвращает контекст или выбрасывает [ApiError].
  ///
  /// [adminOnly] дополнительно требует роль `admin`.
  Future<AuthContext> authenticate(
    Request request, {
    bool adminOnly = false,
  }) async {
    final header = request.headers['authorization'];
    if (header == null) {
      throw ApiError.unauthorized();
    }
    final trimmed = header.trim();
    if (!trimmed.toLowerCase().startsWith('bearer ')) {
      throw ApiError.unauthorized();
    }
    final token = trimmed.substring(7).trim();
    if (token.isEmpty) {
      throw ApiError.unauthorized();
    }

    final sessions = await db.query(
      'sessions',
      where: 'token = ?',
      whereArgs: [token],
      limit: 1,
    );
    if (sessions.isEmpty) {
      throw ApiError.unauthorized();
    }

    final session = sessions.first;
    final expiresAt = DateTime.tryParse(session['expires_at']! as String);
    if (expiresAt == null || !expiresAt.isAfter(DateTime.now().toUtc())) {
      await db.delete('sessions', where: 'token = ?', whereArgs: [token]);
      throw ApiError.unauthorized('Срок действия токена истёк');
    }

    final user = await findUserById(session['user_id']! as int);
    if (user == null) {
      await db.delete('sessions', where: 'token = ?', whereArgs: [token]);
      throw ApiError.unauthorized();
    }
    if ((user['is_blocked']! as int) != 0) {
      // Заблокированный пользователь не должен пользоваться старым токеном.
      await db.delete(
        'sessions',
        where: 'user_id = ?',
        whereArgs: [user['id']],
      );
      throw ApiError.forbidden('user_blocked', 'Учётная запись заблокирована');
    }
    if (adminOnly && user['role'] != 'admin') {
      throw ApiError.forbidden();
    }

    return AuthContext(token: token, user: user);
  }

  /// Пользователь по идентификатору.
  Future<Map<String, Object?>?> findUserById(int id) async {
    final rows = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// Пользователь по username или email без учёта регистра.
  ///
  /// Сравнение выполняется в Dart: `COLLATE NOCASE` в SQLite не различает
  /// регистр кириллицы.
  Future<Map<String, Object?>?> findUserByLogin(String login) async {
    final key = login.trim().toLowerCase();
    if (key.isEmpty) return null;
    final rows = await db.query('users');
    for (final row in rows) {
      final username = (row['username']! as String).toLowerCase();
      final email = (row['email']! as String).toLowerCase();
      if (username == key || email == key) return row;
    }
    return null;
  }

  /// Пользователь по значению поля `username` или `email` (без регистра).
  Future<Map<String, Object?>?> findUserByField(
    String field,
    String value,
  ) async {
    final key = value.trim().toLowerCase();
    if (key.isEmpty) return null;
    final rows = await db.query(
      'users',
      where: '$field = ? COLLATE NOCASE',
      whereArgs: [value.trim()],
    );
    if (rows.isNotEmpty) return rows.first;
    // Досмотр кириллицы, которую NOCASE не различает.
    final all = await db.query('users');
    for (final row in all) {
      if ((row[field]! as String).toLowerCase() == key) return row;
    }
    return null;
  }

  static List<int> _utf8Bytes(String value) => utf8.encode(value);

  static String _randomHex(int length) {
    final random = Random.secure();
    final bytes = List<int>.generate(length, (_) => random.nextInt(256));
    const digits = '0123456789abcdef';
    final buffer = StringBuffer();
    for (final byte in bytes) {
      buffer.write(digits[(byte >> 4) & 0xF]);
      buffer.write(digits[byte & 0xF]);
    }
    return buffer.toString();
  }
}
