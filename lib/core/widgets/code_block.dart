import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';

import 'app_snackbar.dart';

/// Блок кода статьи (P6) на базе `flutter_highlight`.
///
/// Возможности: подсветка (язык из JSON — cpp, позже dart), горизонтальный
/// скролл длинных строк, кнопка «Копировать» (Clipboard + ВСЕГДА наблюдаемый
/// снекбар «Скопировано» — подводный камень №6 из плана), раскрывающийся блок
/// «Показать вывод» и подпись под кодом (caption).
class CodeBlock extends StatefulWidget {
  const CodeBlock({
    super.key,
    required this.code,
    this.language = 'cpp',
    this.output,
    this.caption,
  });

  /// Исходный код (полный компилируемый файл с main — README контента).
  final String code;

  /// Код языка ('cpp'; позже 'dart' — README контента).
  final String language;

  /// Ожидаемый вывод программы (null/пусто — переключатель не показывается).
  final String? output;

  /// Подпись под кодом.
  final String? caption;

  @override
  State<CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<CodeBlock> {
  /// Показан ли сейчас блок вывода (по умолчанию свёрнут).
  bool _showOutput = false;

  /// Человекочитаемое имя языка (в контенте — коды: cpp, позже dart).
  String get _languageLabel => switch (widget.language) {
    'cpp' => 'C++',
    'dart' => 'Dart',
    _ => widget.language,
  };

  /// Иконка языка в шапке блока.
  IconData get _languageIcon => switch (widget.language) {
    'dart' => Icons.flutter_dash,
    _ => Icons.terminal,
  };

  /// Копирование кода в буфер обмена.
  ///
  /// Clipboard.setData асинхронен, но снекбар «Скопировано» показывается
  /// ВСЕГДА — фидбек должен быть наблюдаем (подводный камень №6 из плана).
  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    showCopiedSnackBar(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;

    // Тема подсветки соответствует светлой/тёмной теме приложения.
    final highlightTheme = dark ? atomOneDarkTheme : atomOneLightTheme;

    // Длинные строки кода прокручиваются по горизонтали: HighlightView
    // рисует RichText без переноса — скролл вместо ломаного переноса.
    final codeArea = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 12),
      child: HighlightView(
        widget.code,
        language: widget.language,
        theme: highlightTheme,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );

    // Блок вывода: свёрнутый переключатель + развёрнутый моно-текст.
    final hasOutput = widget.output != null && widget.output!.isNotEmpty;
    final outputSection = !hasOutput
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                key: const Key('output-toggle'),
                onTap: () => setState(() => _showOutput = !_showOutput),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _showOutput ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _showOutput ? 'Скрыть вывод' : 'Показать вывод',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_showOutput)
                Container(
                  width: double.infinity,
                  color: scheme.surfaceContainerLowest,
                  padding: const EdgeInsets.fromLTRB(12, 9, 12, 11),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.output!,
                    key: const Key('output-text'),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontFamily: 'monospace',
                      height: 1.35,
                    ),
                  ),
                ),
            ],
          );

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // --- Шапка: иконка/язык + кнопка «Копировать» ---
          Row(
            children: [
              const SizedBox(width: 12),
              Icon(_languageIcon, size: 15, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                _languageLabel,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              IconButton(
                key: const Key('code-copy'),
                visualDensity: VisualDensity.compact,
                tooltip: 'Копировать',
                onPressed: _copy,
                icon: Icon(
                  Icons.copy,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: scheme.surfaceContainerLowest,
          ),
          // --- Код с подсветкой ---
          codeArea,
          Divider(
            height: 1,
            thickness: 1,
            color: scheme.surfaceContainerLowest,
          ),
          // --- Вывод (раскрывающийся) ---
          ?outputSection,
          // --- Подпись под кодом ---
          if (widget.caption != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Text(
                widget.caption!,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
