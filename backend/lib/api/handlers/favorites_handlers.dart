import 'package:shelf/shelf.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/auth.dart';
import '../../core/errors.dart';
import '../../models/article.dart';

/// Обработчики избранного пользователя.
class FavoritesHandlers {
  FavoritesHandlers(this.db, this.auth);

  /// Открытая БД.
  final Database db;

  /// Сервис авторизации.
  final AuthService auth;

  /// `GET /api/favorites` — опубликованные статьи в избранном.
  Future<Response> list(Request request) async {
    final context = await auth.authenticate(request);
    final rows = await db.rawQuery(
      'SELECT a.*, c.title AS category_title, f.created_at AS favorited_at '
      'FROM favorites f '
      'JOIN articles a ON a.id = f.article_id '
      'LEFT JOIN categories c ON c.id = a.category_id '
      'WHERE f.user_id = ? AND a.is_published = 1 '
      'ORDER BY f.created_at DESC, a.title COLLATE NOCASE ASC',
      [context.userId],
    );
    return jsonResponse([for (final row in rows) articleToJson(row)]);
  }

  /// `POST /api/favorites/{articleId}` — добавить в избранное (идемпотентно).
  Future<Response> add(Request request, String articleId) async {
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

    final existing = await db.query(
      'favorites',
      where: 'user_id = ? AND article_id = ?',
      whereArgs: [context.userId, articleId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return jsonResponse({'article_id': articleId, 'favorited': true});
    }

    try {
      await db.insert('favorites', {
        'user_id': context.userId,
        'article_id': articleId,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    } on Exception catch (error) {
      // Параллельный запрос мог успеть вставить ту же пару.
      if (!error.toString().toLowerCase().contains('unique')) rethrow;
      return jsonResponse({'article_id': articleId, 'favorited': true});
    }
    return jsonResponse({
      'article_id': articleId,
      'favorited': true,
    }, status: 201);
  }

  /// `DELETE /api/favorites/{articleId}` — убрать из избранного.
  Future<Response> remove(Request request, String articleId) async {
    final context = await auth.authenticate(request);
    await db.delete(
      'favorites',
      where: 'user_id = ? AND article_id = ?',
      whereArgs: [context.userId, articleId],
    );
    return emptyResponse();
  }
}
