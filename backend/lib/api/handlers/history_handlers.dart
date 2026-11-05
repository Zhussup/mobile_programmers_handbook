import 'package:shelf/shelf.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/auth.dart';
import '../../core/errors.dart';
import '../../core/validation.dart';
import '../../models/article.dart';

/// Обработчики истории просмотров.
class HistoryHandlers {
  HistoryHandlers(this.db, this.auth);

  /// Открытая БД.
  final Database db;

  /// Сервис авторизации.
  final AuthService auth;

  /// `GET /api/history?limit=20` — свежие просмотры сверху.
  Future<Response> list(Request request) async {
    final context = await auth.authenticate(request);
    final limit = parseLimit(request.url.queryParameters['limit']);
    final rows = await db.rawQuery(
      'SELECT a.*, c.title AS category_title, h.viewed_at '
      'FROM history h '
      'JOIN articles a ON a.id = h.article_id '
      'LEFT JOIN categories c ON c.id = a.category_id '
      'WHERE h.user_id = ? AND a.is_published = 1 '
      'ORDER BY h.viewed_at DESC, h.id DESC '
      'LIMIT ?',
      [context.userId, limit],
    );
    return jsonResponse([for (final row in rows) articleToJson(row)]);
  }

  /// `POST /api/history/{articleId}` — записать просмотр.
  ///
  /// Для пары (пользователь, статья) хранится одна строка: повторный
  /// просмотр только обновляет время.
  Future<Response> record(Request request, String articleId) async {
    final context = await auth.authenticate(request);
    final articles = await db.query(
      'articles',
      where: 'id = ? AND is_published = 1',
      whereArgs: [articleId],
      limit: 1,
    );
    if (articles.isEmpty) {
      throw ApiError.notFound('Статья не найдена');
    }

    final viewedAt = DateTime.now().toUtc().toIso8601String();
    final existing = await db.query(
      'history',
      where: 'user_id = ? AND article_id = ?',
      whereArgs: [context.userId, articleId],
      orderBy: 'id DESC',
      limit: 1,
    );

    if (existing.isEmpty) {
      await db.insert('history', {
        'user_id': context.userId,
        'article_id': articleId,
        'viewed_at': viewedAt,
      });
      return jsonResponse({
        'article_id': articleId,
        'viewed_at': viewedAt,
      }, status: 201);
    }

    await db.update(
      'history',
      {'viewed_at': viewedAt},
      where: 'id = ?',
      whereArgs: [existing.first['id']],
    );
    return jsonResponse({'article_id': articleId, 'viewed_at': viewedAt});
  }

  /// `DELETE /api/history` — очистить историю текущего пользователя.
  Future<Response> clear(Request request) async {
    final context = await auth.authenticate(request);
    await db.delete(
      'history',
      where: 'user_id = ?',
      whereArgs: [context.userId],
    );
    return emptyResponse();
  }
}
