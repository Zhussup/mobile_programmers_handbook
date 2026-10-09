import 'package:sqflite/sqflite.dart';

import '../../core/constants/app_constants.dart';
import '../../core/db/app_database.dart';
import 'snippet_model.dart';

/// Репозиторий сниппетов песочницы (P10): таблица `user_snippets`.
///
/// Полный CRUD; ВСЕ запросы — с `WHERE user_id = ?` (изоляция мультиюзера:
/// чужой сниппет нельзя ни прочитать, ни изменить, ни удалить, даже зная id;
/// logout ничего не удаляет). SQL-запросы строго параметризованные, имена
/// таблиц — константы [AppDbTables] (пользовательский ввод в SQL не
/// подставляется).
class SnippetRepository {
  /// Репозиторий поверх открытой БД ([AppDatabase.instance]).
  const SnippetRepository({required this.db});

  /// Открытая база.
  final Database db;

  /// Список сниппетов пользователя: свежие изменения раньше
  /// (ORDER BY updated_at DESC, id DESC — id как тайбрейк).
  Future<List<Snippet>> listForUser(int userId) async {
    final rows = await db.query(
      AppConstants.tableUserSnippets,
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'updated_at DESC, id DESC',
    );
    return [for (final row in rows) Snippet.fromMap(row)];
  }

  /// Создание сниппета: INSERT (created_at = updated_at = сейчас) и чтение
  /// готовой модели. Id присваивает БД (AUTOINCREMENT).
  Future<Snippet> create({
    required int userId,
    required String title,
    required SnippetLanguage language,
    required String code,
    String? expectedOutput,
  }) async {
    final now = DateTime.now().toIso8601String();
    final id = await db.insert(
      AppConstants.tableUserSnippets,
      Snippet(
        id: 0,
        userId: userId,
        title: title.trim(),
        language: language,
        code: code,
        expectedOutput: expectedOutput,
        createdAt: DateTime.parse(now),
        updatedAt: DateTime.parse(now),
      ).toMap(),
    );
    return Snippet(
      id: id,
      userId: userId,
      title: title.trim(),
      language: language,
      code: code,
      expectedOutput: expectedOutput,
      createdAt: DateTime.parse(now),
      updatedAt: DateTime.parse(now),
    );
  }

  /// Чтение одного сниппета ПОЛЬЗОВАТЕЛЯ по id (null — нет/чужой сниппет:
  /// ограничение `user_id = ?` в WHERE делает чужой неотличимым от отсутствия).
  Future<Snippet?> getById(int userId, int id) async {
    final rows = await db.query(
      AppConstants.tableUserSnippets,
      where: 'user_id = ? AND id = ?',
      whereArgs: [userId, id],
      limit: 1,
    );
    return rows.isEmpty ? null : Snippet.fromMap(rows.first);
  }

  /// Обновление сниппета пользователя: все редактируемые поля +
  /// updated_at = сейчас (created_at сохраняется).
  ///
  /// Ограничение `user_id = ?` в WHERE: чужой сниппет не затрагивается
  /// (возвращается null — «не найдено у этого пользователя»).
  Future<Snippet?> update({
    required int userId,
    required int id,
    required String title,
    required SnippetLanguage language,
    required String code,
    String? expectedOutput,
  }) async {
    final rowsUpdated = await db.update(
      AppConstants.tableUserSnippets,
      {
        'title': title.trim(),
        'language': language.raw,
        'code': code,
        'expected_output': expectedOutput,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'user_id = ? AND id = ?',
      whereArgs: [userId, id],
    );
    if (rowsUpdated == 0) return null;
    return getById(userId, id);
  }

  /// Удаление сниппета пользователя. Ограничение `user_id = ?` в WHERE:
  /// повторное удаление и чужой сниппет — no-op.
  ///
  /// Возвращает true, если строка реально удалена.
  Future<bool> delete(int userId, int id) async {
    final rowsDeleted = await db.delete(
      AppConstants.tableUserSnippets,
      where: 'user_id = ? AND id = ?',
      whereArgs: [userId, id],
    );
    return rowsDeleted > 0;
  }
}

/// Вспомогательная тестовая утилита (в production счётчик профиля читает
/// [SnippetProvider]): количество сниппетов пользователя.
Future<int> snippetCountForUser(Database db, int userId) async {
  final result = await db.query(
    AppConstants.tableUserSnippets,
    columns: const ['COUNT(*)'],
    where: 'user_id = ?',
    whereArgs: [userId],
  );
  return result.single.values.first as int? ?? 0;
}