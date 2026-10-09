import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/empty_state.dart';
import '../../auth/session_provider.dart';
import '../../reference/article_model.dart';
import '../../reference/history_provider.dart';
import '../../reference/reference_provider.dart';
import '../../reference/widgets/category_card.dart';

/// Главный экран (вкладка «Главная», P5, дополнен P8/P9).
///
/// Приветствие по имени, карточки категорий справочника с переходом на
/// `/reference/<categoryId>`, секция «Продолжить» (P9): недавние статьи из
/// [HistoryProvider] — рендерится ТОЛЬКО при непустой истории.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final reference = context.watch<ReferenceProvider>();
    final history = context.watch<HistoryProvider>();
    final user = session.currentUser;
    final theme = Theme.of(context);

    // «Продолжить» (P9): недавние статьи топ-20 истории; секция скрыта,
    // пока истории нет (критично для виджет-теста «без истории — скрыта»).
    final recent = history.recent(count: AppConstants.homeRecentLimit);

    final greeting = user != null ? 'Привет, ${user.username}!' : 'Привет!';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Главная'),
        actions: [
          IconButton(
            key: const Key('home-open-search'),
            tooltip: 'Поиск',
            onPressed: () => context.push(AppConstants.routeSearch),
            icon: const Icon(Icons.search),
          ),
          IconButton(
            key: const Key('home-open-history'),
            tooltip: 'История',
            onPressed: () => context.push(AppConstants.routeHistory),
            icon: const Icon(Icons.history),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            // Приветствие (гость — fallback; вкладки приватные, гостя не бывает)
            Text(
              greeting,
              key: const Key('home-greeting'),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Справочник по C++ с интерактивными примерами кода.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),

            // --- Категории справочника ---
            Text(
              'Категории',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _referenceSection(reference),

            // --- «Продолжить» (P9): только при непустой истории ---
            if (recent.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                'Продолжить',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              for (final entry in recent)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _RecentCard(
                    key: Key('home-recent-${entry.article.id}'),
                    article: entry.article,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// Секция категорий по статусу загрузки справочника.
  Widget _referenceSection(ReferenceProvider reference) {
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
                  key: Key('home-category-${category.id}'),
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

/// Карточка «Продолжить» (P9, оживила HistoryProvider): переход на статью
/// по id из истории (данные — из провайдера, не из маршрута).
class _RecentCard extends StatelessWidget {
  const _RecentCard({super.key, required this.article});

  final Article article;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push(AppConstants.articlePath(article.id)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.history,
                  size: 20,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      article.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      article.summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, height: 1.25),
                    ),
                  ],
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
