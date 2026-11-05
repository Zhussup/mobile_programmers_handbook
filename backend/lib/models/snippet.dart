/// Сниппет песочницы в JSON-представлении API.
Map<String, Object?> snippetToJson(Map<String, Object?> row) {
  return {
    'id': row['id'],
    'user_id': row['user_id'],
    'title': row['title'],
    'language': row['language'],
    'code': row['code'],
    'expected_output': row['expected_output'],
    'created_at': row['created_at'],
    'updated_at': row['updated_at'],
  };
}
