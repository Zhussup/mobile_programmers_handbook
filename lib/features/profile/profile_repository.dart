import 'package:flutter/foundation.dart' show immutable;
import 'package:sqflite/sqflite.dart';

import '../../core/constants/app_constants.dart';
import '../../core/db/app_database.dart';
import '../../core/utils/hash_utils.dart';
import '../../core/utils/user_uniqueness.dart';
import '../auth/user_model.dart';

/// Русская ошибка изменяемого профиля для UI: сообщение + поле формы
/// (отличается от [AuthException] тем, что умеет ссылаться на старый
/// пароль). Русские сообщения — по контракту экранов.
@immutable
class ProfileException implements Exception {
  /// Ошибка с русским сообщением и полем формы (null — общая).
  const ProfileException(this.message, {this.field});

  /// Русское сообщение для пользователя.
  final String message;

  /// Поле формы, к которому относится ошибка (null — общая ошибка).
  final ProfileField? field;
}

/// Поле формы редактирования профиля, к которому привязана ошибка.
enum ProfileField { username, email, oldPassword }

/// Репозиторий профиля 2.0 (P11): изменение данных, смена пароля, цвет
/// аватара. Все SQL-запросы — параметризованные, таблица — `users`.
///
/// Уникальность username/email — общий хелпер [UserUniqueness] (NOCASE для
/// ASCII + ручная кириллица в Дарте), исключая самого пользователя.
class ProfileRepository {
  /// Репозиторий поверх открытой БД ([AppDatabase.instance]).
  const ProfileRepository({required this.db});

  /// Открытая база.
  final Database db;

  /// Изменение профиля (username и/или email). Поля не переданы —
  /// значения остаются прежними.
  ///
  /// Уникальность — без учёта регистра (в т.ч. кириллицы), свой же текущий
  /// профиль конфликтом НЕ считается ([UserUniqueness.findConflicts] с
  /// excludeUserId). Возвращает обновлённую [UserModel].
  Future<UserModel> updateProfile(
    int userId, {
    String? username,
    String? email,
  }) async {
    final values = <String, Object?>{};
    if (username != null) values['username'] = username.trim();
    if (email != null) values['email'] = email.trim();

    if (values.isNotEmpty) {
      // Текущая строка нужна и для проверки уникальности (исключить себя),
      // и для сборки обновлённой модели (created_at/цвет без изменений).
      final current = await getUserRow(userId);
      if (current == null) {
        throw const ProfileException('Пользователь не найден');
      }
      final conflicts = await UserUniqueness.findConflicts(
        db,
        username: username ?? current.username,
        email: email ?? current.email,
        excludeUserId: userId,
      );
      if (conflicts.contains(UserFieldConflict.username)) {
        throw const ProfileException(
          'Имя пользователя уже занято',
          field: ProfileField.username,
        );
      }
      if (conflicts.contains(UserFieldConflict.email)) {
        throw const ProfileException(
          'Email уже зарегистрирован',
          field: ProfileField.email,
        );
      }

      // UNIQUE-страховка (гонки) — как в AuthRepository._insertUser.
      try {
        await db.update(
          AppDbTables.users,
          values,
          where: 'id = ?',
          whereArgs: [userId],
        );
      } on DatabaseException catch (e) {
        // UNIQUE-страховка: дубликат по индексу (гонка) — понятная ошибка.
        final text = e.toString();
        if (text.contains('${AppDbTables.users}.username')) {
          throw const ProfileException(
            'Имя пользователя уже занято',
            field: ProfileField.username,
          );
        }
        if (text.contains('${AppDbTables.users}.email')) {
          throw const ProfileException(
            'Email уже зарегистрирован',
            field: ProfileField.email,
          );
        }
      }
    }

    final updated = await getUserRow(userId);
    if (updated == null) throw const ProfileException('Пользователь не найден');
    return updated;
  }

  /// Изменение цвета аватара (палитра из AppConstants.avatarPalette).
  /// Возвращает обновлённую [UserModel].
  Future<UserModel> updateAvatarColor(int userId, String colorHex) async {
    final rowsUpdated = await db.update(
      AppDbTables.users,
      {'avatar_color': colorHex},
      where: 'id = ?',
      whereArgs: [userId],
    );
    if (rowsUpdated == 0) {
      throw const ProfileException('Пользователь не найден');
    }
    final updated = await getUserRow(userId);
    if (updated == null) throw const ProfileException('Пользователь не найден');
    return updated;
  }

  /// Смена пароля: проверка СТАРОГО пароля, затем новый хэш + новая соль.
  ///
  /// Неверный старый пароль → [ProfileException] с полем
  /// [ProfileField.oldPassword] — экран подсвечивает поле inline.
  Future<void> changePassword({
    required int userId,
    required String oldPassword,
    required String newPassword,
  }) async {
    final row = await db.query(
      AppDbTables.users,
      columns: const ['password_hash', 'salt'],
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (row.isEmpty) {
      throw const ProfileException('Пользователь не найден');
    }
    final oldHash = row.first['password_hash']! as String;
    final salt = row.first['salt']! as String;
    final ok = HashUtils.verifyPassword(oldPassword, salt, oldHash);
    if (!ok) {
      throw const ProfileException(
        'Неверный старый пароль',
        field: ProfileField.oldPassword,
      );
    }
    final newSalt = HashUtils.generateSalt();
    await db.update(
      AppDbTables.users,
      {
        'password_hash': HashUtils.hashPassword(newPassword, newSalt),
        'salt': newSalt,
      },
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  /// Строка пользователя по id → [UserModel] (null — записи нет).
  Future<UserModel?> getUserRow(int userId) async {
    final rows = await db.query(
      AppConstants.tableUsers,
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    return rows.isEmpty ? null : UserModel.fromMap(rows.first);
  }
}
