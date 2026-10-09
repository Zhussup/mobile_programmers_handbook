import 'package:flutter/foundation.dart';

import '../auth/session_provider.dart';
import 'article_model.dart';
import 'article_repository.dart';
import 'favorites_repository.dart';
import 'user_scoped_provider.dart';

/// Модель списка «Избранное»: строка БД + контент статьи.
@immutable
class FavoriteEntry {
  const FavoriteEntry({required this.article, required this.createdAt});

  /// Статья (сшита с JSON-контентом по articleId).
  final Article article;

  /// Когда добавлена в избранное.
  final DateTime createdAt;
}

/// Провайдер избранного (P9): heart-состояние по статьям + список для экрана.
///
/// user-scoped: подписан на [SessionProvider] — сменился пользователь →
/// полная перезагрузка данных; гость → пустое состояние (в самой БД данные
/// хранятся под своим user_id, чужие не читаются и не пишутся).
class FavoritesProvider extends UserScopedProvider {
  /// Провайдер над двумя репозиториями: SQLite-избранное + JSON-контент.
  FavoritesProvider({
    required this.articles,
    required this.repository,
    required SessionProvider session,
  }) : super(session);

  /// Репозиторий контента (join избранного со статьями).
  final ArticleRepository articles;

  /// Репозиторий избранного (SQLite).
  final FavoritesRepository repository;

  /// Список избранного (сшиты с контентом; без «мёртвых» статей).
  List<FavoriteEntry> _entries = const [];
  Set<String> _ids = const {};
  Map<String, DateTime> _createdAt = const {};
  bool _loading = true;

  /// Загружается ли сейчас список (первая загрузка).
  bool get loading => _loading;

  /// Список избранного пользователя (свежие добавления раньше).
  List<FavoriteEntry> get entries => List.unmodifiable(_entries);

  /// В избранном ли статья (для сердечка в AppBar статьи).
  bool isFavorite(String articleId) => _ids.contains(articleId);

  @override
  Future<void> loadForUser(int? userId, int token) async {
    if (userId == null) {
      // Гость: состояние пустое (данные прошлого пользователя не видны).
      _entries = const [];
      _ids = const {};
      _createdAt = const {};
      _loading = false;
      return;
    }
    _loading = true;
    try {
      final records = await repository.listForUser(userId);
      if (!isActual(token)) return; // пользователь сменился за время запроса
      _ids = {for (final record in records) record.articleId};
      _createdAt = {
        for (final record in records) record.articleId: record.createdAt,
      };
      _entries = _buildEntries();
    } on Exception {
      if (!isActual(token)) return;
      // Сбой БД не роняет приложение: пустое состояние (актуальную
      // перезагрузку, запущенную позже, никто не перетирает).
      _entries = const [];
      _ids = const {};
      _createdAt = const {};
    } finally {
      _loading = false;
    }
  }

  /// Переключение статьи в избранном текущего пользователя.
  ///
  /// Возвращает состояние ПОСЛЕ переключения: true — добавлено, false —
  /// удалено (снекбар «Добавлено/Удалено из избранного»). Ошибка БД
  /// пробрасывается — UI гасит её в снекбар ошибки.
  Future<bool> toggle(String articleId) async {
    final userId = currentUserId;
    // Гость (приватные страницы под guard'ом) — ничего не делаем.
    if (userId == null) return false;
    final token = beginLoad();
    final added = await repository.toggle(userId, articleId);
    // За время записи ответ мог устареть — не перетирать актуальные данные
    // (перезагрузка для нового пользователя уже запущена).
    if (!isActual(token)) return added;
    if (added) {
      _ids = {..._ids, articleId};
      _createdAt = {..._createdAt, articleId: DateTime.now()};
    } else {
      final nextIds = {..._ids}..remove(articleId);
      _ids = nextIds;
      final nextAt = {..._createdAt}..remove(articleId);
      _createdAt = nextAt;
    }
    _entries = _buildEntries();
    return added;
  }

  /// Пересборка списка из id + контента (без перечитывания БД), свежие
  /// добавления раньше. «Мёртвые» id (статья пропала из контента) в список
  /// не попадают, но остаются в _ids — сердечко отражает реальное БД.
  List<FavoriteEntry> _buildEntries() {
    final result = <FavoriteEntry>[];
    for (final id in _ids) {
      final createdAt = _createdAt[id];
      final article = articles.articleById(id);
      if (createdAt == null || article == null) continue;
      result.add(FavoriteEntry(article: article, createdAt: createdAt));
    }
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }
}
