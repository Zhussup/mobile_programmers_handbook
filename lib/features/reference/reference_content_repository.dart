import 'article_model.dart';

/// Общий контракт источника контента справочника.
///
/// Локальная реализация — [ArticleRepository] (JSON-ассеты). Удалённая —
/// [RemoteReferenceRepository] (backend API + кэш sqflite). Провайдеры
/// ([ReferenceProvider], [SearchProvider]) зависят только от этого
/// интерфейса, поэтому экраны и тесты не переписываются.
abstract class ReferenceContentRepository {
  /// Контент загружен и разобран.
  bool get isLoaded;

  /// Использован ли кэш из-за сетевой ошибки (для баннера).
  bool get isFromCache => false;

  /// Загрузка контента (ассеты — локально, API — удалённо).
  Future<void> loadFromAssets();

  /// Все категории в порядке отображения.
  List<ReferenceCategory> get categories;

  /// Категория по id (null — неизвестная).
  ReferenceCategory? categoryById(String categoryId);

  /// Статьи категории (простые раньше).
  List<Article> articlesForCategory(String categoryId);

  /// Статья по id по всему справочнику (null — нет такой).
  Article? articleById(String articleId);

  /// Категория, которой принадлежит статья (null — нет такой статьи).
  ReferenceCategory? categoryOfArticle(String articleId);
}
