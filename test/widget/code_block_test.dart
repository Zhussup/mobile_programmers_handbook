import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChannels;
import 'package:flutter_test/flutter_test.dart';

import 'package:mob_kurs/core/widgets/code_block.dart';

/// Виджет-тесты CodeBlock (P6): копирование с снекбаром «Скопировано»
/// (подводный камень №6), раскрывающийся вывод, подпись.
void main() {
  /// Дать SnackBar'у отыграть таймер самоуничтожения и обратную анимацию —
  /// иначе «pending timer» в конце теста.
  Future<void> drainSnackBar(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 1));
  }

  const code = 'int main() {\n    return 0;\n}';

  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: ListView(children: [child])),
  );

  testWidgets('Код и подпись отрисованы, вывод свёрнут по умолчанию', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const CodeBlock(
          code: code,
          language: 'cpp',
          output: 'Hello, World!',
          caption: 'Подпись к примеру',
        ),
      ),
    );

    // Подсветка (HighlightView из flutter_highlight) присутствует.
    expect(find.byType(CodeBlock), findsOneWidget);
    expect(find.text('Подпись к примеру'), findsOneWidget);
    expect(find.text('Показать вывод'), findsOneWidget);
    // Вывод свёрнут: самого текста вывода нет.
    expect(find.byKey(const Key('output-text')), findsNothing);

    // Раскрытие вывода.
    await tester.tap(find.byKey(const Key('output-toggle')));
    await tester.pump();
    expect(find.text('Скрыть вывод'), findsOneWidget);
    expect(find.text('Hello, World!'), findsOneWidget);
    expect(find.byKey(const Key('output-text')), findsOneWidget);

    // Свёртывание обратно.
    await tester.tap(find.byKey(const Key('output-toggle')));
    await tester.pump();
    expect(find.text('Показать вывод'), findsOneWidget);
  });

  testWidgets('Копирование: текст в буфере обмена + снекбар «Скопировано»', (
    tester,
  ) async {
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (message) async {
        if (message.method == 'Clipboard.setData') {
          final arguments = message.arguments as Map<Object?, Object?>;
          clipboardText = arguments['text'] as String?;
        }
        return null;
      },
    );

    await tester.pumpWidget(
      wrap(const CodeBlock(code: 'тестовый код для буфера')),
    );

    await tester.tap(find.byKey(const Key('code-copy')));
    await tester.pump();

    // Снекбар «Скопировано» — ПОСТОЯННО наблюдаемый фидбек (не «молчание»).
    expect(find.text('Скопировано'), findsOneWidget);
    // Текст действительно в буфере обмена.
    expect(clipboardText, 'тестовый код для буфера');

    await drainSnackBar(tester);
  });

  testWidgets('Блок без output/caption: переключателя вывода нет', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const CodeBlock(code: 'int x = 1;')));

    expect(find.text('Показать вывод'), findsNothing);
    expect(find.text('Подпись к примеру'), findsNothing);
    expect(find.byKey(const Key('code-copy')), findsOneWidget);
  });

  testWidgets('Язык блока отображается в шапке (cpp → C++)', (tester) async {
    await tester.pumpWidget(wrap(const CodeBlock(code: 'int x;')));
    expect(find.text('C++'), findsOneWidget);
  });
}
