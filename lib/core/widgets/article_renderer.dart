import 'package:flutter/material.dart';

import '../../features/reference/article_model.dart';
import 'code_block.dart';

/// Рендер JSON-блоков статьи в виджеты (P6; без markdown-зависимостей).
///
/// Каждый из пяти типов блоков (sealed-иерархия [ArticleBlock]) превращается
/// в виджет: text → абзац, heading → подзаголовок, list → маркированный
/// список, code → [CodeBlock] (подсветка/копирование/вывод), note → врезка.
/// Порядок блоков — как в JSON.
class ArticleRenderer extends StatelessWidget {
  const ArticleRenderer({super.key, required this.blocks});

  /// Блоки статьи в порядке следования (данные только из репозитория).
  final List<ArticleBlock> blocks;

  /// Разбор одного блока в виджет (статический — удобно для экранов и тестов).
  static Widget renderBlock(BuildContext context, ArticleBlock block) {
    final scheme = Theme.of(context).colorScheme;

    if (block is ArticleTextBlock) {
      // Абзац: интерлиньяж 1.5 — комфортное чтение.
      return Text(
        block.text,
        style: const TextStyle(fontSize: 15, height: 1.5),
      );
    }
    if (block is ArticleHeadingBlock) {
      // Подзаголовок: крупнее абзаца, в фирменном цвете.
      return Text(
        block.text,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.bold,
          color: scheme.primary,
        ),
      );
    }
    if (block is ArticleListBlock) {
      // Маркированный список: буллеты «•» с отступом.
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final item in block.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Text(
                      '•',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(fontSize: 15, height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }
    if (block is ArticleCodeBlock) {
      // Код: CodeBlock с подсветкой, копированием и выводом.
      return CodeBlock(
        language: block.language,
        code: block.code,
        output: block.output,
        caption: block.caption,
      );
    }
    if (block is ArticleNoteBlock) {
      // Врезка-замечание: плашка secondaryContainer с иконкой info.
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              size: 20,
              color: scheme.onSecondaryContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                block.text,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: scheme.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ),
      );
    }
    // Sealed-иерархия гарантирует: иных блоков не бывает.
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    // Блоки в порядке следования; между ними отступ 12 px.
    final children = <Widget>[];
    for (var i = 0; i < blocks.length; i++) {
      children.add(renderBlock(context, blocks[i]));
      if (i != blocks.length - 1) {
        children.add(const SizedBox(height: 12));
      }
    }
    return Column(mainAxisSize: MainAxisSize.min, children: children);
  }
}
