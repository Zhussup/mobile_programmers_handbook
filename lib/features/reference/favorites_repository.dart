import 'package:flutter/foundation.dart' show immutable;
import 'package:sqflite/sqflite.dart';

import '../../core/constants/app_constants.dart';
import '../../core/db/app_database.dart';

/// Строка таблицы favorites: id статьи + время добавления.
///
/// Детали статей (title/summary/difficulty) НЕ в БД — контент справочника
/// иммутабелен и живёт в JSON-ассетах; репозиторий возвращает только
/// ключи, «сшивает» с контентом провайдер (join по articleId).
@immutable
class FavoriteRecord {
  const FavoriteRecord({required this.articleId, required this.createdAt});

  /// Строковый id статьи из JSON-контента.
  final String articleId;

  /// Когда статья добавлена в избранное.
  final DateTime createdAt;

  /// Разбор строки таблицы favorites в модель.
  factory FavoriteRecord.fromMap(Map<String, Object?> row) {
    return FavoriteRecord(
      articleId: row['article_id']! as String,
      createdAt: DateTime.parse(row['created_at']! as String),
    );
  }
}

/// Репозиторий избранного (P9): таблица `favorites` (PK user_id+article_id).
///
/// Все запросы — с `WHERE user_id = ?` (изоляция мультиюзера: данные одного
/// пользователя не видны другому, logout ничего не удаляет); SQL-запросы
/// строго параметризованные, имена таблиц — константы [AppDbTables].
class FavoritesRepository {
  /// Репозиторий поверх открытой БД ([AppDatabase.instance]).
  const FavoritesRepository({required this.db});

  /// Открытая база.
  final Database db;

  /// В избранном ли статья у пользователя.
  Future<bool> isFavorite(int userId, String articleId) async {
    final rows = await db.query(
      AppConstants.tableFavorites,
      where: 'user_id = ? AND article_id = ?',
      whereArgs: [userId, articleId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Переключение статьи в избранном.
  ///
  /// Идемпотентен (PK user_id+article_id): повторное добавление не
  /// дублирует строку (INSERT с replace-конфликтом), повторное удаление —
  /// no-op. Возвращает состояние ПОСЛЕ переключения: true — добавлено,
  /// false — удалено.
  Future<bool> toggle(int userId, String articleId) async {
    final wasFavorite = await isFavorite(userId, articleId);
    if (wasFavorite) {
      await db.delete(
        AppConstants.tableFavorites,
        where: 'user_id = ? AND article_id = ?',
        whereArgs: [userId, articleId],
      );
      return false;
    }
    await db.insert(AppConstants.tableFavorites, {
      'user_id': userId,
      'article_id': articleId,
      'created_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return true;
  }

  /// Список избранного пользователя: свежие раньше.
  Future<List<FavoriteRecord>> listForUser(int userId) async {
    final rows = await db.query(
      AppConstants.tableFavorites,
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
    );
    return [for (final row in rows) FavoriteRecord.fromMap(row)];
  }
}
