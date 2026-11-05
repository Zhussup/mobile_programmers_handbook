import '../utils/json_utils.dart';

/// Статья, доступная в мобильном приложении.
class Article {
  const Article({
    required this.id,
    required this.categoryId,
    required this.title,
    this.summary = '',
    this.difficulty = 'beginner',
    this.tags = const <String>[],
    this.blocksJson = '[]',
    this.isPublished = false,
    this.createdAt = '',
    this.updatedAt = '',
    this.categoryTitle = '',
  });

  final String id;
  final String categoryId;
  final String title;
  final String summary;
  final String difficulty;
  final List<String> tags;
  final String blocksJson;
  final bool isPublished;
  final String createdAt;
  final String updatedAt;

  /// Название категории, если backend вернул её вложенным объектом.
  final String categoryTitle;

  String get statusLabel => isPublished ? 'Опубликована' : 'Черновик';

  factory Article.fromJson(dynamic json) {
    final map = asJsonMap(json);
    final rawCategory = map['category'];

    var categoryId = asString(map['category_id'] ?? map['categoryId']);
    var categoryTitle = '';
    if (rawCategory is Map) {
      final categoryMap = asJsonMap(rawCategory);
      categoryTitle = asString(categoryMap['title']);
      if (categoryId.isEmpty) {
        categoryId = asString(categoryMap['id']);
      }
    } else if (rawCategory is String) {
      categoryTitle = rawCategory;
    }

    final rawTags = map['tags'];
    final rawBlocks = map['blocks_json'] ?? map['blocksJson'] ?? map['blocks'];

    return Article(
      id: asString(map['id']),
      categoryId: categoryId,
      title: asString(map['title'], fallback: 'Без названия'),
      summary: asString(map['summary']),
      difficulty: asString(map['difficulty'], fallback: 'beginner'),
      tags: parseStringList(rawTags),
      blocksJson: normalizeBlocksJson(rawBlocks),
      isPublished: asBool(
        map['is_published'] ?? map['isPublished'] ?? map['published'],
      ),
      createdAt: asString(map['created_at'] ?? map['createdAt']),
      updatedAt: asString(map['updated_at'] ?? map['updatedAt']),
      categoryTitle: categoryTitle,
    );
  }

  Article copyWith({
    String? categoryId,
    String? title,
    String? summary,
    String? difficulty,
    List<String>? tags,
    String? blocksJson,
    bool? isPublished,
    String? updatedAt,
    String? categoryTitle,
  }) {
    return Article(
      id: id,
      categoryId: categoryId ?? this.categoryId,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      difficulty: difficulty ?? this.difficulty,
      tags: tags ?? this.tags,
      blocksJson: blocksJson ?? this.blocksJson,
      isPublished: isPublished ?? this.isPublished,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      categoryTitle: categoryTitle ?? this.categoryTitle,
    );
  }
}

/// Русские подписи уровней сложности.
const Map<String, String> difficultyLabels = <String, String>{
  'beginner': 'Начальный',
  'intermediate': 'Средний',
  'advanced': 'Продвинутый',
};

String difficultyLabel(String value) => difficultyLabels[value] ?? value;
