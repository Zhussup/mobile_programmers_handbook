import 'package:flutter/foundation.dart' show immutable;
import 'package:sqflite/sqflite.dart';

import '../../core/constants/app_constants.dart';
import '../../core/db/app_database.dart';

/// Строка таблицы history: id статьи, когда просмотрена (топ-20).
///
/// Детали статьи (title/summary) НЕ хранятся в БД — контент справочника
/// иммутабелен; «сшивает» с контентом провайдер (join по articleId).
@immutable
class HistoryRecordRaw {
  const HistoryRecordRaw({required this.articleId, required this.viewedAt});

  /// Строковый id статьи из JSON-контента.
  final String articleId;

  /// Когда статья открыта (в БД — строка ISO-8601).
  final DateTime viewedAt;

  factory HistoryRecordRaw.fromMap(Map<String, Object?> row) {
    return HistoryRecordRaw(
      articleId: row['article_id']! as String,
      viewedAt: DateTime.parse(row['viewed_at']! as String),
    );
  }
}

/// Репозиторий истории просмотров (P9): таблица `history`, индекс
/// (user_id, viewed_at), лимит топ-20 ([AppConstants.historyLimit]).
///
/// Все запросы — с `WHERE user_id = ?` (изоляция мультиюзера: данные
/// одного пользователя не видны другому, logout ничего не удаляет).
class HistoryRepository {
  /// Репозиторий поверх открытой БД ([AppDatabase.instance]).
  const HistoryRepository({required this.db});

  /// Открытая база.
  final Database db;

  /// Запись просмотра: одна строка на статью у пользователя — повторное
  /// открытие не плодит дубликаты, а обновляет «свежесть» (viewed_at).
  ///
  /// Вставка + подрезка до топ-20 одним батчем (атомарно): DELETE строк,
  /// не входящих в топ-20 по (user_id, viewed_at DESC, id DESC).
  Future<void> record(int userId, String articleId) async {
    final viewedAt = DateTime.now().toUtc().toIso8601String();
    final batch = db.batch();
    batch.delete(
      AppDbTables.history,
      where: 'user_id = ? AND article_id = ?',
      whereArgs: [userId, articleId],
    );
    batch.insert(AppDbTables.history, {
      'user_id': userId,
      'article_id': articleId,
      'viewed_at': viewedAt,
    });
    batch.execute(
      '''
        DELETE FROM ${AppDbTables.history}
        WHERE user_id = ? AND id NOT IN (
          SELECT id FROM ${AppDbTables.history}
          WHERE user_id = ?
          ORDER BY viewed_at DESC, id DESC
          LIMIT ${AppConstants.historyLimit}
        )
      ''',
      [userId, userId],
    );
    await batch.commit(noResult: true);
  }

  /// История пользователя: топ-20 по свежести.
  Future<List<HistoryRecordRaw>> listTop(int userId) async {
    final rows = await db.query(
      AppDbTables.history,
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'viewed_at DESC, id DESC',
      limit: AppConstants.historyLimit,
    );
    return [for (final row in rows) HistoryRecordRaw.fromMap(row)];
  }

  /// Очистка истории пользователя (кнопка «Очистить», P9).
  Future<void> clear(int userId) async {
    await db.delete(
      AppDbTables.history,
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }
}
