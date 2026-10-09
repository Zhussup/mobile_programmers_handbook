import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/empty_state.dart';
import '../playground_draft_provider.dart';
import '../snippet_model.dart';
import '../snippet_provider.dart';

/// Раздел «Песочница» `/playground` (P10): список своих сниппетов + FAB
/// «Создать».
///
/// Черновик «Открыть в песочнице» из статьи: экран замечает появление
/// черновика ([PlaygroundDraftProvider]) и открывает редактор в режиме
/// создания; сам код редактор забирает в своём init-эффекте
/// (`consumeDraft`). Данные в маршрутах — только id (подводный камень №8).
class PlaygroundScreen extends StatefulWidget {
  const PlaygroundScreen({super.key});

  @override
  State<PlaygroundScreen> createState() => _PlaygroundScreenState();
}

class _PlaygroundScreenState extends State<PlaygroundScreen> {
  /// Провайдер сохранён в initState (context.read с listen: false разрешён
  /// в initState): ссылка нужна и для add/removeListener — доступ через
  /// context в dispose уже невозможен (inherited после unmount).
  late final PlaygroundDraftProvider _draftProvider;

  @override
  void initState() {
    super.initState();
    _draftProvider = context.read<PlaygroundDraftProvider>();
    // Слушатель черновика: IndexedStack сохраняет состояние вкладок, поэтому
    // initState не перезапускается при повторных визитах — слушатель же
    // живёт все время жизни экрана и срабатывает на каждый setDraft.
    _draftProvider.addListener(_onDraftChanged);
    // Первый вход на вкладку при уже записанном черновике (переход
    // go('/playground') создаёт экран без notify): постфрейм-проверка.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _handleDraftIfNeeded(),
    );
  }

  @override
  void dispose() {
    // Слушатель снимается по сохранённому провайдеру и той же ссылкой,
    // что регистрировался; context.read в dispose недоступен (unmount).
    _draftProvider.removeListener(_onDraftChanged);
    super.dispose();
  }

  /// Реакция на появление черновика: открыть редактор (режим создания).
  void _onDraftChanged() {
    if (!mounted) return;
    _handleDraftIfNeeded();
  }

  /// Открыть редактор, если есть неподобранный черновик.
  ///
  /// Защита от повторного push: черновик ОДНОРАЗОВЫЙ — редактор забирает
  /// его в своём init-эффекте; двойной push возможен только если бы
  /// слушатель и постфрейм-проверка сработали на один и тот же черновик в
  /// один кадр, поэтому перед push проверяем hasDraft ещё раз.
  void _handleDraftIfNeeded() {
    if (!mounted) return;
    if (!_draftProvider.hasDraft) return;
    // push, а не go: редактор — страница ВНУТРИ ветки «Песочница» (нижняя
    // навигация остаётся; кнопка «назад» ведёт в список).
    context.push(AppConstants.routeSnippetNew);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SnippetProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Песочница')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('playground-fab'),
        onPressed: () => context.push(AppConstants.routeSnippetNew),
        icon: const Icon(Icons.add),
        label: const Text('Создать'),
      ),
      body: SafeArea(
        child: _buildList(context, provider, scheme),
      ),
    );
  }

  /// Тело: спиннер первой загрузки → EmptyState → карточки сниппетов.
  Widget _buildList(
    BuildContext context,
    SnippetProvider provider,
    ColorScheme scheme,
  ) {
    if (provider.loading && provider.entries.isEmpty) {
      return const Center(
        key: Key('playground-loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (provider.entries.isEmpty) {
      return const Center(
        child: EmptyState(
          key: Key('playground-empty'),
          title: 'Сниппетов пока нет',
          message: 'Нажмите «Создать», чтобы написать первый фрагмент кода, '
              'или откройте пример из статьи кнопкой «Открыть в песочнице».',
          icon: Icons.code,
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
      itemCount: provider.entries.length,
      itemBuilder: (context, index) {
        final snippet = provider.entries[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _SnippetCard(key: Key('snippet-card-${snippet.id}'), snippet: snippet),
        );
      },
    );
  }
}

/// Карточка сниппета: название, чип языка, время изменения, превью кода.
/// Тап — редактирование (`/playground/edit/:id`, данные только по id).
class _SnippetCard extends StatelessWidget {
  const _SnippetCard({super.key, required this.snippet});

  final Snippet snippet;

  /// Превью кода: первые строки, моноширинно, серым.
  String get _previewText {
    final lines = snippet.preview(count: 5);
    if (lines.isEmpty) return '// пусто';
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push(
          AppConstants.snippetEditPath(snippet.id),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      snippet.title,
                      key: const Key('snippet-card-title'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      snippet.language.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Обновлено: ${DateFormat('dd.MM.yyyy HH:mm').format(snippet.updatedAt)}',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _previewText,
                  key: const Key('snippet-card-preview'),
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.3,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}