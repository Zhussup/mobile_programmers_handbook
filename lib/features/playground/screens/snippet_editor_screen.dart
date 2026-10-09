import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:go_router/go_router.dart';
import 'package:highlight/highlight.dart' show Mode;
import 'package:highlight/languages/cpp.dart';
import 'package:highlight/languages/dart.dart';
import 'package:provider/provider.dart';

import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/empty_state.dart';
import '../playground_draft_provider.dart';
import '../snippet_model.dart';
import '../snippet_provider.dart';

/// Экран редактора сниппета (P10): создание и редактирование.
///
/// Режим определяется маршрутом: без snippetId — создание
/// (`/playground/new`), с id — редактирование (`/playground/edit/:id`).
///
/// Подсветка живая: [CodeController] + [CodeField] из flutter_code_editor.
///
/// Подводный камень №5 из плана: `resizeToAvoidBottomInset: true` (по
/// умолчанию) + прокручиваемое тело + `maxLines: null` у редактора — иначе
/// кнопка «Сохранить» уезжает за клавиатуру.
///
/// Подводный камень №8: экран получает ТОЛЬКО id — данные достаются из
/// [SnippetProvider]; для копии из статьи — черновик
/// [PlaygroundDraftProvider.consumeDraft()] в init-эффекте.
class SnippetEditorScreen extends StatefulWidget {
  /// Редактор сниппета (snippetId null — режим создания).
  const SnippetEditorScreen({super.key, this.snippetId});

  /// Id сниппета для режима редактирования (null — создание).
  final int? snippetId;

  @override
  State<SnippetEditorScreen> createState() => _SnippetEditorScreenState();
}

class _SnippetEditorScreenState extends State<SnippetEditorScreen> {
  /// Режим создания?
  bool get _isCreateMode => widget.snippetId == null;

  /// Редактор кода с живой подсветкой (язык меняется чипами).
  late final CodeController _codeController = CodeController(
    language: cpp,
    text: '',
  );

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _outputController = TextEditingController();

  /// Язык сниппета (чипы).
  SnippetLanguage _language = SnippetLanguage.cpp;

  /// Черновик/сниппет уже подставлены (одноразовая инициализация).
  bool _initialised = false;

  /// Сниппет режима редактирования не найден у текущего пользователя.
  bool _notFound = false;

  /// Идёт сохранение/удаление (защита от двойного тапа).
  bool _submitting = false;

  /// Inline-ошибка названия (не validator — проверка на submit).
  String? _titleError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initStep());
  }

  /// Init-эффект: подставить черновик (создание) или сниппет (редактирование).
  ///
  /// В режиме редактирования данные приходят из провайдера, и первая
  /// загрузка может быть ещё в полёте — тогда пробуем на следующем кадре.
  void _initStep() {
    if (!mounted || _initialised) return;
    if (_isCreateMode) {
      // Создание: забрать одноразовый черновик «Открыть в песочнице».
      final draft = context.read<PlaygroundDraftProvider>().consumeDraft();
      if (draft != null) {
        setState(() {
          _codeController.text = draft.code;
          _codeController.language = _highlightMode(draft.language);
          _language = draft.language;
        });
      }
      _initialised = true;
      return;
    }

    // Редактирование: сниппет из провайдера (только СВОЕГО пользователя).
    final provider = context.read<SnippetProvider>();
    final snippet = provider.snippetById(widget.snippetId!);
    if (snippet == null) {
      if (provider.loading) {
        // Первая загрузка списка ещё идёт — попробовать позже.
        WidgetsBinding.instance.addPostFrameCallback((_) => _initStep());
        return;
      }
      setState(() {
        _notFound = true;
        _initialised = true;
      });
      return;
    }
    setState(() => _prefill(snippet));
    _initialised = true;
  }

  /// Подстановка сниппета в контроллеры (одноразовая).
  void _prefill(Snippet snippet) {
    _titleController.text = snippet.title;
    _outputController.text = snippet.expectedOutput ?? '';
    _language = snippet.language;
    _codeController
      ..language = _highlightMode(snippet.language)
      ..text = snippet.code;
  }

  /// Mode из пакета highlight для живой подсветки выбранного языка.
  static Mode _highlightMode(SnippetLanguage language) => switch (language) {
    SnippetLanguage.dart => dart,
    SnippetLanguage.cpp => cpp,
  };

  @override
  void dispose() {
    _codeController.dispose();
    _titleController.dispose();
    _outputController.dispose();
    super.dispose();
  }

  /// Смена языка чипом: контроллер перечитывает подсветку.
  void _changeLanguage(SnippetLanguage language) {
    if (language == _language) return;
    setState(() {
      _language = language;
      _codeController.language = _highlightMode(language);
    });
  }

  /// Значение поля «Ожидаемый вывод»: пустая строка → null.
  String? get _expectedOutputValue {
    final text = _outputController.text.trim();
    return text.isEmpty ? null : text;
  }

  /// Сохранение (создание или обновление) → снекбар «Сохранено» → назад.
  Future<void> _save() async {
    if (_submitting) return;
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = 'Введите название сниппета');
      return;
    }
    setState(() {
      _titleError = null;
      _submitting = true;
    });
    try {
      final provider = context.read<SnippetProvider>();
      if (_isCreateMode) {
        await provider.create(
          title: title,
          language: _language,
          code: _codeController.text,
          expectedOutput: _expectedOutputValue,
        );
      } else {
        final original = provider.snippetById(widget.snippetId!);
        if (original == null) {
          if (!mounted) return;
          showErrorSnackBar(context, 'Сниппет не найден');
          return;
        }
        await provider.update(
          original,
          title: title,
          language: _language,
          code: _codeController.text,
          expectedOutput: _expectedOutputValue,
        );
      }
      if (!mounted) return;
      showSavedSnackBar(context);
      context.pop(); // назад в список ветки «Песочница»
    } on Exception {
      if (!mounted) return;
      showErrorSnackBar(context, 'Не удалось сохранить сниппет');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Отмена: назад в список без изменений.
  void _cancel() => context.pop();

  /// Удаление с диалогом подтверждения → снекбар «Удалено» → назад.
  Future<void> _deleteWithConfirm() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить сниппет?'),
        content: Text('«${_titleController.text.trim()}» будет удалён '
            'безвозвратно. Прочие сниппеты не затрагиваются.'),
        actions: [
          TextButton(
            key: const Key('snippet-delete-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            key: const Key('snippet-delete-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;
    try {
      final deleted = await context
          .read<SnippetProvider>()
          .delete(widget.snippetId!);
      if (!mounted) return;
      if (!deleted) {
        showErrorSnackBar(context, 'Сниппет не найден');
        return;
      }
      showAppSnackBar(context, AppSnackBarMessages.deleted);
      context.pop();
    } on Exception {
      if (!mounted) return;
      showErrorSnackBar(context, 'Не удалось удалить сниппет');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Редактирование: экран живёт на данных провайдера (см. _initStep) —
    // при отсутствии сниппета показать заглушку, а не пустую форму.
    if (_notFound) {
      return Scaffold(
        appBar: AppBar(title: const Text('Редактирование')),
        body: const EmptyState(
          key: Key('snippet-not-found'),
          title: 'Сниппет не найден',
          message: 'Возможно, он удалён или принадлежит другому аккаунту.',
          icon: Icons.search_off,
        ),
      );
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;

    // Тема подсветки — та же, что у блока кода статей, под app-тему.
    final codeStyles = dark ? atomOneDarkTheme : atomOneLightTheme;

    return Scaffold(
      // Подводный камень №5: клавиатура НЕ перекрывает кнопки — scaffold
      // ужимает телоскролла, всё в нём прокручивается.
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(_isCreateMode ? 'Новый сниппет' : 'Редактирование'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- Название ---
              TextField(
                key: const Key('snippet-title'),
                controller: _titleController,
                textInputAction: TextInputAction.next,
                maxLength: 60,
                decoration: InputDecoration(
                  labelText: 'Название сниппета',
                  prefixIcon: const Icon(Icons.title),
                  errorText: _titleError,
                ),
              ),
              const SizedBox(height: 12),

              // --- Язык: два чипа (cpp | dart) ---
              Row(
                children: [
                  Text('Язык', style: theme.textTheme.titleSmall),
                  const SizedBox(width: 12),
                  ChoiceChip(
                    key: const Key('snippet-lang-cpp'),
                    label: const Text('C++'),
                    selected: _language == SnippetLanguage.cpp,
                    onSelected: (_) => _changeLanguage(SnippetLanguage.cpp),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    key: const Key('snippet-lang-dart'),
                    label: const Text('Dart'),
                    selected: _language == SnippetLanguage.dart,
                    onSelected: (_) => _changeLanguage(SnippetLanguage.dart),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // --- Редактор кода (живая подсветка) ---
              Text('Код', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              CodeTheme(
                data: CodeThemeData(styles: codeStyles),
                child: CodeField(
                  key: const Key('snippet-code-editor'),
                  controller: _codeController,
                  minLines: 6,
                  // Подводный камень №5: maxLines: null — высота растёт под
                  // содержимое, кнопка «Сохранить» доступна при скролле.
                  maxLines: null,
                  wrap: false,
                  textStyle: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // --- Ожидаемый вывод ---
              TextField(
                key: const Key('snippet-output'),
                controller: _outputController,
                maxLines: 3,
                minLines: 1,
                decoration: const InputDecoration(
                  labelText: 'Ожидаемый вывод',
                  helperText: 'Что печатает программа (может быть пустым)',
                  prefixIcon: Icon(Icons.output),
                ),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
              const SizedBox(height: 20),

              // --- Кнопки действий ---
              FilledButton.icon(
                key: const Key('snippet-save'),
                onPressed: _submitting ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Сохранить'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('snippet-cancel'),
                      onPressed: _cancel,
                      icon: const Icon(Icons.close),
                      label: const Text('Отмена'),
                    ),
                  ),
                  // Удаление — только в режиме редактирования.
                  if (!_isCreateMode) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('snippet-delete'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: scheme.error,
                        ),
                        onPressed: _submitting ? null : _deleteWithConfirm,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Удалить'),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
