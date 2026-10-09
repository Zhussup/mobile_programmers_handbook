import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/widgets/empty_state.dart';
import '../reference_provider.dart';
import '../widgets/category_card.dart';

/// Вкладка «Справочник» (P6): список категорий из JSON-контента.
///
/// Данные — только из [ReferenceProvider] (id в маршруте — подводный камень
/// №8 из плана). Переход: `/reference/<categoryId>` → список статей.
class ReferenceScreen extends StatelessWidget {
  const ReferenceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final reference = context.watch<ReferenceProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Справочник')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            // Подпись раздела под AppBar.
            Text(
              'Категории',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _byStatus(reference),
          ],
        ),
      ),
    );
  }

  /// Содержимое секции по статусу загрузки.
  Widget _byStatus(ReferenceProvider reference) {
    switch (reference.status) {
      case ReferenceStatus.loading:
        return Center(
          key: const Key('reference-loading'),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: const CircularProgressIndicator(),
          ),
        );
      case ReferenceStatus.error:
        return EmptyState(
          key: const Key('reference-error'),
          title: 'Справочник недоступен',
          message: reference.errorMessage,
          icon: Icons.cloud_off,
        );
      case ReferenceStatus.ready:
        final categories = reference.categories;
        if (categories.isEmpty) {
          return EmptyState(
            title: 'Категорий пока нет',
            message: 'Содержимое справочника не загружено.',
          );
        }
        return Column(
          children: [
            for (final category in categories)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: CategoryCard(
                  key: Key('reference-category-${category.id}'),
                  category: category,
                  articleCount: reference
                      .articlesForCategory(category.id)
                      .length,
                ),
              ),
          ],
        );
    }
  }
}
