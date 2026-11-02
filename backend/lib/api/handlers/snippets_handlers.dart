import 'package:shelf/shelf.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/auth.dart';
import '../../core/errors.dart';
import '../../core/http_utils.dart';
import '../../core/validation.dart';
import '../../models/snippet.dart';

/// Обработчики личных сниппетов песочницы.
class SnippetsHandlers {
  SnippetsHandlers(this.db, this.auth);

  /// Открытая БД.
  final Database db;

  /// Сервис авторизации.
  final AuthService auth;

  /// `GET /api/snippets` — сниппеты текущего пользователя.
  Future<Response> list(Request request) async {
    final context = await auth.authenticate(request);
    final rows = await db.query(
      'snippets',
      where: 'user_id = ?',
      whereArgs: [context.userId],
      orderBy: 'updated_at DESC, id DESC',
    );
    return jsonResponse([for (final row in rows) snippetToJson(row)]);
  }

  /// `POST /api/snippets` — создать сниппет.
  Future<Response> create(Request request) async {
    final context = await auth.authenticate(request);
    final body = await readJsonBody(request);
    final validator = FormValidator();
    validator.check(validateTitle(body['title']), 'title');
    validator.check(validateLanguage(body['language']), 'language');
    final code = optionalStringValue(body['code']);
    if (code == null) validator.add('code', 'Код должен быть строкой');
    final expectedOutput = optionalStringValue(body['expected_output']);
    if (expectedOutput == null) {
      validator.add('expected_output', 'Ожидаемый вывод должен быть строкой');
    }
    if (validator.hasErrors) validator.fail();

    final now = DateTime.now().toUtc().toIso8601String();
    final id = await db.insert('snippets', {
      'user_id': context.userId,
      'title': (body['title']! as String).trim(),
      'language': body['language']! as String,
      'code': code,
      'expected_output': expectedOutput,
      'created_at': now,
      'updated_at': now,
    });
    final row = await _findOwn(context.userId, id);
    return jsonResponse(snippetToJson(row!), status: 201);
  }

  /// `GET /api/snippets/{id}` — свой сниппет.
  Future<Response> getById(Request request, String rawId) async {
    final context = await auth.authenticate(request);
    final id = _parseId(rawId);
    final row = await _findOwn(context.userId, id);
    if (row == null) throw ApiError.notFound('Сниппет не найден');
    return jsonResponse(snippetToJson(row));
  }

  /// `PUT /api/snippets/{id}` — изменить свой сниппет.
  Future<Response> update(Request request, String rawId) async {
    final context = await auth.authenticate(request);
    final id = _parseId(rawId);
    final existing = await _findOwn(context.userId, id);
    if (existing == null) throw ApiError.notFound('Сниппет не найден');

    final body = await readJsonBody(request);
    final validator = FormValidator();
    String? title;
    String? language;
    String? code;
    String? expectedOutput;
    if (body.containsKey('title')) {
      validator.check(validateTitle(body['title']), 'title');
      title = stringValue(body['title']);
    }
    if (body.containsKey('language')) {
      validator.check(validateLanguage(body['language']), 'language');
      language = body['language'] as String?;
    }
    if (body.containsKey('code')) {
      code = optionalStringValue(body['code']);
      if (code == null) validator.add('code', 'Код должен быть строкой');
    }
    if (body.containsKey('expected_output')) {
      expectedOutput = optionalStringValue(body['expected_output']);
      if (expectedOutput == null) {
        validator.add('expected_output', 'Ожидаемый вывод должен быть строкой');
      }
    }
    if (validator.hasErrors) validator.fail();

    final updates = <String, Object?>{
      if (title != null) 'title': title,
      if (language != null) 'language': language,
      if (code != null) 'code': code,
      if (expectedOutput != null) 'expected_output': expectedOutput,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    await db.update(
      'snippets',
      updates,
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, context.userId],
    );
    final row = await _findOwn(context.userId, id);
    return jsonResponse(snippetToJson(row!));
  }

  /// `DELETE /api/snippets/{id}` — удалить свой сниппет.
  Future<Response> delete(Request request, String rawId) async {
    final context = await auth.authenticate(request);
    final id = _parseId(rawId);
    final existing = await _findOwn(context.userId, id);
    if (existing == null) throw ApiError.notFound('Сниппет не найден');
    await db.delete(
      'snippets',
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, context.userId],
    );
    return emptyResponse();
  }

  Future<Map<String, Object?>?> _findOwn(int userId, int id) async {
    final rows = await db.query(
      'snippets',
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, userId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  int _parseId(String rawId) {
    final id = int.tryParse(rawId);
    if (id == null || id <= 0) throw ApiError.notFound('Сниппет не найден');
    return id;
  }
}
