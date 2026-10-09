import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/empty_state.dart';
import '../reference_provider.dart';
import '../widgets/difficulty_badge.dart';

/// Список статей категории `/reference/:categoryId` (P6).
///
/// Категория достаётся по id ИЗ РЕПОЗИТОРИЯ (в маршруте — только id,
/// подводный камень №8 из плана); статьи отсортированы по сложности:
/// простые раньше. Неизвестная категория → экран-заглушка (EmptyState),
/// не падение.
class CategoryArticlesScreen extends StatelessWidget {
  const CategoryArticlesScreen({super.key, required this.categoryId});

  /// Строковый id категории из маршрута.
  final String categoryId;

  @override
  Widget build(BuildContext context) {
    final reference = context.watch<ReferenceProvider>();
    final scheme = Theme.of(context).colorScheme;

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

    // --- Неизвестная категория: экран-заглушка (не падение) ---
    final category = reference.categoryById(categoryId);
    final articles = reference.articlesForCategory(categoryId);
    if (category == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Справочник')),
        body: EmptyState(
          key: const Key('category-not-found'),
          title: 'Категория не найдена',
          message: 'Проверьте ссылку или вернитесь назад.',
          icon: Icons.search_off,
        ),
      );
    }

    // --- Данные категории (готовы: статус ready) ---
    return Scaffold(
      appBar: AppBar(title: Text(category.title)),
      body: SafeArea(
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          itemCount: articles.length,
          itemBuilder: (context, index) {
            final article = articles[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                margin: EdgeInsets.zero,
                child: InkWell(
                  key: Key('article-card-${article.id}'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: () =>
                      context.push(AppConstants.articlePath(article.id)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                article.title,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            DifficultyBadge(difficulty: article.difficulty),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          article.summary,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
