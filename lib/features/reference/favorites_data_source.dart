import 'favorites_repository.dart';

/// Контракт источника избранного (локально — sqflite, удалённо — API).
abstract class FavoritesDataSource {
  /// Использован ли кэш из-за сетевой ошибки.
  bool get servedFromCache => false;

  /// В избранном ли статья у пользователя.
  Future<bool> isFavorite(int userId, String articleId);

  /// Переключение статьи в избранном; результат после операции
  /// (true — добавлено, false — удалено).
  Future<bool> toggle(int userId, String articleId);

  /// Список избранного пользователя (свежие раньше).
  Future<List<FavoriteRecord>> listForUser(int userId);
}
