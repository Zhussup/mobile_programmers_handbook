import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/widgets/article_renderer.dart';
import '../../../core/widgets/empty_state.dart';
import '../reference_provider.dart';
import '../widgets/difficulty_badge.dart';

/// Экран статьи `/article/:id` (P6): заголовок, краткое описание, все блоки
/// в порядке следования (ArticleRenderer — text/heading/list/code/note).
///
/// Данные достаются по id ИЗ РЕПОЗИТОРИЯ (в маршруте — только id, подводный
/// камень №8 из плана); неизвестный id → экран-заглушка (EmptyState).
class ArticleScreen extends StatelessWidget {
  const ArticleScreen({super.key, required this.articleId});

  /// Строковый id статьи из маршрута.
  final String articleId;

  @override
  Widget build(BuildContext context) {
    final reference = context.watch<ReferenceProvider>();

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

    final article = reference.articleById(articleId);
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

    // --- Статья найдена: заголовок, описание, блоки в порядке следования ---
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(article.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
          children: [
            // Сложность + теги (tags — для поиска P8).
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
