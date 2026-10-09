import 'package:flutter/foundation.dart' show immutable;

/// Сложность статьи (в контенте допустимы только эти три значения — README).
enum Difficulty { beginner, intermediate, advanced }

extension DifficultyX on Difficulty {
  /// Русская подпись сложности для бейджа на карточках.
  String get label => switch (this) {
    Difficulty.beginner => 'Базовый',
    Difficulty.intermediate => 'Средний',
    Difficulty.advanced => 'Продвинутый',
  };

  /// Порядок сортировки: простые статьи раньше сложных.
  int get sortOrder => index;
}

/// Разбор значения `difficulty` из JSON.
///
/// Defensive: пустое/неизвестное значение → [Difficulty.beginner] (не падаем).
Difficulty difficultyFromRaw(Object? raw) {
  if (raw is String) {
    return Difficulty.values.firstWhere(
      (d) => d.name == raw,
      orElse: () => Difficulty.beginner,
    );
  }
  return Difficulty.beginner;
}

/// Значение-строка из карты JSON (null, если поля нет/оно не строка/пустое).
String? _stringField(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is String && value.isNotEmpty) return value;
  return null;
}

/// Категория справочника (данные поля `category` одного JSON-файла).
///
/// id — строка маршрута `/reference/:categoryId` (см. README контента).
@immutable
class ReferenceCategory {
  const ReferenceCategory({
    required this.id,
    required this.title,
    required this.icon,
    required this.description,
  });

  /// Строковый id-роут (напр. `syntax`).
  final String id;

  /// Название категории (русское).
  final String title;

  /// Имя Material Icons (напр. `code`) — расшифровка в category_icon.dart.
  final String icon;

  /// Короткое описание категории.
  final String description;

  /// Разбор поля `category` из JSON; null — структурно неверное (пропустить).
  static ReferenceCategory? tryParse(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final id = _stringField(raw, 'id');
    final title = _stringField(raw, 'title');
    if (id == null || title == null) return null;
    return ReferenceCategory(
      id: id,
      title: title,
      // Незаданая иконка — запасная (иконка-книга).
      icon: _stringField(raw, 'icon') ?? 'menu_book',
      description: _stringField(raw, 'description') ?? '',
    );
  }
}

/// Базовый класс блока статьи.
///
/// Sealed-иерархия: парсинг ([tryParseBlock]) и рендер (ArticleRenderer)
/// обрабатывают все типы, иного типа в контенте быть не может.
sealed class ArticleBlock {
  const ArticleBlock();
}

/// Блок «абзац текста» (`type: text`).
class ArticleTextBlock extends ArticleBlock {
  const ArticleTextBlock(this.text);

  /// Текст абзаца.
  final String text;
}

/// Блок «подзаголовок внутри статьи» (`type: heading`).
class ArticleHeadingBlock extends ArticleBlock {
  const ArticleHeadingBlock(this.text);

  /// Текст подзаголовка.
  final String text;
}

/// Блок «маркированный список» (`type: list`).
class ArticleListBlock extends ArticleBlock {
  const ArticleListBlock(this.items);

  /// Пункты списка.
  final List<String> items;
}

/// Блок «пример кода» (`type: code`).
class ArticleCodeBlock extends ArticleBlock {
  const ArticleCodeBlock({
    required this.code,
    required this.language,
    required this.output,
    required this.caption,
  });

  /// Исходный код (полный компилируемый файл, ASCII — README).
  final String code;

  /// Код языка (`cpp`, позже `dart`).
  final String language;

  /// Ожидаемый вывод программы без завершающего \n (null — без вывода).
  final String? output;

  /// Подпись под кодом (для примеров с cin — документирование ввода).
  final String? caption;
}

/// Блок «врезка-замечание» (`type: note`).
class ArticleNoteBlock extends ArticleBlock {
  const ArticleNoteBlock(this.text);

  /// Текст замечания.
  final String text;
}

/// Статья справочника: метаданные + блоки в порядке следования.
@immutable
class Article {
  const Article({
    required this.id,
    required this.title,
    required this.summary,
    required this.difficulty,
    required this.tags,
    required this.blocks,
  });

  /// Уникальный во всём справочнике id (`cpp_syn_hello_world` и т.п.).
  final String id;

  /// Заголовок статьи.
  final String title;

  /// Краткое описание (список статей категории, поиск P8).
  final String summary;

  /// Сложность (beginner/intermediate/advanced).
  final Difficulty difficulty;

  /// Теги для поиска P8 (русские, строчными).
  final List<String> tags;

  /// Блоки статьи в порядке следования из JSON.
  final List<ArticleBlock> blocks;

  /// Есть ли в статье пример кода.
  bool get hasCode => blocks.any((b) => b is ArticleCodeBlock);

  /// Разбор статьи из JSON.
  ///
  /// Defensive: null — structurally неверная статья (нет id/title или ни
  /// одного валидного блока) → репозиторий её пропускает. Некорректные
  /// ОТСЛЕЖЕННЫЕ блоки просто выкидываются (см. [tryParseBlock]).
  static Article? tryParse(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final id = _stringField(raw, 'id');
    final title = _stringField(raw, 'title');
    if (id == null || title == null) return null;

    final rawTags = raw['tags'];
    final tags = <String>[
      if (rawTags is List)
        for (final tag in rawTags)
          if (tag is String && tag.isNotEmpty) tag,
    ];

    final rawBlocks = raw['blocks'];
    final blocks = <ArticleBlock>[
      if (rawBlocks is List)
        for (final rawBlock in rawBlocks)
          // Некорректный блок → пропустить (не ронять статью/приложение).
          ?tryParseBlock(rawBlock),
    ];

    // Статья без валидных блоков бесполезна — пропускаем её целиком.
    if (blocks.isEmpty) return null;

    return Article(
      id: id,
      title: title,
      summary: _stringField(raw, 'summary') ?? '',
      difficulty: difficultyFromRaw(raw['difficulty']),
      tags: tags,
      blocks: List.unmodifiable(blocks),
    );
  }
}

/// Разбор одного блока статьи из JSON.
///
/// Defensive-политика: незнакомый тип или отсутствие обязательного поля —
/// возвращается null (блок пропускается), приложение не падает.
ArticleBlock? tryParseBlock(Object? raw) {
  if (raw is! Map<String, dynamic>) return null;
  switch (raw['type']) {
    case 'text':
      final text = _stringField(raw, 'text');
      return text == null ? null : ArticleTextBlock(text);
    case 'heading':
      final text = _stringField(raw, 'text');
      return text == null ? null : ArticleHeadingBlock(text);
    case 'list':
      final items = raw['items'];
      if (items is! List) return null;
      return ArticleListBlock(
        List.unmodifiable([
          for (final item in items)
            if (item is String) item,
        ]),
      );
    case 'code':
      // Кода без исходника не бывает — такой блок отбрасывается.
      final code = _stringField(raw, 'code');
      if (code == null) return null;
      return ArticleCodeBlock(
        // Незаданный язык трактуем как cpp (текущий контент — только cpp).
        language: _stringField(raw, 'language') ?? 'cpp',
        code: code,
        output: _stringField(raw, 'output'),
        caption: _stringField(raw, 'caption'),
      );
    case 'note':
      final text = _stringField(raw, 'text');
      return text == null ? null : ArticleNoteBlock(text);
    default:
      // Незнакомый тип блока — пропускаем с комментарием (контент растёт).
      return null;
  }
}
