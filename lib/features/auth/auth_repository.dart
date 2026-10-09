import 'package:flutter/foundation.dart' show immutable;
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/db/app_database.dart';
import '../../core/utils/hash_utils.dart';
import 'user_model.dart';

/// Понятная ошибка авторизации/регистрации для UI (русский текст).
///
/// [field] указывает на поле формы, к которому относится ошибка
/// (например, «имя пользователя занято») — экран подсвечивает его inline.
@immutable
class AuthException implements Exception {
  /// Ошибка с русским сообщением и (опционально) привязкой к полю формы.
  const AuthException(this.message, {this.field});

  /// Русское сообщение для пользователя.
  final String message;

  /// Поле формы, к которому относится ошибка (null — общая ошибка).
  final AuthField? field;
}

/// Поле формы, к которому привязана ошибка.
enum AuthField { username, email }

/// Репозиторий пользователей: регистрация, вход, восстановление сессии,
/// выход. Все SQL-запросы — параметризованные (`?` + whereArgs).
///
/// Данные пароля: хранится ТОЛЬКО солёный sha256 (hash + salt); открытый
/// пароль нигде не сохраняется и не логируется.
class AuthRepository {
  /// Репозиторий поверх открытой БД и prefs (сессия в `session_user_id`).
  const AuthRepository({required this.db, required this.prefs});

  /// Открытая база (AppDatabase.instance.open()).
  final Database db;

  /// prefs — ключ `session_user_id` (сессия, не БД).
  final SharedPreferences prefs;

  /// Палитра цветов аватара (хранится hex-строкой).
  static const List<String> _avatarPalette = [
    '#2AA79B', // фирменный бирюзовый
    '#4D8BF5', // синий
    '#E0A83F', // янтарный
    '#D16A8A', // розовый
    '#8C6FF0', // фиолетовый
    '#5FA85D', // зелёный
  ];

  /// Регистрация нового пользователя: соль + солёный sha256 + INSERT.
  ///
  /// Дубликаты username/email (без учёта регистра) маппятся в
  /// [AuthException] с русским сообщением и привязкой к полю формы.
  Future<UserModel> register({
    required String username,
    required String email,
    required String password,
  }) async {
    // Проверка уникальности без учёта регистра: COLLATE NOCASE в SQLite
    // работает только для ASCII, кириллицу сравниваем сами (в нижнем регистре).
    await _assertUnique(username, email);

    final salt = HashUtils.generateSalt();
    final hash = HashUtils.hashPassword(password, salt);
    final createdAt = DateTime.now().toIso8601String();
    final avatarColor = _pickAvatarColor(username);

    final id = await _insertUser(
      username: username,
      email: email,
      hash: hash,
      salt: salt,
      avatarColor: avatarColor,
      createdAt: createdAt,
    );
    return UserModel(
      id: id,
      username: username.trim(),
      email: email.trim(),
      avatarColor: avatarColor,
      createdAt: DateTime.parse(createdAt),
    );
  }

  /// Вход по имени пользователя ИЛИ email (+ проверка пароля).
  ///
  /// При несуществующем пользователе или неверном пароле —
  /// [AuthException] «Неверный логин или пароль» (без раскрытия деталей).
  Future<UserModel> login({
    required String loginOrEmail,
    required String password,
  }) async {
    // Параметризованный запрос: username/email совпадение без учёта регистра.
    final rows = await db.query(
      AppConstants.tableUsers,
      where: 'username = ? COLLATE NOCASE OR email = ? COLLATE NOCASE',
      whereArgs: [loginOrEmail, loginOrEmail],
    );

    // КИ: если SQL-дубль не найден (например, кириллица, которую NOCASE
    // не различает) — досматриваем в Дарте без учёта регистра.
    var row = rows.isEmpty ? null : rows.first;
    if (row == null) {
      final all = await db.query(AppConstants.tableUsers);
      final key = loginOrEmail.trim().toLowerCase();
      for (final candidate in all) {
        if ((candidate['username'] as String).toLowerCase() == key ||
            (candidate['email'] as String).toLowerCase() == key) {
          row = candidate;
          break;
        }
      }
    }

    if (row == null) {
      throw const AuthException('Неверный логин или пароль');
    }

    final hash = row['password_hash'] as String;
    final salt = row['salt'] as String;
    final ok = HashUtils.verifyPassword(password, salt, hash);
    if (!ok) {
      throw const AuthException('Неверный логин или пароль');
    }
    return UserModel.fromMap(row);
  }

  /// Восстановление сессии: пользователь по id (или null, если записи нет).
  Future<UserModel?> getUserById(int id) async {
    final rows = await db.query(
      AppConstants.tableUsers,
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : UserModel.fromMap(rows.first);
  }

  /// Сохранить id пользователя в сессии (prefs).
  Future<void> saveSession(int id) async {
    await prefs.setInt(AppConstants.prefSessionUserId, id);
  }

  /// Id пользователя из сессии (null — сессии нет).
  int? get sessionId => prefs.getInt(AppConstants.prefSessionUserId);

  /// Выход: очищает ключ сессии в prefs и НИЧЕГО не удаляет из БД
  /// (все пользовательские данные — favorites / history / snippets — остаются).
  Future<void> logout() async {
    await prefs.remove(AppConstants.prefSessionUserId);
  }

  // --- Внутренние методы ---

  /// Проверка уникальности username/email без учёта регистра (в т.ч.
  /// кириллицы): читаем таблицу (она локальная и небольшая) и сравниваем
  /// в Дарте. UNIQUE COLLATE NOCASE в схеме остаётся страховкой.
  Future<void> _assertUnique(String username, String email) async {
    final rows = await db.query(
      AppConstants.tableUsers,
      columns: const ['username', 'email'],
    );
    final usernameKey = username.trim().toLowerCase();
    final emailKey = email.trim().toLowerCase();
    for (final row in rows) {
      if ((row['username'] as String).toLowerCase() == usernameKey) {
        throw const AuthException(
          'Имя пользователя уже занято',
          field: AuthField.username,
        );
      }
      if ((row['email'] as String).toLowerCase() == emailKey) {
        throw const AuthException(
          'Email уже зарегистрирован',
          field: AuthField.email,
        );
      }
    }
  }

  /// INSERT пользователя; UNIQUE-нарушение (страховка) → [AuthException].
  Future<int> _insertUser({
    required String username,
    required String email,
    required String hash,
    required String salt,
    required String avatarColor,
    required String createdAt,
  }) async {
    try {
      return await db.insert(AppDbTables.users, {
        'username': username.trim(),
        'email': email.trim(),
        'password_hash': hash,
        'salt': salt,
        'avatar_color': avatarColor,
        'created_at': createdAt,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
    } on DatabaseException catch (e) {
      // Подстраховка: дубликат по UNIQUE-индексу (гонка или изменение
      // регистра): маппим в понятную ошибку поля формы.
      final text = e.toString();
      if (text.contains('${AppDbTables.users}.username')) {
        throw const AuthException(
          'Имя пользователя уже занято',
          field: AuthField.username,
        );
      }
      if (text.contains('${AppDbTables.users}.email')) {
        throw const AuthException(
          'Email уже зарегистрирован',
          field: AuthField.email,
        );
      }
      rethrow;
    }
  }

  /// Выбор цвета аватара: детерминированно по имени (хэш по кодам символов,
  /// т.к. String.hashCode не стабилен между запусками).
  static String _pickAvatarColor(String username) {
    final palette = _avatarPalette;
    var sum = 0;
    for (final rune in username.runes) {
      sum += rune;
    }
    return palette[sum % palette.length];
  }
}
