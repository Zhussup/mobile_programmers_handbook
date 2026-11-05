import 'package:shelf/shelf.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/auth.dart';
import '../../core/errors.dart';
import '../../core/http_utils.dart';
import '../../core/validation.dart';
import '../../models/article.dart';
import '../../models/category.dart';
import '../../models/user.dart';

/// Административные обработчики: пользователи, статьи, категории.
class AdminHandlers {
  AdminHandlers(this.db, this.auth);

  /// Открытая БД.
  final Database db;

  /// Сервис авторизации.
  final AuthService auth;

  // ---------------------------------------------------------------------
  // Пользователи
  // ---------------------------------------------------------------------

  /// `GET /api/admin/users?q=` — все пользователи.
  Future<Response> users(Request request) async {
    await auth.authenticate(request, adminOnly: true);
    final needle = request.url.queryParameters['q']?.trim().toLowerCase() ?? '';
    var rows = await db.query('users', orderBy: 'id ASC');
    if (needle.isNotEmpty) {
      rows = rows.where((row) {
        final haystack = '${row['username']} ${row['email']}'.toLowerCase();
        return haystack.contains(needle);
      }).toList();
    }
    return jsonResponse([for (final row in rows) userToJson(row)]);
  }

  /// `POST /api/admin/users` — создать пользователя.
  Future<Response> createUser(Request request) async {
    await auth.authenticate(request, adminOnly: true);
    final body = await readJsonBody(request);
    final validator = FormValidator();
    validator.check(validateUsername(body['username']), 'username');
    validator.check(validateEmail(body['email']), 'email');
    validator.check(validatePassword(body['password']), 'password');
    final role = body.containsKey('role') ? body['role'] : 'user';
    validator.check(validateRole(role), 'role');
    final rawAvatar = body['avatar_color'];
    if (rawAvatar != null) {
      validator.check(validateAvatarColor(rawAvatar), 'avatar_color');
    }
    if (validator.hasErrors) validator.fail();

    final username = (body['username']! as String).trim();
    final email = (body['email']! as String).trim();
    final conflicts = <String, String>{};
    if (await auth.findUserByField('username', username) != null) {
      conflicts['username'] = 'Такое имя пользователя уже занято';
    }
    if (await auth.findUserByField('email', email) != null) {
      conflicts['email'] = 'Такая почта уже зарегистрирована';
    }
    if (conflicts.isNotEmpty) {
      throw ApiError.conflict(
        'Имя пользователя или почта уже заняты',
        fields: conflicts,
      );
    }

    final salt = AuthService.generateSalt();
    final int id;
    try {
      id = await db.insert('users', {
        'username': username,
        'email': email,
        'password_hash': AuthService.hashPassword(
          body['password']! as String,
          salt,
        ),
        'salt': salt,
        'role': role,
        'is_blocked': 0,
        'avatar_color': rawAvatar is String
            ? rawAvatar.trim()
            : pickAvatarColor(username),
        'created_at': _now(),
      });
    } on Exception catch (error) {
      if (_isUniqueViolation(error)) {
        throw ApiError.conflict('Имя пользователя или почта уже заняты');
      }
      rethrow;
    }
    final user = await auth.findUserById(id);
    return jsonResponse(userToJson(user!), status: 201);
  }

  /// `PUT /api/admin/users/{id}` — изменить пользователя.
  Future<Response> updateUser(Request request, String rawId) async {
    final context = await auth.authenticate(request, adminOnly: true);
    final id = _parseId(rawId, 'Пользователь не найден');
    final existing = await auth.findUserById(id);
    if (existing == null) throw ApiError.notFound('Пользователь не найден');

    final body = await readJsonBody(request);
    final validator = FormValidator();
    String? username;
    String? email;
    String? role;
    String? avatarColor;

    if (body.containsKey('username')) {
      validator.check(validateUsername(body['username']), 'username');
      username = stringValue(body['username']);
    }
    if (body.containsKey('email')) {
      validator.check(validateEmail(body['email']), 'email');
      email = stringValue(body['email']);
    }
    if (body.containsKey('role')) {
      validator.check(validateRole(body['role']), 'role');
      role = body['role'] is String ? body['role'] as String : null;
    }
    if (body.containsKey('avatar_color')) {
      validator.check(
        validateAvatarColor(body['avatar_color']),
        'avatar_color',
      );
      avatarColor = stringValue(body['avatar_color']);
    }
    if (validator.hasErrors) validator.fail();

    if (id == context.userId && role != null && role != 'admin') {
      throw ApiError.validation(
        'Нельзя понизить собственную роль',
        fields: {'role': 'Нельзя понизить собственную роль'},
      );
    }

    final conflicts = <String, String>{};
    if (username != null) {
      final found = await auth.findUserByField('username', username);
      if (found != null && found['id'] != id) {
        conflicts['username'] = 'Такое имя пользователя уже занято';
      }
    }
    if (email != null) {
      final found = await auth.findUserByField('email', email);
      if (found != null && found['id'] != id) {
        conflicts['email'] = 'Такая почта уже зарегистрирована';
      }
    }
    if (conflicts.isNotEmpty) {
      throw ApiError.conflict(
        'Имя пользователя или почта уже заняты',
        fields: conflicts,
      );
    }

    final updates = <String, Object?>{
      if (username != null) 'username': username,
      if (email != null) 'email': email,
      if (role != null) 'role': role,
      if (avatarColor != null) 'avatar_color': avatarColor,
    };
    if (updates.isNotEmpty) {
      try {
        await db.update('users', updates, where: 'id = ?', whereArgs: [id]);
      } on Exception catch (error) {
        if (_isUniqueViolation(error)) {
          throw ApiError.conflict('Имя пользователя или почта уже заняты');
        }
        rethrow;
      }
    }
    final user = await auth.findUserById(id);
    return jsonResponse(userToJson(user!));
  }

  /// `PATCH /api/admin/users/{id}/block` — блокировка/разблокировка.
  Future<Response> blockUser(Request request, String rawId) async {
    final context = await auth.authenticate(request, adminOnly: true);
    final id = _parseId(rawId, 'Пользователь не найден');
    final existing = await auth.findUserById(id);
    if (existing == null) throw ApiError.notFound('Пользователь не найден');

    final body = await readJsonBody(request);
    final rawBlocked = body.containsKey('blocked')
        ? body['blocked']
        : body['is_blocked'];
    final blocked = parseBool(rawBlocked);
    if (blocked == null) {
      throw ApiError.validation(
        'Поле blocked должно быть логическим значением',
        fields: {'blocked': 'Укажите true или false'},
      );
    }
    if (id == context.userId && blocked) {
      throw ApiError.validation(
        'Нельзя заблокировать самого себя',
        fields: {'blocked': 'Нельзя заблокировать самого себя'},
      );
    }

    await db.update(
      'users',
      {'is_blocked': blocked ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    if (blocked) {
      // Ранее выданные токены перестают действовать немедленно.
      await db.delete('sessions', where: 'user_id = ?', whereArgs: [id]);
    }
    final user = await auth.findUserById(id);
    return jsonResponse(userToJson(user!));
  }

  /// `PATCH /api/admin/users/{id}/role` — смена роли.
  Future<Response> changeRole(Request request, String rawId) async {
    final context = await auth.authenticate(request, adminOnly: true);
    final id = _parseId(rawId, 'Пользователь не найден');
    final existing = await auth.findUserById(id);
    if (existing == null) throw ApiError.notFound('Пользователь не найден');

    final body = await readJsonBody(request);
    final role = body['role'];
    final error = validateRole(role);
    if (error != null) {
      throw ApiError.validation(error, fields: {'role': error});
    }
    if (id == context.userId && role != 'admin') {
      throw ApiError.validation(
        'Нельзя понизить собственную роль',
        fields: {'role': 'Нельзя понизить собственную роль'},
      );
    }
    await db.update('users', {'role': role}, where: 'id = ?', whereArgs: [id]);
    final user = await auth.findUserById(id);
    return jsonResponse(userToJson(user!));
  }

  // ---------------------------------------------------------------------
  // Статьи
  // ---------------------------------------------------------------------

  /// `GET /api/admin/articles?category=&published=` — все статьи.
  Future<Response> articles(Request request) async {
    await auth.authenticate(request, adminOnly: true);
    final query = request.url.queryParameters;
    final where = <String>[];
    final arguments = <Object?>[];

    final category = query['category']?.trim();
    if (category != null && category.isNotEmpty) {
      where.add('a.category_id = ?');
      arguments.add(category);
    }
    final rawPublished = query['published'];
    if (rawPublished != null && rawPublished.trim().isNotEmpty) {
      final published = parseBool(rawPublished);
      if (published == null) {
        throw ApiError.validation(
          'Параметр published должен быть true или false',
          fields: {'published': 'Укажите true или false'},
        );
      }
      where.add('a.is_published = ?');
      arguments.add(published ? 1 : 0);
    }

    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    final rows = await db.rawQuery(
      'SELECT a.*, c.title AS category_title '
      'FROM articles a '
      'LEFT JOIN categories c ON c.id = a.category_id '
      '$whereSql '
      'ORDER BY a.updated_at DESC, a.title COLLATE NOCASE ASC',
      arguments,
    );
    return jsonResponse([for (final row in rows) articleToJson(row)]);
  }

  /// `POST /api/admin/articles` — создать статью.
  Future<Response> createArticle(Request request) async {
    await auth.authenticate(request, adminOnly: true);
    final body = await readJsonBody(request);
    final validator = FormValidator();

    validator.check(validateTitle(body['title']), 'title');
    final summary = optionalStringValue(body['summary']);
    if (summary == null) {
      validator.add('summary', 'Краткое описание должно быть строкой');
    }

    final rawCategory = body['category_id'] ?? body['category'];
    final categoryId = rawCategory is String ? rawCategory.trim() : null;
    if (categoryId == null || categoryId.isEmpty) {
      validator.add('category_id', 'Категория обязательна');
    } else if (!await _categoryExists(categoryId)) {
      validator.add('category_id', 'Категория не найдена');
    }

    final difficulty = body.containsKey('difficulty')
        ? body['difficulty']
        : 'beginner';
    validator.check(validateDifficulty(difficulty), 'difficulty');

    final tags = body.containsKey('tags')
        ? parseStringList(body['tags'])
        : <String>[];
    if (tags == null) {
      validator.add('tags', 'Теги должны быть массивом строк');
    }
    final blocks = body.containsKey('blocks')
        ? parseBlocks(body['blocks'])
        : <Map<String, Object?>>[];
    if (blocks == null) {
      validator.add('blocks', 'Блоки должны быть массивом объектов');
    }

    String? articleId;
    if (body.containsKey('id') && body['id'] != null) {
      articleId = stringValue(body['id']);
      if (articleId == null || articleId.isEmpty) {
        validator.add('id', 'Идентификатор статьи должен быть строкой');
      } else if (!RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(articleId)) {
        validator.add(
          'id',
          'Идентификатор может содержать только латиницу, цифры, _ и -',
        );
      }
    }

    final rawPublished = body.containsKey('is_published')
        ? body['is_published']
        : body['published'];
    final published = rawPublished == null ? false : parseBool(rawPublished);
    if (published == null) {
      validator.add('published', 'Поле published должно быть логическим');
    }
    if (validator.hasErrors) validator.fail();

    final id = articleId ?? _generateArticleId();
    final duplicate = await db.query(
      'articles',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (duplicate.isNotEmpty) {
      throw ApiError.conflict(
        'Статья с таким идентификатором уже существует',
        fields: {'id': 'Статья с таким идентификатором уже существует'},
      );
    }

    final now = _now();
    await db.insert('articles', {
      'id': id,
      'category_id': categoryId,
      'title': (body['title']! as String).trim(),
      'summary': summary,
      'difficulty': difficulty,
      'tags': _encodeStringList(tags!),
      'blocks_json': _encodeBlocks(blocks!),
      'is_published': published! ? 1 : 0,
      'created_at': now,
      'updated_at': now,
    });
    final article = await _articleById(id);
    return jsonResponse(articleToJson(article!), status: 201);
  }

  /// `PUT /api/admin/articles/{id}` — изменить статью.
  Future<Response> updateArticle(Request request, String articleId) async {
    await auth.authenticate(request, adminOnly: true);
    final existing = await _articleById(articleId);
    if (existing == null) throw ApiError.notFound('Статья не найдена');

    final body = await readJsonBody(request);
    final validator = FormValidator();
    String? title;
    String? summary;
    String? categoryId;
    String? difficulty;
    List<String>? tags;
    List<Map<String, Object?>>? blocks;
    bool? published;

    if (body.containsKey('title')) {
      validator.check(validateTitle(body['title']), 'title');
      title = stringValue(body['title']);
    }
    if (body.containsKey('summary')) {
      summary = optionalStringValue(body['summary']);
      if (summary == null) {
        validator.add('summary', 'Краткое описание должно быть строкой');
      }
    }
    if (body.containsKey('category_id') || body.containsKey('category')) {
      final rawCategory = body['category_id'] ?? body['category'];
      categoryId = rawCategory is String ? rawCategory.trim() : null;
      if (categoryId == null || categoryId.isEmpty) {
        validator.add('category_id', 'Категория обязательна');
      } else if (!await _categoryExists(categoryId)) {
        validator.add('category_id', 'Категория не найдена');
      }
    }
    if (body.containsKey('difficulty')) {
      validator.check(validateDifficulty(body['difficulty']), 'difficulty');
      difficulty = body['difficulty'] is String
          ? body['difficulty'] as String
          : null;
    }
    if (body.containsKey('tags')) {
      tags = parseStringList(body['tags']);
      if (tags == null)
        validator.add('tags', 'Теги должны быть массивом строк');
    }
    if (body.containsKey('blocks')) {
      blocks = parseBlocks(body['blocks']);
      if (blocks == null) {
        validator.add('blocks', 'Блоки должны быть массивом объектов');
      }
    }
    if (body.containsKey('is_published') || body.containsKey('published')) {
      final rawPublished = body.containsKey('is_published')
          ? body['is_published']
          : body['published'];
      published = parseBool(rawPublished);
      if (published == null) {
        validator.add('published', 'Поле published должно быть логическим');
      }
    }
    if (validator.hasErrors) validator.fail();

    final updates = <String, Object?>{
      if (title != null) 'title': title,
      if (summary != null) 'summary': summary,
      if (categoryId != null) 'category_id': categoryId,
      if (difficulty != null) 'difficulty': difficulty,
      if (tags != null) 'tags': _encodeStringList(tags),
      if (blocks != null) 'blocks_json': _encodeBlocks(blocks),
      if (published != null) 'is_published': published ? 1 : 0,
      'updated_at': _now(),
    };
    await db.update(
      'articles',
      updates,
      where: 'id = ?',
      whereArgs: [articleId],
    );
    final article = await _articleById(articleId);
    return jsonResponse(articleToJson(article!));
  }

  /// `DELETE /api/admin/articles/{id}` — удалить статью.
  Future<Response> deleteArticle(Request request, String articleId) async {
    await auth.authenticate(request, adminOnly: true);
    final existing = await _articleById(articleId);
    if (existing == null) throw ApiError.notFound('Статья не найдена');
    // ON DELETE CASCADE удалит связанные записи избранного и истории.
    await db.delete('articles', where: 'id = ?', whereArgs: [articleId]);
    return emptyResponse();
  }

  /// `PATCH /api/admin/articles/{id}/publish` — публикация/снятие.
  Future<Response> publishArticle(Request request, String articleId) async {
    await auth.authenticate(request, adminOnly: true);
    final existing = await _articleById(articleId);
    if (existing == null) throw ApiError.notFound('Статья не найдена');

    final body = await readJsonBody(request);
    final published = parseBool(body['published']);
    if (published == null) {
      throw ApiError.validation(
        'Поле published должно быть логическим значением',
        fields: {'published': 'Укажите true или false'},
      );
    }
    await db.update(
      'articles',
      {'is_published': published ? 1 : 0, 'updated_at': _now()},
      where: 'id = ?',
      whereArgs: [articleId],
    );
    final article = await _articleById(articleId);
    return jsonResponse(articleToJson(article!));
  }

  // ---------------------------------------------------------------------
  // Категории
  // ---------------------------------------------------------------------

  /// `GET /api/admin/categories` — все категории.
  Future<Response> categories(Request request) async {
    await auth.authenticate(request, adminOnly: true);
    final rows = await db.query(
      'categories',
      orderBy: 'sort_order ASC, title COLLATE NOCASE ASC',
    );
    return jsonResponse([for (final row in rows) categoryToJson(row)]);
  }

  /// `POST /api/admin/categories` — создать категорию.
  Future<Response> createCategory(Request request) async {
    await auth.authenticate(request, adminOnly: true);
    final body = await readJsonBody(request);
    final validator = FormValidator();

    final id = stringValue(body['id']);
    if (id == null || id.isEmpty) {
      validator.add('id', 'Идентификатор категории обязателен');
    } else if (!RegExp(r'^[A-Za-z0-9_-]{1,50}$').hasMatch(id)) {
      validator.add(
        'id',
        'Идентификатор может содержать только латиницу, цифры, _ и -',
      );
    }
    validator.check(validateTitle(body['title']), 'title');
    final description = optionalStringValue(body['description']);
    if (description == null) {
      validator.add('description', 'Описание должно быть строкой');
    }
    final icon = optionalStringValue(body['icon'], fallback: 'book');
    if (icon == null) validator.add('icon', 'Иконка должна быть строкой');
    final sortOrder = _optionalInt(body['sort_order']);
    if (body.containsKey('sort_order') && sortOrder == null) {
      validator.add('sort_order', 'Порядок сортировки должен быть числом');
    }
    if (validator.hasErrors) validator.fail();

    final duplicate = await db.query(
      'categories',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (duplicate.isNotEmpty) {
      throw ApiError.conflict(
        'Категория с таким идентификатором уже существует',
        fields: {'id': 'Категория с таким идентификатором уже существует'},
      );
    }

    await db.insert('categories', {
      'id': id,
      'title': (body['title']! as String).trim(),
      'description': description,
      'icon': icon,
      'sort_order': sortOrder ?? 0,
    });
    final rows = await db.query(
      'categories',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return jsonResponse(categoryToJson(rows.first), status: 201);
  }

  /// `PUT /api/admin/categories/{id}` — изменить категорию.
  Future<Response> updateCategory(Request request, String categoryId) async {
    await auth.authenticate(request, adminOnly: true);
    final existing = await db.query(
      'categories',
      where: 'id = ?',
      whereArgs: [categoryId],
      limit: 1,
    );
    if (existing.isEmpty) throw ApiError.notFound('Категория не найдена');

    final body = await readJsonBody(request);
    final validator = FormValidator();
    String? title;
    String? description;
    String? icon;
    int? sortOrder;

    if (body.containsKey('title')) {
      validator.check(validateTitle(body['title']), 'title');
      title = stringValue(body['title']);
    }
    if (body.containsKey('description')) {
      description = optionalStringValue(body['description']);
      if (description == null) {
        validator.add('description', 'Описание должно быть строкой');
      }
    }
    if (body.containsKey('icon')) {
      icon = optionalStringValue(body['icon']);
      if (icon == null || icon.isEmpty) {
        validator.add('icon', 'Иконка должна быть непустой строкой');
      }
    }
    if (body.containsKey('sort_order')) {
      sortOrder = _optionalInt(body['sort_order']);
      if (sortOrder == null) {
        validator.add('sort_order', 'Порядок сортировки должен быть числом');
      }
    }
    if (validator.hasErrors) validator.fail();

    final updates = <String, Object?>{
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (icon != null) 'icon': icon,
      if (sortOrder != null) 'sort_order': sortOrder,
    };
    if (updates.isNotEmpty) {
      await db.update(
        'categories',
        updates,
        where: 'id = ?',
        whereArgs: [categoryId],
      );
    }
    final rows = await db.query(
      'categories',
      where: 'id = ?',
      whereArgs: [categoryId],
      limit: 1,
    );
    return jsonResponse(categoryToJson(rows.first));
  }

  /// `DELETE /api/admin/categories/{id}` — удалить пустую категорию.
  Future<Response> deleteCategory(Request request, String categoryId) async {
    await auth.authenticate(request, adminOnly: true);
    final existing = await db.query(
      'categories',
      where: 'id = ?',
      whereArgs: [categoryId],
      limit: 1,
    );
    if (existing.isEmpty) throw ApiError.notFound('Категория не найдена');

    final articles = await db.query(
      'articles',
      where: 'category_id = ?',
      whereArgs: [categoryId],
      limit: 1,
    );
    if (articles.isNotEmpty) {
      throw ApiError.conflict(
        'Нельзя удалить категорию, пока в ней есть статьи',
      );
    }
    await db.delete('categories', where: 'id = ?', whereArgs: [categoryId]);
    return emptyResponse();
  }

  // ---------------------------------------------------------------------
  // Вспомогательные методы
  // ---------------------------------------------------------------------

  Future<bool> _categoryExists(String id) async {
    final rows = await db.query(
      'categories',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<Map<String, Object?>?> _articleById(String id) async {
    final rows = await db.rawQuery(
      'SELECT a.*, c.title AS category_title '
      'FROM articles a '
      'LEFT JOIN categories c ON c.id = a.category_id '
      'WHERE a.id = ?',
      [id],
    );
    return rows.isEmpty ? null : rows.first;
  }

  int _parseId(String rawId, String message) {
    final id = int.tryParse(rawId);
    if (id == null || id <= 0) throw ApiError.notFound(message);
    return id;
  }

  String _generateArticleId() {
    final suffix = AuthService.generateToken().substring(0, 8);
    return 'art_${DateTime.now().microsecondsSinceEpoch}_$suffix';
  }

  String _encodeStringList(List<String> values) => encodeStringList(values);

  String _encodeBlocks(List<Map<String, Object?>> blocks) {
    return encodeBlocks(blocks);
  }

  int? _optionalInt(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

  bool _isUniqueViolation(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('unique') || text.contains('constraint');
  }

  String _now() => DateTime.now().toUtc().toIso8601String();
}
