import 'dart:convert';

/// Безопасный разбор JSON-значений из ответов API.
Map<String, dynamic> asJsonMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((k, v) => MapEntry(k.toString(), v));
  return <String, dynamic>{};
}

/// Достаёт массив из ответа: сам список либо обёртка `items`/`articles`/…
List<dynamic> asJsonList(dynamic value, {List<String> keys = const []}) {
  if (value is List) return value;
  if (value is Map) {
    for (final key in keys) {
      final nested = value[key];
      if (nested is List) return nested;
    }
  }
  return const <dynamic>[];
}

int asInt(dynamic value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

bool asBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value?.toString().toLowerCase();
  return text == 'true' || text == '1';
}

String asString(dynamic value, {String fallback = ''}) {
  if (value == null) return fallback;
  final text = value.toString();
  return text.isEmpty ? fallback : text;
}

/// Разбирает JSON-массив строк; при ошибке возвращает пустой список.
List<String> parseStringList(dynamic value) {
  if (value is List) {
    return value
        .where((item) => item != null)
        .map((item) => item.toString())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  if (value is String && value.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is List) return parseStringList(decoded);
    } catch (_) {
      return value
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
  }
  return <String>[];
}

/// Приводит блоки статьи к строке JSON-массива.
String normalizeBlocksJson(dynamic value) {
  if (value is String) {
    final text = value.trim();
    if (text.isEmpty) return '[]';
    try {
      final decoded = jsonDecode(text);
      if (decoded is List) {
        return const JsonEncoder.withIndent('  ').convert(decoded);
      }
    } catch (_) {
      return text;
    }
    return text;
  }
  if (value is List) {
    return const JsonEncoder.withIndent('  ').convert(value);
  }
  return '[]';
}
