import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/empty_state.dart';
import '../history_provider.dart';

/// Экран «История» `/history` (P9): топ-20 просмотренных статей + кнопка
/// «Очистить» с диалогом подтверждения (подводный камень №6 — снекбар).
///
/// Данные — из [HistoryProvider] (user-scoped); переходы — `/article/:id`.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  /// Диалог подтверждения очистки + сама очистка + снекбар.
  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Очистить историю?'),
        content: const Text(
          'Список «Недавно смотрели» будет удалён для этого аккаунта. '
          'Статьи останутся в справочнике.',
        ),
        actions: [
          TextButton(
            key: const Key('history-clear-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            key: const Key('history-clear-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Очистить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    try {
      await context.read<HistoryProvider>().clear();
      if (!context.mounted) return;
      showAppSnackBar(context, AppSnackBarMessages.historyCleared);
    } on Exception {
      if (!context.mounted) return;
      showErrorSnackBar(context, 'Не удалось очистить историю');
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = context.watch<HistoryProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('История'),
        actions: [
          // Кнопка «Очистить» есть только когда есть что чистить.
          if (history.entries.isNotEmpty)
            IconButton(
              key: const Key('history-clear'),
              tooltip: 'Очистить историю',
              onPressed: () => _confirmClear(context),
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: SafeArea(
        child: history.entries.isEmpty
            ? const Center(
                child: EmptyState(
                  key: Key('history-empty'),
                  title: 'История пуста',
                  message:
                      'После чтения статей здесь появится '
                      '«Недавно смотрели».',
                  icon: Icons.history,
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      'Недавно смотрели',
                      key: const Key('history-section-title'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  for (final entry in history.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _HistoryCard(
                        key: Key('history-entry-${entry.article.id}'),
                        entry: entry,
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

/// Карточка истории: статья + время просмотра, переход на статью.
class _HistoryCard extends StatelessWidget {
  const _HistoryCard({super.key, required this.entry});

  final HistoryEntry entry;

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
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('dd.MM.yyyy HH:mm').format(entry.viewedAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
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
