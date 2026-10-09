import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;

import 'article_model.dart';

/// Репозиторий справочника: загрузка и разбор JSON-ассетов контента
/// (assets/content/reference/).
///
/// Стратегия загрузки (файлы больше не «только 3»): фиксированный список
/// имён [contentFiles] — источник истины по списку файлов и соглашениям
/// это README контента; имена стабильны.
///
/// В контенте — ТОЛЬКО данные справочника (категории/статьи), они
/// иммутабельны; пользовательские данные живут в SQLite (favorites/history).
class ArticleRepository {
  /// Список файлов контента (см. README: имена файлов и category.id).
  ///
  /// Полный план: 5 категорий C++ + ветка Dart/Flutter. Производственный
  /// путь ([loadFromAssets]) спокойно пропускает ещё не существующие
  /// файлы — справочник стартует с того, что уже появилось (P8).
  static const List<String> contentFiles = [
    'cpp_syntax.json',
    'cpp_data_structures.json',
    'cpp_algorithms.json',
    'cpp_stl.json',
    'cpp_oop.json',
    'dart_flutter.json',
  ];

  /// Каталог контента в ассетах (строго UTF-8 — README).
  static const String _assetDir = 'assets/content/reference';

  /// Репозиторий с загрузкой ассетов через rootBundle (production).
  ArticleRepository();

  /// Репозиторий ИЗ ГОТОВЫХ сырых JSON-строк.
  ///
  /// Для тестов: файлы читаются с диска (dart:io) либо подаются inline-
  /// фикстуры — разбор выполняется сразу, без rootBundle.
  factory ArticleRepository.fromRaw(List<String> rawFiles) {
    final repository = ArticleRepository();
    for (final raw in rawFiles) {
      repository._parseFile(raw);
    }
    repository._loaded = true;
    return repository;
  }

  // --- Накопленное (заполняется [_parseFile]) ---
  final List<ReferenceCategory> _categories = [];
  final Map<String, ReferenceCategory> _categoriesById = {};
  final Map<String, Article> _articlesById = {};
  final Map<String, List<Article>> _articlesByCategory = {};
  final Map<String, String> _articleCategoryIds = {};
  bool _loaded = false;

  /// Контент загружен и разобран.
  bool get isLoaded => _loaded;

  /// Загрузка из ассетов (production-путь). Повторный вызов — no-op.
  ///
  /// Отдельный сбойный файл не роняет загрузку остальных (defensive).
  Future<void> loadFromAssets() async {
    if (_loaded) return;
    for (final name in contentFiles) {
      try {
        final raw = await rootBundle.loadString('$_assetDir/$name');
        _parseFile(raw);
      } catch (e) {
        // Отсутствующий/нечитаемый файл пропускаем — справочник остаётся
        // частично доступным, приложение не падает.
        debugPrint('Справочник: файл $name пропущен ($e)');
      }
    }
    _loaded = true;
  }

  /// Разбор одного файла контента: категория + список статей.
  ///
  /// Битый JSON или файл без корректной категории — целиком пропускается.
  void _parseFile(String raw) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (e) {
      debugPrint('Справочник: некорректный JSON, файл пропущен ($e)');
      return;
    }
    if (decoded is! Map<String, dynamic>) {
      debugPrint('Справочник: JSON не объект, файл пропущен');
      return;
    }

    final category = ReferenceCategory.tryParse(decoded['category']);
    if (category == null) {
      debugPrint('Справочник: файл без корректной категории, пропущен');
      return;
    }
    // Дубликат категории — файл полностью пропускаем.
    if (_categoriesById.containsKey(category.id)) {
      debugPrint('Справочник: дубликат категории ${category.id}');
      return;
    }

    final rawArticles = decoded['articles'];
    if (rawArticles is! List) {
      debugPrint('Справочник: в файле ${category.id} нет массива articles');
      return;
    }

    final articles = <Article>[];
    for (final rawArticle in rawArticles) {
      final article = Article.tryParse(rawArticle);
      if (article == null) {
        debugPrint(
          'Справочник: статья пропущена (некорректная) в ${category.id}',
        );
        continue;
      }
      // id статей уникальны во всём справочнике — дубликат отбрасываем.
      if (_articlesById.containsKey(article.id)) {
        debugPrint('Справочник: дубликат id статьи ${article.id} — пропущен');
        continue;
      }
      articles.add(article);
      _articlesById[article.id] = article;
      // Карта «статья → её категория» — для поиска (показ категории рядом
      // с результатом, P8).
      _articleCategoryIds[article.id] = category.id;
    }

    _categoriesById[category.id] = category;
    _categories.add(category);
    _articlesByCategory[category.id] = articles;
  }

  /// Все категории (порядок следования файлов контента).
  List<ReferenceCategory> get categories => List.unmodifiable(_categories);

  /// Категория по id (null — неизвестная категория; не падать, а показать
  /// экран-заглушку).
  ReferenceCategory? categoryById(String categoryId) =>
      _categoriesById[categoryId];

  /// Статьи категории, отсортированные по сложности (простые раньше).
  List<Article> articlesForCategory(String categoryId) {
    final list = _articlesByCategory[categoryId];
    if (list == null) return const [];
    final sorted = List<Article>.of(list);
    sorted.sort(
      (a, b) => a.difficulty.sortOrder.compareTo(b.difficulty.sortOrder),
    );
    return List.unmodifiable(sorted);
  }

  /// Статья по id по всему справочнику (null — нет такой статьи).
  Article? articleById(String articleId) => _articlesById[articleId];

  /// Категория, которой принадлежит статья (null — нет такой статьи).
  ///
  /// Используется поиском (P8): результат поиска показывает категорию
  /// рядом с заголовком (README: category.id — идентификаторы категорий).
  ReferenceCategory? categoryOfArticle(String articleId) {
    final categoryId = _articleCategoryIds[articleId];
    if (categoryId == null) return null;
    return _categoriesById[categoryId];
  }
}
