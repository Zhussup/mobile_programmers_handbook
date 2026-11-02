import '../utils/json_utils.dart';

/// Категория контента (используется фильтром и формой статьи).
class Category {
  const Category({
    required this.id,
    required this.title,
    this.description = '',
    this.icon = 'book',
    this.sortOrder = 0,
  });

  final String id;
  final String title;
  final String description;
  final String icon;
  final int sortOrder;

  factory Category.fromJson(dynamic json) {
    final map = asJsonMap(json);
    return Category(
      id: asString(map['id']),
      title: asString(map['title'], fallback: asString(map['id'])),
      description: asString(map['description']),
      icon: asString(map['icon'], fallback: 'book'),
      sortOrder: asInt(map['sort_order'] ?? map['sortOrder']),
    );
  }
}
