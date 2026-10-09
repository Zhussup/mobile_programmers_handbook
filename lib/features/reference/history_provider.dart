import 'package:flutter/foundation.dart';

import '../../../core/constants/app_constants.dart';
import '../auth/session_provider.dart';
import 'article_model.dart';
import 'article_repository.dart';
import 'history_repository.dart';
import 'user_scoped_provider.dart';

/// Модель «Недавно смотрели» (home) и экрана истории: статья + время.
@immutable
class HistoryEntry {
  const HistoryEntry({required this.article, required this.viewedAt});

  /// Статья (сшита с JSON-контентом по articleId).
  final Article article;

  /// Когда статья открыта.
  final DateTime viewedAt;
}

/// Провайдер истории просмотров (P9): «недавно смотрели» на home, экран
/// `/history` с кнопкой «Очистить».
///
/// user-scoped: подписан на [SessionProvider] — смена пользователя → полная
/// перезагрузка, гость → пустое состояние (данные в БД лежат под своим
/// user_id, чужие не видны).
class HistoryProvider extends UserScopedProvider {
  /// Провайдер над двумя репозиториями: SQLite-история + JSON-контент.
  HistoryProvider({
    required this.articles,
    required this.repository,
    required SessionProvider session,
  }) : super(session);

  /// Репозиторий контента (join истории со статьями).
  final ArticleRepository articles;

  /// Репозиторий истории (SQLite).
  final HistoryRepository repository;

  /// Топ просмотренных статей (свежие раньше; репозиторий уже отсортировал
  /// и подрезал до топ-20 — JOIN с контентом только отсюда).
  List<HistoryEntry> _entries = const [];
  bool _loading = true;

  /// Загружается ли сейчас список (первая загрузка).
  bool get loading => _loading;

  /// Топ-20 просмотров пользователя (свежие раньше).
  List<HistoryEntry> get entries => List.unmodifiable(_entries);

  /// Первые [count] записей — секция «Продолжить» на home.
  List<HistoryEntry> recent({int count = 5}) => _entries.take(count).toList();

  @override
  Future<void> loadForUser(int? userId, int token) async {
    if (userId == null) {
      // Гость: состояние пустое (данные прошлого пользователя не видны).
      _entries = const [];
      _loading = false;
      return;
    }
    _loading = true;
    try {
      final records = await repository.listTop(userId);
      if (!isActual(token)) return; // пользователь сменился за время запроса
      _entries = records
          .where((record) => articles.articleById(record.articleId) != null)
          .map(
            (record) => HistoryEntry(
              article: articles.articleById(record.articleId)!,
              viewedAt: record.viewedAt,
            ),
          )
          .toList();
    } on Exception {
      if (!isActual(token)) return;
      // Сбой БД не роняет приложение: пустое состояние.
      _entries = const [];
    } finally {
      _loading = false;
    }
  }

  /// Запись просмотра статьи (статья ОДИН раз на появление экрана — см.
  /// ArticleScreen; сам репозиторий держит не больше строки на статью и
  /// подрезает топ-20).
  ///
  /// Ошибка БД НЕ пробрасывается (история не критична для чтения статьи),
  /// только debug-лог.
  Future<void> record(String articleId) async {
    final userId = currentUserId;
    if (userId == null) return; // гость
    final token = beginLoad();
    try {
      await repository.record(userId, articleId);
      if (!isActual(token)) return;
      _applyLocalRecord(articleId);
    } on Exception catch (e) {
      debugPrint('История: запись не удалась ($e)');
    }
  }

  /// Локальное обновление топа без перечитывания БД: статья переносится
  /// в начало, хвост сверх топ-20 отбрасывается.
  void _applyLocalRecord(String articleId) {
    final article = articles.articleById(articleId);
    if (article == null) return;
    final entry = HistoryEntry(article: article, viewedAt: DateTime.now());
    final others = _entries.where((e) => e.article.id != articleId).toList();
    _entries = [entry, ...others].take(AppConstants.historyLimit).toList();
  }

  /// Очистка истории текущего пользователя (кнопка «Очистить»).
  ///
  /// Ошибка БД не пробрасывается — экран покажет снекбар по факту успеха
  /// в UI-обработчике.
  Future<void> clear() async {
    final userId = currentUserId;
    if (userId == null) return;
    final token = beginLoad();
    try {
      await repository.clear(userId);
      if (!isActual(token)) return;
      _entries = const [];
    } on Exception catch (e) {
      debugPrint('История: очистка не удалась ($e)');
      rethrow;
    }
  }
}
