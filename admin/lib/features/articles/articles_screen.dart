import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/models/article.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/date_format.dart';
import '../../core/widgets/app_snackbar.dart';
import 'articles_provider.dart';

/// Экран управления статьями (`/articles`).
class ArticlesScreen extends StatefulWidget {
  const ArticlesScreen({super.key});

  @override
  State<ArticlesScreen> createState() => _ArticlesScreenState();
}

class _ArticlesScreenState extends State<ArticlesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<ArticlesProvider>();
      provider.loadCategories();
      provider.load();
    });
  }

  Future<void> _togglePublished(Article article) async {
    final provider = context.read<ArticlesProvider>();
    try {
      final updated = await provider.setPublished(
        article,
        !article.isPublished,
      );
      if (mounted) {
        showSuccessSnackBar(
          context,
          updated.isPublished
              ? 'Статья «${updated.title}» опубликована'
              : 'Статья «${updated.title}» снята с публикации',
        );
      }
    } on ApiException catch (error) {
      if (mounted) showErrorSnackBar(context, apiErrorMessage(error));
    }
  }

  Future<void> _delete(Article article) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить статью?'),
        content: Text(
          'Статья «${article.title}» будет удалена без возможности '
          'восстановления. Продолжить?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final provider = context.read<ArticlesProvider>();
    try {
      await provider.deleteArticle(article);
      if (mounted) {
        showSuccessSnackBar(context, 'Статья «${article.title}» удалена');
      }
    } on ApiException catch (error) {
      if (mounted) showErrorSnackBar(context, apiErrorMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ArticlesProvider>();
    final scheme = Theme.of(context).colorScheme;
    final categoryFilter = provider.categoryFilter;
    final categoryItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: '', child: Text('Все категории')),
      ...provider.categories.map(
        (category) =>
            DropdownMenuItem(value: category.id, child: Text(category.title)),
      ),
      // Если выбранная категория исчезла из нового списка, не роняем фильтр.
      if (categoryFilter != null &&
          categoryFilter.isNotEmpty &&
          !provider.categories.any((category) => category.id == categoryFilter))
        DropdownMenuItem(value: categoryFilter, child: Text(categoryFilter)),
    ];

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Статьи',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(
                    'Всего: ${provider.articles.length}',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              _FilterDropdown(
                label: 'Категория',
                value: provider.categoryFilter ?? '',
                items: categoryItems,
                onChanged: (value) => provider.applyFilters(
                  categoryId: (value == null || value.isEmpty) ? null : value,
                  published: provider.publishedFilter,
                ),
              ),
              _FilterDropdown(
                label: 'Статус',
                value: switch (provider.publishedFilter) {
                  true => 'published',
                  false => 'draft',
                  null => '',
                },
                items: const [
                  DropdownMenuItem(value: '', child: Text('Все статусы')),
                  DropdownMenuItem(
                    value: 'published',
                    child: Text('Опубликованные'),
                  ),
                  DropdownMenuItem(value: 'draft', child: Text('Черновики')),
                ],
                onChanged: (value) => provider.applyFilters(
                  categoryId: provider.categoryFilter,
                  published: switch (value) {
                    'published' => true,
                    'draft' => false,
                    _ => null,
                  },
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Обновить',
                onPressed: provider.loading ? null : provider.load,
                icon: const Icon(Icons.refresh),
              ),
              FilledButton.icon(
                onPressed: () => context.go('/articles/edit/new'),
                icon: const Icon(Icons.add),
                label: const Text('Добавить статью'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (provider.loading) const LinearProgressIndicator(minHeight: 2),
          if (provider.errorMessage != null)
            _ErrorBanner(
              message: provider.errorMessage!,
              onRetry: provider.load,
            ),
          const SizedBox(height: 8),
          Expanded(
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: provider.articles.isEmpty && !provider.loading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('Статьи не найдены'),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minWidth: constraints.maxWidth,
                              ),
                              child: DataTable(
                                showCheckboxColumn: false,
                                columnSpacing: 24,
                                headingRowColor: WidgetStatePropertyAll(
                                  scheme.surfaceContainerHighest.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                                columns: const [
                                  DataColumn(label: Text('ID')),
                                  DataColumn(label: Text('Название')),
                                  DataColumn(label: Text('Категория')),
                                  DataColumn(label: Text('Сложность')),
                                  DataColumn(label: Text('Статус')),
                                  DataColumn(label: Text('Обновлена')),
                                  DataColumn(label: Text('Действия')),
                                ],
                                rows: provider.articles.map((article) {
                                  return DataRow(
                                    key: ValueKey('article_${article.id}'),
                                    cells: [
                                      DataCell(
                                        SizedBox(
                                          width: 90,
                                          child: Text(
                                            article.id,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        ConstrainedBox(
                                          constraints: const BoxConstraints(
                                            maxWidth: 280,
                                          ),
                                          child: Tooltip(
                                            message: article.summary.isEmpty
                                                ? article.title
                                                : '${article.title}\n\n'
                                                      '${article.summary}',
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                  article.title,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                if (article.tags.isNotEmpty)
                                                  Text(
                                                    article.tags.join(', '),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: scheme
                                                          .onSurfaceVariant,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          article.categoryTitle.isNotEmpty
                                              ? article.categoryTitle
                                              : provider.categoryTitle(
                                                  article.categoryId,
                                                ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          difficultyLabel(article.difficulty),
                                        ),
                                      ),
                                      DataCell(
                                        _PublishedChip(
                                          published: article.isPublished,
                                        ),
                                      ),
                                      DataCell(
                                        Text(formatDateTime(article.updatedAt)),
                                      ),
                                      DataCell(
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              tooltip: 'Редактировать',
                                              icon: const Icon(
                                                Icons.edit_outlined,
                                              ),
                                              onPressed: () => context.go(
                                                '/articles/edit/${article.id}',
                                              ),
                                            ),
                                            IconButton(
                                              tooltip: article.isPublished
                                                  ? 'Снять с публикации'
                                                  : 'Опубликовать',
                                              icon: Icon(
                                                article.isPublished
                                                    ? Icons.unpublished_outlined
                                                    : Icons.publish_outlined,
                                              ),
                                              onPressed: () =>
                                                  _togglePublished(article),
                                            ),
                                            IconButton(
                                              tooltip: 'Удалить',
                                              icon: Icon(
                                                Icons.delete_outline,
                                                color: scheme.error,
                                              ),
                                              onPressed: () => _delete(article),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _PublishedChip extends StatelessWidget {
  const _PublishedChip({required this.published});

  final bool published;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = published ? const Color(0xFF2E7D32) : scheme.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        published ? 'Опубликована' : 'Черновик',
        style: TextStyle(fontSize: 12, color: color),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Повторить')),
        ],
      ),
    );
  }
}
