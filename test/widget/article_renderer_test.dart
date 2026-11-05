import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mob_kurs/core/widgets/article_renderer.dart';
import 'package:mob_kurs/core/widgets/code_block.dart';
import 'package:mob_kurs/features/reference/article_model.dart';

/// Виджет-тесты ArticleRenderer (P6): все пять типов блоков рендерятся,
/// порядок блоков соблюдается.
void main() {
  const blocks = [
    ArticleTextBlock('Обычный текст абзаца'),
    ArticleHeadingBlock('Подзаголовок раздела'),
    ArticleListBlock(['Первый пункт', 'Второй пункт']),
    ArticleCodeBlock(
      language: 'cpp',
      code: 'int main() { return 0; }',
      output: 'ок',
      caption: 'Подпись',
    ),
    ArticleNoteBlock('Важное замечание'),
  ];

  Future<void> pumpRenderer(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: ArticleRenderer(blocks: blocks)),
        ),
      ),
    );
  }

  testWidgets('Рендерятся все пять типов блоков', (tester) async {
    await pumpRenderer(tester);

    // text
    expect(find.text('Обычный текст абзаца'), findsOneWidget);
    // heading
    expect(find.text('Подзаголовок раздела'), findsOneWidget);
    // list (2 пункта, буллеты «•»)
    expect(find.text('Первый пункт'), findsOneWidget);
    expect(find.text('Второй пункт'), findsOneWidget);
    expect(find.text('•'), findsNWidgets(2));
    // code (CodeBlock + подпись)
    expect(find.byType(CodeBlock), findsOneWidget);
    expect(find.text('Подпись'), findsOneWidget);
    // note
    expect(find.text('Важное замечание'), findsOneWidget);
  });

  testWidgets('Порядок блоков — как в JSON (по позициям на экране)', (
    tester,
  ) async {
    await pumpRenderer(tester);

    double topOf(String text) => tester.getTopLeft(find.text(text)).dy;

    final textTop = topOf('Обычный текст абзаца');
    final headingTop = topOf('Подзаголовок раздела');
    final noteTop = topOf('Важное замечание');

    expect(textTop, lessThan(headingTop));
    expect(headingTop, lessThan(noteTop));
  });

  testWidgets('Пустой список блоков рендерит пустую колонку', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ArticleRenderer(blocks: [])),
      ),
    );
    expect(find.byType(ArticleRenderer), findsOneWidget);
  });
}
