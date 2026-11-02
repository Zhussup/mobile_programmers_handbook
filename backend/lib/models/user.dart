/// Пользователь API (без хэша и соли).
Map<String, Object?> userToJson(Map<String, Object?> row) {
  return {
    'id': row['id'],
    'username': row['username'],
    'email': row['email'],
    'role': row['role'],
    'is_blocked': (row['is_blocked'] as int? ?? 0) != 0,
    'avatar_color': row['avatar_color'],
    'created_at': row['created_at'],
  };
}

/// Палитра цветов аватара (совпадает с мобильным приложением).
const List<String> avatarPalette = [
  '#2AA79B',
  '#4D8BF5',
  '#E0A83F',
  '#D16A8A',
  '#8C6FF0',
  '#5FA85D',
  '#4BA6C7',
  '#C75B4A',
];

/// Детерминированный цвет аватара по имени пользователя.
String pickAvatarColor(String username) {
  var sum = 0;
  for (final rune in username.runes) {
    sum += rune;
  }
  return avatarPalette[sum % avatarPalette.length];
}
