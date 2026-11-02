import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/models/article.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/app_snackbar.dart';
import 'articles_provider.dart';

/// Создание и редактирование статьи (`/articles/edit/:id`).
///
/// `id == 'new'` — создание новой записи.
class ArticleEditScreen extends StatefulWidget {
  const ArticleEditScreen({super.key, required this.articleId});

  final String articleId;

  @override
  State<ArticleEditScreen> createState() => _ArticleEditScreenState();
}

class _ArticleEditScreenState extends State<ArticleEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _summaryController = TextEditingController();
  final _tagsController = TextEditingController();
  final _blocksController = TextEditingController(text: '[]');

  String _categoryId = '';
  String _difficulty = 'beginner';
  bool _published = false;
  bool _loading = true;
  bool _saving = false;
  bool _notFound = false;
  String? _serverError;
  Map<String, String> _fieldErrors = const <String, String>{};

  bool get _isNew => widget.articleId == 'new';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  @override
  void dispose() {
    _titleController.dispose();
    _summaryController.dispose();
    _tagsController.dispose();
    _blocksController.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    final provider = context.read<ArticlesProvider>();
    await provider.loadCategories();
    if (!mounted) return;

    if (_isNew) {
      setState(() {
        if (provider.categories.isNotEmpty) {
          _categoryId = provider.categories.first.id;
        }
        _loading = false;
      });
      return;
    }

    final article = await provider.findArticle(widget.articleId);
    if (!mounted) return;
    if (article == null) {
      setState(() {
        _loading = false;
        _notFound = true;
      });
      return;
    }
    _fill(article);
    setState(() => _loading = false);
  }

  void _fill(Article article) {
    _titleController.text = article.title;
    _summaryController.text = article.summary;
    _tagsController.text = article.tags.join(', ');
    _blocksController.text = article.blocksJson;
    _categoryId = article.categoryId;
    _difficulty = article.difficulty;
    _published = article.isPublished;
  }

  Future<void> _save() async {
    setState(() {
      _serverError = null;
      _fieldErrors = const <String, String>{};
    });
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_categoryId.isEmpty) {
      setState(() => _serverError = 'Выберите категорию статьи.');
      return;
    }

    final provider = context.read<ArticlesProvider>();
    setState(() => _saving = true);
    try {
      await provider.saveArticle(
        id: _isNew ? null : widget.articleId,
        title: _titleController.text,
        summary: _summaryController.text,
        categoryId: _categoryId,
        difficulty: _difficulty,
        tags: _parseTags(_tagsController.text),
        blocksJson: _blocksController.text.trim().isEmpty
            ? '[]'
            : _blocksController.text.trim(),
        published: _published,
      );
      if (!mounted) return;
      showSuccessSnackBar(
        context,
        _isNew ? 'Статья создана' : 'Изменения сохранены',
      );
      context.go('/articles');
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _serverError = error.message;
        _fieldErrors = error.fields;
        _saving = false;
      });
    }
  }

  List<String> _parseTags(String value) => value
      .split(',')
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .toList();

  String? _validateBlocks(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Введите JSON-массив блоков';
    try {
      final decoded = jsonDecode(text);
      if (decoded is! List) return 'Ожидается JSON-массив блоков';
    } catch (_) {
      return 'Некорректный JSON';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<ArticlesProvider>();
    final scheme = Theme.of(context).colorScheme;

    final categoryItems = provider.categories
        .map(
          (category) =>
              DropdownMenuItem(value: category.id, child: Text(category.title)),
        )
        .toList();
    // Статья может ссылаться на категорию, которой нет в актуальном списке.
    // Показываем её отдельным пунктом, чтобы форма не падала.
    if (_categoryId.isNotEmpty &&
        !categoryItems.any((item) => item.value == _categoryId)) {
      categoryItems.insert(
        0,
        DropdownMenuItem(
          value: _categoryId,
          child: Text(provider.categoryTitle(_categoryId)),
        ),
      );
    }

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_notFound) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, size: 48),
            const SizedBox(height: 12),
            const Text('Статья не найдена'),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => context.go('/articles'),
              child: const Text('К списку статей'),
            ),
          ],
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Назад',
                          onPressed: () => context.go('/articles'),
                          icon: const Icon(Icons.arrow_back),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isNew ? 'Новая статья' : 'Редактирование статьи',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_serverError != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _serverError!,
                          style: TextStyle(color: scheme.onErrorContainer),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextFormField(
                      controller: _titleController,
                      decoration: InputDecoration(
                        labelText: 'Название',
                        errorText: _fieldErrors['title'],
                      ),
                      validator: (value) {
                        if ((value?.trim() ?? '').isEmpty) {
                          return 'Введите название';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _summaryController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: 'Краткое описание',
                        errorText: _fieldErrors['summary'],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        SizedBox(
                          width: 320,
                          child: DropdownButtonFormField<String>(
                            initialValue: _categoryId.isEmpty
                                ? null
                                : _categoryId,
                            decoration: InputDecoration(
                              labelText: 'Категория',
                              errorText: _fieldErrors['category_id'],
                            ),
                            items: categoryItems,
                            onChanged: _saving
                                ? null
                                : (value) {
                                    if (value != null) {
                                      setState(() => _categoryId = value);
                                    }
                                  },
                            validator: (value) => value == null || value.isEmpty
                                ? 'Выберите категорию'
                                : null,
                          ),
                        ),
                        SizedBox(
                          width: 220,
                          child: DropdownButtonFormField<String>(
                            initialValue: _difficulty,
                            decoration: const InputDecoration(
                              labelText: 'Сложность',
                            ),
                            items: difficultyLabels.entries
                                .map(
                                  (entry) => DropdownMenuItem(
                                    value: entry.key,
                                    child: Text(entry.value),
                                  ),
                                )
                                .toList(),
                            onChanged: _saving
                                ? null
                                : (value) {
                                    if (value != null) {
                                      setState(() => _difficulty = value);
                                    }
                                  },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _tagsController,
                      decoration: const InputDecoration(
                        labelText: 'Теги',
                        hintText: 'Через запятую: массивы, циклы, строки',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _blocksController,
                      minLines: 10,
                      maxLines: 20,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Блоки статьи (JSON)',
                        alignLabelWithHint: true,
                        errorText:
                            _fieldErrors['blocks_json'] ??
                            _fieldErrors['blocks'],
                        hintText: '[{"type":"text","content":"…"}]',
                      ),
                      validator: _validateBlocks,
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Опубликовать статью'),
                      subtitle: const Text(
                        'Опубликованная статья доступна в мобильном приложении',
                      ),
                      value: _published,
                      onChanged: _saving
                          ? null
                          : (value) => setState(() => _published = value),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 12,
                      children: [
                        OutlinedButton(
                          onPressed: _saving
                              ? null
                              : () => context.go('/articles'),
                          child: const Text('Отмена'),
                        ),
                        FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(_saving ? 'Сохранение…' : 'Сохранить'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
