import 'dart:convert';

/// Статья в JSON-представлении API.
///
/// [tags] и [blocks_json] в БД хранятся как JSON-строки; наружу отдаются
/// массивами. Дополнительные поля (`category_title`, `favorited_at`,
/// `viewed_at`) появляются, если они есть в строке результата JOIN.
Map<String, Object?> articleToJson(Map<String, Object?> row) {
  return {
    'id': row['id'],
    'category_id': row['category_id'],
    if (row['category_title'] != null) 'category_title': row['category_title'],
    'title': row['title'],
    'summary': row['summary'],
    'difficulty': row['difficulty'],
    'tags': decodeJsonArray(row['tags']),
    'blocks': decodeJsonArray(row['blocks_json']),
    'is_published': (row['is_published'] as int? ?? 0) != 0,
    'created_at': row['created_at'],
    'updated_at': row['updated_at'],
    if (row['favorited_at'] != null) 'favorited_at': row['favorited_at'],
    if (row['viewed_at'] != null) 'viewed_at': row['viewed_at'],
  };
}

/// Сериализация тегов в JSON-строку для хранения в БД.
String encodeStringList(List<String> values) => jsonEncode(values);

/// Сериализация блоков статьи в JSON-строку для хранения в БД.
String encodeBlocks(List<Map<String, Object?>> blocks) => jsonEncode(blocks);

/// Безопасный разбор JSON-массива из БД. Некорректное значение → `[]`.
List<Object?> decodeJsonArray(Object? raw) {
  if (raw is List) return raw;
  if (raw is String && raw.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded;
    } on FormatException {
      // Повреждённое значение не должно ронять ответ.
    }
  }
  return const [];
}
