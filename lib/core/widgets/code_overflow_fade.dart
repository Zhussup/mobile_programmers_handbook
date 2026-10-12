import 'package:flutter/material.dart';

/// Затухание правого края кодовой области, когда самая длинная строка
/// не влезает по ширине (подводный камень №9).
///
/// Зачем: скроллируемые кодовые области (CodeField песочницы и HighlightView
/// блоков статей) длинные строки НЕ переносят — правый край срезает текст
/// без любой индикации прокрутки, и срез выглядит как дефект вёрстки, а не
/// как горизонтальный скролл. [CodeOverflowFade] мягко растворяет текст у
/// края (только когда переполнение реально есть): край читается как
/// «есть продолжение», а не «текст порван».
///
/// Ничего не перекрывает по кликам ([IgnorePointer]); при отсутствии
/// переполнения отдаёт [child] как есть — без обёрток и наложений.
class CodeOverflowFade extends StatelessWidget {
  const CodeOverflowFade({
    super.key,
    required this.child,
    required this.code,
    required this.fade,
    this.fadeKey,
    this.residualAllowance = 0,
    this.fadeWidth = 40,
  });

  /// Кодовая область (собственная гор. прокрутка внутри неё — у пакетов).
  final Widget child;

  /// Текст кода: по нему меряется самая длинная строка.
  final String code;

  /// Цвет растворения — фон кодовой области (края «светятся» им).
  final Color fade;

  /// Ключ полосы затухания (для виджет-тестов); null — не искать.
  final String? fadeKey;

  /// Резерв ширины, не доступный коду (номера строк/fold-стрелки CodeField
  /// ~96 лог.px; у блоков статей без страйда — 0).
  final double residualAllowance;

  /// Ширина полосы затухания (лог.px).
  final double fadeWidth;

  /// Ширина самой длинной строки кода моно-шрифтом (TextPainter).
  double _longestLineWidth() {
    const style = TextStyle(fontFamily: 'monospace', fontSize: 13);
    var widest = 0.0;
    for (final line in code.split('\n')) {
      if (widest > 4000) break; // дальше мерить смысла нет
      final painter = TextPainter(
        text: TextSpan(text: line.isEmpty ? ' ' : line, style: style),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 4000);
      widest = painter.width > widest ? painter.width : widest;
      painter.dispose();
    }
    return widest;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final overflows =
            _longestLineWidth() > constraints.maxWidth - residualAllowance;
        if (!overflows) return child;
        return Stack(
          children: [
            child,
            Positioned.fill(
              child: IgnorePointer(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    key: fadeKey == null ? null : Key(fadeKey!),
                    width: fadeWidth,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [fade.withValues(alpha: 0), fade],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}