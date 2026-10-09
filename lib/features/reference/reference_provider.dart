import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;

import 'article_model.dart';
import 'article_repository.dart';

/// Состояние загрузки справочника.
enum ReferenceStatus { loading, ready, error }

/// Провайдер справочника (P6): категории, статьи категории, статья по id.
///
/// Главное правило (подводный камень №8 из плана): в маршрутах и extras
/// передаются ТОЛЬКО id — все данные экраны получают отсюда, из репозитория
/// (state restore не ломается).
class ReferenceProvider extends ChangeNotifier {
  /// Провайдер поверх репозитория контента.
  ReferenceProvider({required this.repository});

  /// Репозиторий справочника (JSON-контент).
  final ArticleRepository repository;

  ReferenceStatus _status = ReferenceStatus.loading;
  bool _loadStarted = false;

  /// Состояние загрузки для экранов (спиннер / данные / заглушка).
  ReferenceStatus get status => _status;

  /// Русское сообщение об ошибке (для экрана-заглушки).
  String get errorMessage =>
      'Не удалось загрузить содержимое справочника. '
      'Соберите приложение заново и попробуйте снова.';

  /// Загрузка контента (вызывается один раз при создании провайдера).
  ///
  /// Повторный вызов — no-op (защита от гонки параллельных load).
  Future<void> load() async {
    if (_loadStarted) return;
    _loadStarted = true;

    if (repository.isLoaded) {
      // Репозиторий уже разобрал контент (тестовый путь — из сырых строк).
      _status = ReferenceStatus.ready;
      notifyListeners();
      return;
    }

    try {
      await repository.loadFromAssets();
      _status = ReferenceStatus.ready;
    } catch (e) {
      debugPrint('Справочник: ошибка загрузки ($e)');
      _status = ReferenceStatus.error;
    }
    notifyListeners();
  }

  /// Категории справочника (пусто до готовности — экраны показывают спиннер).
  List<ReferenceCategory> get categories => repository.categories;

  /// Категория по id (null — неизвестная категория маршрута).
  ReferenceCategory? categoryById(String categoryId) =>
      repository.categoryById(categoryId);

  /// Статьи категории (отсортированы по сложности — простые раньше).
  List<Article> articlesForCategory(String categoryId) =>
      repository.articlesForCategory(categoryId);

  /// Статья по id (null — неизвестная статья маршрута).
  Article? articleById(String articleId) => repository.articleById(articleId);

  /// Подпись количества статей («1 статья», «3 статьи», «5 статей») —
  /// русская плюрализация для карточек категорий.
  static String articlesLabel(int count) {
    final last = count % 10;
    final two = count % 100;
    if (two >= 11 && two <= 19) return '$count статей';
    if (last == 1) return '$count статья';
    if (last >= 2 && last <= 4) return '$count статьи';
    return '$count статей';
  }
}
