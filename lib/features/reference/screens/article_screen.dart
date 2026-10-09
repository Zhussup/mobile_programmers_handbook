import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/article_renderer.dart';
import '../../../core/widgets/empty_state.dart';
import '../favorites_provider.dart';
import '../history_provider.dart';
import '../reference_provider.dart';
import '../widgets/difficulty_badge.dart';

/// Экран статьи `/article/:id` (P6, дополнен P9): заголовок, краткое
/// описание, все блоки в порядке следования (ArticleRenderer —
/// text/heading/list/code/note), сердечко «в избранное» + автозапись в
/// историю.
///
/// Данные достаются по id ИЗ РЕПОЗИТОРИЯ (в маршруте — только id, подводный
/// камень №8 из плана); неизвестный id → экран-заглушка (EmptyState).
class ArticleScreen extends StatefulWidget {
  const ArticleScreen({super.key, required this.articleId});

  /// Строковый id статьи из маршрута.
  final String articleId;

  @override
  State<ArticleScreen> createState() => _ArticleScreenState();
}

class _ArticleScreenState extends State<ArticleScreen> {
  /// Запись в историю — ОДНО событие на появление экрана (не при каждом
  /// rebuild, не при каждом pump).
  bool _historyRecorded = false;

  @override
  void initState() {
    super.initState();
    // Постфрейм, а не initState: запись в историю трогает провайдеры
    // (notifyListeners), которые нельзя будить во время build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _recordHistoryOnce());
  }

  /// Записать просмотр в историю ровно один раз за жизнь экрана.
  Future<void> _recordHistoryOnce() async {
    if (!mounted || _historyRecorded) return;
    final reference = context.read<ReferenceProvider>();
    final article = reference.articleById(widget.articleId);
    if (article == null) return; // неизвестная статья — история не пишется
    _historyRecorded = true;
    await context.read<HistoryProvider>().record(article.id);
  }

  /// Переключение избранного сердечком (снекбар — подводный камень №6).
  Future<void> _toggleFavorite(BuildContext context, String articleId) async {
    try {
      final added = await context.read<FavoritesProvider>().toggle(articleId);
      if (!(mounted && context.mounted)) return;
      // По требованию плана: фидбек всегда наблюдаем, а не «молчание».
      showAppSnackBar(
        context,
        added
            ? AppSnackBarMessages.favoriteAdded
            : AppSnackBarMessages.favoriteRemoved,
      );
    } on Exception {
      if (!(mounted && context.mounted)) return;
      showErrorSnackBar(context, 'Не удалось обновить избранное');
    }
  }

  @override
  Widget build(BuildContext context) {
    final reference = context.watch<ReferenceProvider>();
    final favorites = context.watch<FavoritesProvider>();

    // --- Загрузка: спиннер ---
    if (reference.status == ReferenceStatus.loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Справочник')),
        body: const Center(
          key: Key('reference-loading'),
          child: CircularProgressIndicator(),
        ),
      );
    }

    final article = reference.articleById(widget.articleId);
    if (article == null) {
      // --- Неизвестная статья: экран-заглушка (не падение) ---
      return Scaffold(
        appBar: AppBar(title: const Text('Не найдено')),
        body: EmptyState(
          key: const Key('article-not-found'),
          title: 'Статья не найдена',
          message: 'Возможно, ссылка устарела.',
          icon: Icons.search_off,
        ),
      );
    }

    // --- Статья найдена: заголовок, описание, сердечко, блоки ---
    final scheme = Theme.of(context).colorScheme;
    final isFavorite = favorites.isFavorite(article.id);

    return Scaffold(
      appBar: AppBar(
        title: Text(article.title),
        actions: [
          // Сердечко: filled — в избранном, outline — нет (P9).
          IconButton(
            key: const Key('article-favorite'),
            tooltip: isFavorite ? 'Убрать из избранного' : 'В избранное',
            onPressed: () => _toggleFavorite(context, article.id),
            icon: Icon(
              isFavorite ? Icons.favorite : Icons.favorite_border,
              color: isFavorite ? scheme.error : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
          children: [
            // Сложность + теги (tags — для поиска P8); история пишется
            // в postFrame initState'а.
            Row(
              children: [
                DifficultyBadge(difficulty: article.difficulty),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    article.tags.map((t) => '#$t').join('  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              article.summary,
              style: const TextStyle(fontSize: 15, height: 1.45),
            ),
            const SizedBox(height: 20),
            ArticleRenderer(blocks: article.blocks),
          ],
        ),
      ),
    );
  }
}
