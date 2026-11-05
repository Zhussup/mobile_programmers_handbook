/// Категория справочника в JSON-представлении API.
Map<String, Object?> categoryToJson(Map<String, Object?> row) {
  return {
    'id': row['id'],
    'title': row['title'],
    'description': row['description'],
    'icon': row['icon'],
    'sort_order': row['sort_order'],
  };
}
