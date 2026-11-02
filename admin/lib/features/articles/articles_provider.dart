import 'dart:convert';

import 'package:flutter/foundation.dart' hide Category;

import '../../core/models/article.dart';
import '../../core/models/category.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/json_utils.dart';

/// Управление контентом через `/api/admin/articles` и `/api/admin/categories`.
class ArticlesProvider extends ChangeNotifier {
  ArticlesProvider({required this.api});

  final ApiClient api;

  List<Article> _articles = <Article>[];
  List<Category> _categories = <Category>[];
  bool _loading = false;
  bool _categoriesLoading = false;
  bool _saving = false;
  String? _errorMessage;
  String? _categoryFilter;
  bool? _publishedFilter;
  int _requestId = 0;

  List<Article> get articles => List.unmodifiable(_articles);
  List<Category> get categories => List.unmodifiable(_categories);
  bool get loading => _loading;
  bool get categoriesLoading => _categoriesLoading;
  bool get saving => _saving;
  String? get errorMessage => _errorMessage;
  String? get categoryFilter => _categoryFilter;
  bool? get publishedFilter => _publishedFilter;

  String categoryTitle(String categoryId) {
    for (final category in _categories) {
      if (category.id == categoryId) return category.title;
    }
    for (final article in _articles) {
      if (article.categoryId == categoryId &&
          article.categoryTitle.isNotEmpty) {
        return article.categoryTitle;
      }
    }
    return categoryId.isEmpty ? '—' : categoryId;
  }

  /// Загружает статьи с учётом фильтров.
  Future<void> load() async {
    final requestId = ++_requestId;
    _loading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final data = await api.get(
        '/admin/articles',
        query: <String, dynamic>{
          'category': _categoryFilter,
          'published': _publishedFilter == null
              ? null
              : (_publishedFilter! ? 'true' : 'false'),
        },
      );
      if (requestId != _requestId) return;
      _articles = asJsonList(
        data,
        keys: const ['items', 'articles'],
      ).map(Article.fromJson).toList();
    } on ApiException catch (error) {
      if (requestId != _requestId) return;
      _errorMessage = error.message;
    } finally {
      if (requestId == _requestId) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  /// Загружает категории для фильтра и формы статьи.
  Future<void> loadCategories() async {
    _categoriesLoading = true;
    notifyListeners();
    try {
      final data = await api.get('/admin/categories');
      _categories = asJsonList(
        data,
        keys: const ['items', 'categories'],
      ).map(Category.fromJson).toList();
    } on ApiException catch (error) {
      _errorMessage ??= error.message;
    } finally {
      _categoriesLoading = false;
      notifyListeners();
    }
  }

  /// Применяет фильтры и перезагружает список.
  Future<void> applyFilters({String? categoryId, bool? published}) async {
    _categoryFilter = categoryId;
    _publishedFilter = published;
    await load();
  }

  /// Ищет статью в загруженном списке; при необходимости догружает список.
  Future<Article?> findArticle(String id) async {
    if (id.isEmpty || id == 'new') return null;
    var found = _findById(id);
    if (found == null) {
      await load();
      found = _findById(id);
    }
    return found;
  }

  Article? _findById(String id) {
    for (final article in _articles) {
      if (article.id == id) return article;
    }
    return null;
  }

  /// Создаёт (`id == null`) или обновляет статью.
  ///
  /// После сохранения при необходимости вызывает отдельный эндпоинт
  /// публикации, как требует контракт API.
  Future<Article> saveArticle({
    String? id,
    required String title,
    required String summary,
    required String categoryId,
    required String difficulty,
    required List<String> tags,
    required String blocksJson,
    required bool published,
  }) async {
    _saving = true;
    notifyListeners();

    try {
      final body = <String, dynamic>{
        'category_id': categoryId,
        'title': title.trim(),
        'summary': summary.trim(),
        'difficulty': difficulty,
        'tags': tags,
        'blocks_json': blocksJson,
        'blocks': _decodeBlocks(blocksJson),
      };

      Article saved;
      if (id == null || id.isEmpty) {
        final data = await api.post('/admin/articles', body: body);
        saved = _articleFromResponse(
          data,
          fallback: Article(
            id: asString(asJsonMap(data)['id']),
            categoryId: categoryId,
            title: title.trim(),
            summary: summary.trim(),
            difficulty: difficulty,
            tags: tags,
            blocksJson: blocksJson,
            isPublished: false,
          ),
        );
        _articles = <Article>[saved, ..._articles];
      } else {
        final current = _findById(id);
        final base =
            (current ??
                    Article(
                      id: id,
                      categoryId: categoryId,
                      title: title.trim(),
                      summary: summary.trim(),
                      difficulty: difficulty,
                      tags: tags,
                      blocksJson: blocksJson,
                      isPublished: published,
                    ))
                .copyWith(
                  categoryId: categoryId,
                  title: title.trim(),
                  summary: summary.trim(),
                  difficulty: difficulty,
                  tags: tags,
                  blocksJson: blocksJson,
                );
        final data = await api.put('/admin/articles/$id', body: body);
        saved = _mergeArticle(base, data);
        _articles = _articles
            .map((item) => item.id == id ? saved : item)
            .toList();
      }

      if (saved.isPublished != published) {
        saved = await setPublished(saved, published);
      } else {
        notifyListeners();
      }
      return saved;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  /// Публикация/снятие с публикации.
  Future<Article> setPublished(Article article, bool published) async {
    final data = await api.patch(
      '/admin/articles/${article.id}/publish',
      body: <String, dynamic>{'published': published},
    );
    final updated = _mergeArticle(article, data, fallbackPublished: published);
    _replace(updated);
    return updated;
  }

  /// Удаление статьи (в UI — с подтверждением).
  Future<void> deleteArticle(Article article) async {
    await api.delete('/admin/articles/${article.id}');
    _articles = _articles.where((item) => item.id != article.id).toList();
    notifyListeners();
  }

  Article _articleFromResponse(dynamic data, {required Article fallback}) {
    final map = asJsonMap(data);
    if (map.isEmpty) return fallback;
    final parsed = Article.fromJson(map);
    if (parsed.id.isEmpty) {
      return fallback.copyWith(
        title: map.containsKey('title') ? parsed.title : fallback.title,
        isPublished: parsed.isPublished,
      );
    }
    return parsed;
  }

  Article _mergeArticle(Article base, dynamic data, {bool? fallbackPublished}) {
    final map = asJsonMap(data);
    if (map.isEmpty) {
      return fallbackPublished == null
          ? base
          : base.copyWith(isPublished: fallbackPublished);
    }
    if (map.containsKey('title')) {
      return Article.fromJson(map);
    }
    final hasPublished =
        map.containsKey('is_published') ||
        map.containsKey('isPublished') ||
        map.containsKey('published');
    return base.copyWith(
      isPublished: hasPublished
          ? asBool(
              map['is_published'] ?? map['isPublished'] ?? map['published'],
            )
          : fallbackPublished,
    );
  }

  void _replace(Article updated) {
    _articles = _articles
        .map((item) => item.id == updated.id ? updated : item)
        .toList();
    notifyListeners();
  }

  List<dynamic> _decodeBlocks(String blocksJson) {
    try {
      final decoded = jsonDecode(blocksJson);
      return decoded is List ? decoded : const <dynamic>[];
    } catch (_) {
      return const <dynamic>[];
    }
  }
}
