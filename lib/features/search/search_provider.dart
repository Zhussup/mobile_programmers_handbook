import 'package:flutter/foundation.dart';

import '../reference/article_model.dart';
import '../reference/article_repository.dart';

/// Результат поиска: статья + её категория (показываем категорию рядом с
/// результатом — «удобно видеть, откуда статья»).
@immutable
class SearchResult {
  const SearchResult({required this.article, required this.category});

  /// Найденная статья.
  final Article article;

  /// Категория, в которой лежит статья.
  final ReferenceCategory category;
}

/// Провайдер поиска (P8): мгновенная фильтрация справочника по запросу и
/// сложности.
///
/// Стратегия «мгновенности»: контент уже в памяти ([ArticleRepository] —
/// JSON-ассеты разобраны при старте), фильтрация синхронна и не блокирует
/// UI — debounce не нужен (в справочнике десятки статей). Реакция — прямо
/// в onChanged поля ввода: каждое изменение запроса сразу пересчитывает
/// список.
///
/// Поиск идёт ПО title, summary И tags (README: теги — русские, строчными,
/// плюс латинские термины), без учёта регистра.
class SearchProvider extends ChangeNotifier {
  /// Провайдер поиска поверх репозитория контента.
  SearchProvider(this.articles);

  /// Репозиторий справочника.
  final ArticleRepository articles;

  /// Текущий запрос (как в поле ввода).
  String query = '';

  /// Выбранная сложность (null — «Все»).
  Difficulty? difficulty;

  /// Обновить запрос из поля ввода (каждое изменение — мгновенный пересчёт).
  void setQuery(String value) {
    if (query == value) return;
    query = value;
    notifyListeners();
  }

  /// Выбрать фильтр сложности; повторный тап по выбранному чипу — «Все».
  void setDifficulty(Difficulty? value) {
    if (difficulty == value) return;
    difficulty = value;
    notifyListeners();
  }

  /// Сброс поиска (clean-состояние: «Все» + пустой запрос).
  void reset() {
    query = '';
    difficulty = null;
    notifyListeners();
  }

  /// Результаты поиска под текущие запрос/фильтр.
  ///
  /// Порядок: по категориям (порядок файлов контента), внутри категории —
  /// от простых к сложным ([ArticleRepository.articlesForCategory]).
  List<SearchResult> get results {
    final normalized = query.trim().toLowerCase();
    return [
      for (final category in articles.categories)
        for (final article in articles.articlesForCategory(category.id))
          if (_matches(article, normalized))
            SearchResult(article: article, category: category),
    ];
  }

  /// Статья подходит под текущие фильтры?
  bool _matches(Article article, String normalizedQuery) {
    if (difficulty != null && article.difficulty != difficulty) return false;
    if (normalizedQuery.isEmpty) return true;
    return _matchesQuery(article, normalizedQuery);
  }

  /// Совпадение по title / summary / tags (без учёта регистра).
  static bool _matchesQuery(Article article, String query) {
    if (article.title.toLowerCase().contains(query)) return true;
    if (article.summary.toLowerCase().contains(query)) return true;
    for (final tag in article.tags) {
      if (tag.toLowerCase().contains(query)) return true;
    }
    return false;
  }
}
