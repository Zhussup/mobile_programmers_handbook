import 'package:sqflite/sqflite.dart';

import '../constants/app_constants.dart';

/// Какое поле занято другим пользователем (проверка уникальности).
enum UserFieldConflict { username, email }

/// Проверка уникальности username/email (общий хелпер AuthRepository и
/// ProfileRepository, P11 — по правилам подводного камня из плана).
///
/// COLLATE NOCASE в схеме различает регистр только для ASCII: для
/// кириллических имён сравнение без учёта регистра выполняется вручную
/// в Дарте (таблица users локальная и небольшая — читаем её целиком).
class UserUniqueness {
  UserUniqueness._();

  /// Какие поля заняты (без учёта регистра, включая кириллицу).
  ///
  /// [excludeUserId] — id текущего пользователя при изменении профиля:
  /// его собственные username/email не считаются конфликтом. Пустой набор —
  /// значения свободны.
  static Future<Set<UserFieldConflict>> findConflicts(
    Database db, {
    required String username,
    required String email,
    int? excludeUserId,
  }) async {
    final rows = await db.query(
      AppConstants.tableUsers,
      columns: const ['id', 'username', 'email'],
    );
    final usernameKey = username.trim().toLowerCase();
    final emailKey = email.trim().toLowerCase();
    final result = <UserFieldConflict>{};
    for (final row in rows) {
      if (excludeUserId != null && (row['id']! as int) == excludeUserId) {
        continue;
      }
      if ((row['username']! as String).toLowerCase() == usernameKey) {
        result.add(UserFieldConflict.username);
      }
      if ((row['email']! as String).toLowerCase() == emailKey) {
        result.add(UserFieldConflict.email);
      }
    }
    return result;
  }
}
