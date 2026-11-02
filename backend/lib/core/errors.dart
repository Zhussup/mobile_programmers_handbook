import 'dart:convert';

import 'package:shelf/shelf.dart';

/// Заголовки JSON-ответа (UTF-8 — русские сообщения).
const Map<String, String> jsonHeaders = {
  'content-type': 'application/json; charset=utf-8',
};

/// Единая ошибка API.
///
/// Обработчик выбрасывает [ApiError], промежуточный слой превращает её в
/// JSON-ответ вида:
/// `{"error": {"code": "...", "message": "...", "fields": {...}}}`.
class ApiError implements Exception {
  /// Создание ошибки с HTTP-статусом, машинным кодом и русским сообщением.
  const ApiError(this.statusCode, this.code, this.message, {this.fields});

  /// HTTP-статус ответа.
  final int statusCode;

  /// Машинный код (`validation_error`, `unauthorized`, ...).
  final String code;

  /// Русское сообщение для пользователя.
  final String message;

  /// Ошибки по полям формы (необязательно).
  final Map<String, String>? fields;

  /// Ошибка валидации (400).
  factory ApiError.validation(String message, {Map<String, String>? fields}) {
    return ApiError(400, 'validation_error', message, fields: fields);
  }

  /// Нет или истёк токен (401).
  factory ApiError.unauthorized([String message = 'Требуется авторизация']) {
    return ApiError(401, 'unauthorized', message);
  }

  /// Недостаточно прав (403). Для заблокированного пользователя —
  /// `ApiError.forbidden('user_blocked', 'Учётная запись заблокирована')`.
  factory ApiError.forbidden([
    String code = 'forbidden',
    String message = 'Недостаточно прав',
  ]) {
    return ApiError(403, code, message);
  }

  /// Объект не найден (404).
  factory ApiError.notFound([String message = 'Объект не найден']) {
    return ApiError(404, 'not_found', message);
  }

  /// Конфликт уникальности (409).
  factory ApiError.conflict(String message, {Map<String, String>? fields}) {
    return ApiError(409, 'conflict', message, fields: fields);
  }

  /// Непредвиденная ошибка (500); детали клиенту не раскрываются.
  factory ApiError.internal() {
    return const ApiError(500, 'internal_error', 'Внутренняя ошибка сервера');
  }

  /// JSON-представление ошибки (без `null`-полей).
  Map<String, Object?> toJson() {
    return {
      'code': code,
      'message': message,
      if (fields != null && fields!.isNotEmpty) 'fields': fields,
    };
  }

  @override
  String toString() => 'ApiError($statusCode, $code): $message';
}

/// Успешный ответ: `{"data": ...}`.
Response jsonResponse(Object? data, {int status = 200}) {
  return Response(
    status,
    body: jsonEncode({'data': data}),
    headers: jsonHeaders,
  );
}

/// Ответ без тела (204 по умолчанию).
Response emptyResponse([int status = 204]) => Response(status);

/// Ответ с ошибкой в едином формате.
Response errorResponse(ApiError error) {
  return Response(
    error.statusCode,
    body: jsonEncode({'error': error.toJson()}),
    headers: jsonHeaders,
  );
}
