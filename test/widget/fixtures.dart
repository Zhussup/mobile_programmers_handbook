import 'dart:convert';

/// Inline-фикстуры контента для виджет-тестов P8/P9.
///
/// Контент расширяется параллельно (контент-агент: 5→8 статей и новые
/// файлы), поэтому тесты поиска/избранного/истории НЕ опираются на реальный
/// контент — они подают собственные JSON-фикстуры через
/// `ArticleRepository.fromRaw` и получают детерминированные списки.

/// Одна статья-фикстура (один text-блок — достаточно для экранов).
Map<String, Object?> fixtureArticle({
  required String id,
  required String title,
  String summary = 'Краткое описание статьи.',
  String difficulty = 'beginner',
  List<String> tags = const ['тег'],
}) => {
  'id': id,
  'title': title,
  'summary': summary,
  'difficulty': difficulty,
  'tags': tags,
  'blocks': [
    {'type': 'text', 'text': 'Текст статьи $id.'},
    {
      'type': 'code',
      'language': 'cpp',
      'code': 'int main() { return 0; }',
      'output': '',
    },
  ],
};

/// Файл-категория с данными статей.
String fixtureCategory({
  required String id,
  required String title,
  required List<Map<String, Object?>> articles,
  String icon = 'code',
  String description = 'Тестовая категория',
}) => jsonEncode({
  'category': {
    'id': id,
    'title': title,
    'icon': icon,
    'description': description,
  },
  'articles': articles,
});

/// Детерминированный набор для тестов P8/P9: две категории, у статей
/// размазаны сложности и разные теги.
///
/// - `Примеры и вывод` (syntax): var — beginner (теги: переменные),
///   loop — intermediate (теги: циклы);
/// - `Контейнеры` (stl): vector — advanced (теги: stl, контейнеры),
///   map — intermediate (теги: stl).
final List<String> p8p9ReferenceFixtures = [
  fixtureCategory(
    id: 'syntax',
    title: 'Синтаксис C++',
    articles: [
      fixtureArticle(
        id: 'fx_syn_var',
        title: 'Переменные',
        summary: 'Объявление и инициализация переменных.',
        difficulty: 'beginner',
        tags: ['переменные', 'типы'],
      ),
      fixtureArticle(
        id: 'fx_syn_loop',
        title: 'Циклы',
        summary: 'for, while, do-while.',
        difficulty: 'intermediate',
        tags: ['циклы'],
      ),
    ],
  ),
  fixtureCategory(
    id: 'stl',
    title: 'Контейнеры STL',
    articles: [
      fixtureArticle(
        id: 'fx_stl_vector',
        title: 'Vector',
        summary: 'Динамический массив.',
        difficulty: 'advanced',
        tags: ['stl', 'контейнеры'],
      ),
      fixtureArticle(
        id: 'fx_stl_map',
        title: 'Map',
        summary: 'Словарь ключ-значение.',
        difficulty: 'intermediate',
        tags: ['stl'],
      ),
    ],
  ),
];
