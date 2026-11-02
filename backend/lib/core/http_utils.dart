import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'errors.dart';

/// Чтение JSON-объекта из тела запроса.
///
/// Пустое тело → пустая карта. Некорректный JSON → 400 `validation_error`.
Future<Map<String, dynamic>> readJsonBody(Request request) async {
  final text = await request.readAsString();
  if (text.trim().isEmpty) return <String, dynamic>{};
  try {
    final decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } on FormatException {
    // Ниже — единое сообщение.
  }
  throw ApiError.validation('Некорректный JSON в теле запроса');
}

/// Строковое значение поля с обрезкой; `null` для отсутствующего/не-строки.
String? stringValue(Object? raw) {
  if (raw is! String) return null;
  return raw.trim();
}

/// Необязательная строка: отсутствие → [fallback], не-строка → `null`
/// (вызывающий сам решает, считать это ошибкой).
String? optionalStringValue(Object? raw, {String fallback = ''}) {
  if (raw == null) return fallback;
  if (raw is! String) return null;
  return raw.trim();
}
