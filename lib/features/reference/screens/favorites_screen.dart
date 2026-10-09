import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/empty_state.dart';
import '../favorites_provider.dart';

/// Экран «Избранное» `/favorites` (P9): список статей пользователя с
/// кнопкой удаления и переходом на статью. Пусто → EmptyState.
///
/// Данные — из [FavoritesProvider] (user-scoped); кнопка удаления
/// переключает ту же запись, что и сердечко в статье, с снекбаром.
class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  /// Убрать статью из избранного (кнопка корзины на карточке).
  Future<void> _remove(BuildContext context, String articleId) async {
    try {
      final added = await context.read<FavoritesProvider>().toggle(articleId);
      if (!context.mounted) return;
      // По требованию плана (подводный камень №6): фидбек всегда наблюдаем.
      showAppSnackBar(
        context,
        added
            ? AppSnackBarMessages.favoriteAdded
            : AppSnackBarMessages.favoriteRemoved,
      );
    } on Exception {
      if (!context.mounted) return;
      showErrorSnackBar(context, 'Не удалось обновить избранное');
    }
  }

  @override
  Widget build(BuildContext context) {
    final favorites = context.watch<FavoritesProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Избранное')),
      body: SafeArea(
        child: favorites.entries.isEmpty
            ? const Center(
                child: EmptyState(
                  key: Key('favorites-empty'),
                  title: 'В избранном пусто',
                  message: 'Добавляйте статьи сердечком в AppBar статьи.',
                  icon: Icons.favorite_border,
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  for (final entry in favorites.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _FavoriteCard(
                        key: Key('favorites-entry-${entry.article.id}'),
                        entry: entry,
                        onRemove: () => _remove(context, entry.article.id),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

/// Карточка избранной статьи: переход на статью + кнопка «убрать».
class _FavoriteCard extends StatelessWidget {
  const _FavoriteCard({super.key, required this.entry, required this.onRemove});

  final FavoriteEntry entry;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push(AppConstants.articlePath(entry.article.id)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.article.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      entry.article.summary,
                      maxLines: 2,
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
              const SizedBox(width: 8),
              IconButton(
                key: Key('favorite-remove-${entry.article.id}'),
                visualDensity: VisualDensity.compact,
                tooltip: 'Убрать из избранного',
                onPressed: onRemove,
                icon: Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                size: 22,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
