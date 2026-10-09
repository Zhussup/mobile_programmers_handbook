import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/empty_state.dart';
import '../../reference/article_model.dart';
import '../../reference/reference_provider.dart';
import '../../reference/widgets/difficulty_badge.dart';
import '../search_provider.dart';

/// Экран поиска `/search` (P8): мгновенная фильтрация справочника по
/// title/summary/tags + чипы сложности.
///
/// Данные — из [SearchProvider]/[ReferenceProvider] (в маршруте нет ничего
/// кроме пути — подводный камень №8 из плана). Переход на статью —
/// `/article/:id`. Состояние поиска при уходе пересоздаётся: поле
/// синхронизируется с [SearchProvider.query], а сам провайдер живёт на
/// уровне приложения.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  /// Контроллер поля поиска (для кнопки очистки).
  final TextEditingController _queryController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Поле синхронно с провайдером (поиск сохраняется при возврате на экран,
    // пока жив провайдер — до выхода из приложения).
    _queryController.text = context.read<SearchProvider>().query;
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reference = context.watch<ReferenceProvider>();
    final search = context.watch<SearchProvider>();

    // --- Контент ещё грузится: спиннер (без поля — не путать) ---
    if (reference.status == ReferenceStatus.loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Поиск')),
        body: const Center(
          key: Key('reference-loading'),
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Поиск')),
      body: SafeArea(
        child: Column(
          children: [
            // --- Поле запроса: мгновенная фильтрация в onChanged ---
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                key: const Key('search-field'),
                controller: _queryController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  labelText: 'Название, описание или теги',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _queryController.text.isEmpty
                      ? null
                      : IconButton(
                          key: const Key('search-clear'),
                          tooltip: 'Очистить запрос',
                          onPressed: () {
                            _queryController.clear();
                            context.read<SearchProvider>().setQuery('');
                          },
                          icon: const Icon(Icons.clear),
                        ),
                  // Рамка — из inputDecorationTheme темы (radius 12, единый
                  // стиль форм на всех экранах): локальный OutlineInputBorder
                  // перебивал её на 4 px.
                ),
                onChanged: (value) {
                  setState(() {}); // перерисовать suffix-кнопку очистки
                  context.read<SearchProvider>().setQuery(value);
                },
              ),
            ),
            // --- Фильтр сложности (чипы) ---
            _DifficultyFilter(search: search),
            // --- Счётчик и результаты ---
            Expanded(
              child: _ResultsByStatus(reference: reference, search: search),
            ),
          ],
        ),
      ),
    );
  }
}

/// Фильтр сложности: чипы «Все» / Базовый / Средний / Продвинутый.
class _DifficultyFilter extends StatelessWidget {
  const _DifficultyFilter({required this.search});

  final SearchProvider search;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chip(
              context,
              key: const Key('diff-filter-all'),
              label: 'Все',
              selected: search.difficulty == null,
              onTap: () => search.setDifficulty(null),
            ),
            for (final difficulty in Difficulty.values)
              _chip(
                context,
                key: Key('diff-filter-${difficulty.name}'),
                label: difficulty.label,
                selected: search.difficulty == difficulty,
                onTap: () => search.setDifficulty(difficulty),
              ),
          ],
        ),
      ),
    );
  }

  /// Чип фильтра; тап по выбранному — возврат к «Все» (сброс фильтра).
  Widget _chip(
    BuildContext context, {
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ChoiceChip(
      key: key,
      label: Text(label),
      selected: selected,
      onSelected: (bool selectedNow) =>
          selected ? search.setDifficulty(null) : onTap(),
    );
  }
}

/// Результаты по статусу контента и результатам поиска.
class _ResultsByStatus extends StatelessWidget {
  const _ResultsByStatus({required this.reference, required this.search});

  final ReferenceProvider reference;
  final SearchProvider search;

  @override
  Widget build(BuildContext context) {
    // Контент не готов (ошибка): заглушка.
    if (reference.status == ReferenceStatus.error ||
        reference.categories.isEmpty) {
      return Center(
        child: EmptyState(
          key: const Key('search-reference-error'),
          title: 'Справочник недоступен',
          message: reference.errorMessage,
          icon: Icons.cloud_off,
        ),
      );
    }

    final results = search.results;

    // Ничего не найдено: EmptyState (P8).
    if (results.isEmpty) {
      return Center(
        child: EmptyState(
          key: const Key('search-empty'),
          title: 'Ничего не найдено',
          message: 'Измените запрос или сбросьте фильтр сложности.',
          icon: Icons.search_off,
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        // Счётчик найденного (наблюдаемый отклик фильтра в демо).
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            'Найдено: ${results.length}',
            key: const Key('search-results-count'),
            style: TextStyle(
              fontSize: 12.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (final result in results)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _SearchResultCard(result: result),
          ),
      ],
    );
  }
}

/// Карточка результата: title + difficulty badge + категория + summary.
class _SearchResultCard extends StatelessWidget {
  const _SearchResultCard({required this.result});

  final SearchResult result;

  @override
  Widget build(BuildContext context) {
    final article = result.article;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        key: Key('search-result-${article.id}'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push(AppConstants.articlePath(article.id)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                result.category.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      article.title,
                      style: const TextStyle(
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
    );
  }
}
