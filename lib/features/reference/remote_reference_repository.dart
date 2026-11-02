import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import 'article_model.dart';
import 'reference_cache.dart';
import 'reference_content_repository.dart';

/// Удалённый репозиторий справочника (КР_2_2, К8–К9).
///
/// Загружает категории (`GET /categories`) и статьи (`GET /articles`) через
/// backend API, разбирает их теми же моделями, что и локальный
/// [ArticleRepository], и сохраняет успешный ответ в sqflite-кэш.
///
/// При сетевой ошибке/таймауте отдаёт последний сохранённый снимок и
/// помечает [isFromCache] — экран показывает баннер «Нет связи».
/// Остальные ошибки (401/403/5xx) пробрасываются наверх: сессией и
/// снекбарами управляет приложение.
class RemoteReferenceRepository implements ReferenceContentRepository {
  /// Репозиторий поверх API-клиента и кэша sqflite.
  RemoteReferenceRepository({required this._apiClient, required this._cache});

  final ApiClient _apiClient;
  final ReferenceCache _cache;

  final List<ReferenceCategory> _categories = [];
  final Map<String, ReferenceCategory> _categoriesById = {};
  final Map<String, Article> _articlesById = {};
  final Map<String, List<Article>> _articlesByCategory = {};
  final Map<String, String> _articleCategoryIds = {};

  List<Map<String, dynamic>> _rawCategories = const [];
  List<Map<String, dynamic>> _rawArticles = const [];
  bool _loaded = false;
  bool _fromCache = false;

  @override
  bool get isLoaded => _loaded;

  @override
  bool get isFromCache => _fromCache;

  /// Загрузка контента из API; при сетевой ошибке — из кэша.
  ///
  /// Повторный вызов после успешной загрузки — no-op (контракт провайдера).
  @override
  Future<void> loadFromAssets() async {
    if (_loaded) return;

    try {
      final categoriesData = await _apiClient.get('/categories');
      final articlesData = await _apiClient.get('/articles');

      _rawCategories = _asMaps(categoriesData);
      _rawArticles = _asMaps(articlesData);

      // Кэш вторичен: сбой записи не должен ломать показ контента.
      try {
        await _cache.save(categories: _rawCategories, articles: _rawArticles);
      } catch (e) {
        debugPrint('Кэш справочника: не удалось сохранить ($e)');
      }

      _rebuild();
      _fromCache = false;
      _loaded = true;
    } on ApiException catch (e) {
      // Кэш спасает только от отсутствия связи/таймаута.
      if (!e.isNetwork) rethrow;

      final cached = await _cache.read();
      if (cached == null || cached.categories.isEmpty) rethrow;

      _rawCategories = cached.categories;
      _rawArticles = cached.articles;
      _rebuild();
      _fromCache = true;
      _loaded = true;
    }
  }

  /// Запрос статей с серверными фильтрами (контракт API).
  ///
  /// [q] — поиск по заголовку/описанию/тегам, [categoryId] — категория,
  /// [difficulty] — сложность. Основной экран справочника загружает полный
  /// список один раз, а этот метод доступен для точечных запросов.
  Future<List<Article>> fetchArticles({
    String? q,
    String? categoryId,
    Difficulty? difficulty,
  }) async {
    final data = await _apiClient.get(
      '/articles',
      query: {'q': q, 'category': categoryId, 'difficulty': difficulty?.name},
    );
    return [
      for (final raw in _asMaps(data))
        if (Article.tryParse(_normalizeArticle(raw)) case final Article article)
          article,
    ];
  }

  @override
  List<ReferenceCategory> get categories => List.unmodifiable(_categories);

  @override
  ReferenceCategory? categoryById(String categoryId) =>
      _categoriesById[categoryId];

  @override
  List<Article> articlesForCategory(String categoryId) {
    final list = _articlesByCategory[categoryId];
    if (list == null) return const [];
    final sorted = List<Article>.of(list);
    sorted.sort(
      (a, b) => a.difficulty.sortOrder.compareTo(b.difficulty.sortOrder),
    );
    return List.unmodifiable(sorted);
  }

  @override
  Article? articleById(String articleId) => _articlesById[articleId];

  @override
  ReferenceCategory? categoryOfArticle(String articleId) {
    final categoryId = _articleCategoryIds[articleId];
    if (categoryId == null) return null;
    return _categoriesById[categoryId];
  }

  /// Пересборка in-memory индексов из сырых JSON-объектов.
  void _rebuild() {
    _categories.clear();
    _categoriesById.clear();
    _articlesById.clear();
    _articlesByCategory.clear();
    _articleCategoryIds.clear();

    for (final raw in _rawCategories) {
      final category = ReferenceCategory.tryParse(raw);
      if (category == null || _categoriesById.containsKey(category.id)) {
        continue;
      }
      _categories.add(category);
      _categoriesById[category.id] = category;
    }

    for (final raw in _rawArticles) {
      final normalized = _normalizeArticle(raw);
      final article = Article.tryParse(normalized);
      if (article == null || _articlesById.containsKey(article.id)) continue;

      final categoryId = _categoryIdOf(normalized);
      _articlesById[article.id] = article;
      _articlesByCategory.putIfAbsent(categoryId, () => []).add(article);
      _articleCategoryIds[article.id] = categoryId;
    }
  }

  /// Нормализация статьи API: `tags`/`blocks` могут прийти массивом или
  /// JSON-строкой; категория — в `category_id` либо вложенном `category`.
  static Map<String, dynamic> _normalizeArticle(Map<String, dynamic> raw) {
    final result = Map<String, dynamic>.of(raw);

    final tags = result['tags'];
    if (tags is String) {
      result['tags'] = _decodeList(tags);
    }
    final blocks = result['blocks'] ?? result['blocks_json'];
    if (blocks is String) {
      result['blocks'] = _decodeList(blocks);
    }

    if (_categoryIdOf(result).isEmpty) {
      final nested = result['category'];
      if (nested is Map && nested['id'] is String) {
        result['category_id'] = nested['id'];
      }
    }
    return result;
  }

  /// id категории статьи (пустая строка — не определена).
  static String _categoryIdOf(Map<String, dynamic> article) {
    final direct = article['category_id'] ?? article['categoryId'];
    if (direct is String && direct.isNotEmpty) return direct;
    final nested = article['category'];
    if (nested is Map) {
      final id = nested['id'];
      if (id is String) return id;
    }
    return '';
  }

  /// Декодирование JSON-строки в список (ошибка → пустой список).
  static List<dynamic> _decodeList(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded : const [];
    } on FormatException {
      return const [];
    }
  }

  /// Ответ API → список JSON-объектов.
  ///
  /// Поддерживает как массив в `data`, так и объект с массивом внутри
  /// (`items`/`categories`/`articles`) — backend может расширяться.
  static List<Map<String, dynamic>> _asMaps(Object? data) {
    if (data is List) {
      return [
        for (final item in data)
          if (item is Map<String, dynamic>) item,
      ];
    }
    if (data is Map<String, dynamic>) {
      for (final key in const ['items', 'categories', 'articles']) {
        final nested = data[key];
        if (nested is List) return _asMaps(nested);
      }
      return [data];
    }
    return const [];
  }
}
