import 'package:shelf/shelf.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/auth.dart';
import '../../core/errors.dart';
import '../../models/article.dart';
import '../../models/category.dart';

/// Обработчики контента: категории и опубликованные статьи.
class ContentHandlers {
  ContentHandlers(this.db, this.auth);

  /// Открытая БД.
  final Database db;

  /// Сервис авторизации.
  final AuthService auth;

  /// `GET /api/categories` — список категорий.
  Future<Response> categories(Request request) async {
    await auth.authenticate(request);
    final rows = await db.query(
      'categories',
      orderBy: 'sort_order ASC, title COLLATE NOCASE ASC',
    );
    return jsonResponse([for (final row in rows) categoryToJson(row)]);
  }

  /// `GET /api/articles?category=&difficulty=&q=` — опубликованные статьи.
  Future<Response> articles(Request request) async {
    await auth.authenticate(request);
    final query = request.url.queryParameters;
    final where = <String>['a.is_published = 1'];
    final arguments = <Object?>[];

    final category = query['category']?.trim();
    if (category != null && category.isNotEmpty) {
      where.add('a.category_id = ?');
      arguments.add(category);
    }

    final difficulty = query['difficulty']?.trim();
    if (difficulty != null && difficulty.isNotEmpty) {
      where.add('a.difficulty = ?');
      arguments.add(difficulty);
    }

    final rows = await db.rawQuery(
      'SELECT a.*, c.title AS category_title '
      'FROM articles a '
      'LEFT JOIN categories c ON c.id = a.category_id '
      'WHERE ${where.join(' AND ')} '
      'ORDER BY a.updated_at DESC, a.title COLLATE NOCASE ASC',
      arguments,
    );

    final needle = query['q']?.trim().toLowerCase() ?? '';
    final filtered = needle.isEmpty
        ? rows
        : rows.where((row) {
            final tags = decodeJsonArray(row['tags']).join(' ');
            final haystack = '${row['title']} ${row['summary']} $tags'
                .toLowerCase();
            return haystack.contains(needle);
          }).toList();

    return jsonResponse([for (final row in filtered) articleToJson(row)]);
  }

  /// `GET /api/articles/{id}` — статья по идентификатору.
  ///
  /// Пользователь видит только опубликованную статью; администратор —
  /// любую (нужно для формы редактирования).
  Future<Response> articleById(Request request, String articleId) async {
    final context = await auth.authenticate(request);
    final rows = await db.rawQuery(
      'SELECT a.*, c.title AS category_title '
      'FROM articles a '
      'LEFT JOIN categories c ON c.id = a.category_id '
      'WHERE a.id = ?',
      [articleId],
    );
    if (rows.isEmpty) {
      throw ApiError.notFound('Статья не найдена');
    }
    final article = rows.first;
    if ((article['is_published']! as int) == 0 && !context.isAdmin) {
      throw ApiError.notFound('Статья не найдена');
    }
    return jsonResponse(articleToJson(article));
  }
}
