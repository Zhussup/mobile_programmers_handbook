import 'history_repository.dart';

/// Контракт источника истории просмотров (локально — sqflite, удалённо — API).
abstract class HistoryDataSource {
  /// Использован ли кэш из-за сетевой ошибки.
  bool get servedFromCache => false;

  /// Записать просмотр статьи (без дублей, свежее время).
  Future<void> record(int userId, String articleId);

  /// История пользователя (свежие сверху, лимит топ-20).
  Future<List<HistoryRecordRaw>> listTop(int userId);

  /// Очистить историю пользователя.
  Future<void> clear(int userId);
}
