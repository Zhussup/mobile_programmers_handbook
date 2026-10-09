import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mob_kurs/core/constants/app_constants.dart';
import 'package:mob_kurs/features/reference/article_repository.dart';
import 'package:mob_kurs/features/reference/screens/article_screen.dart';

import 'fixtures.dart';
import 'harness.dart';

/// Виджет-тесты поиска (P8): ввод сужает результаты, чипы сложности
/// фильтруют, пустой результат → EmptyState, переход в статью.
void main() {
  final harness = AppHarness();

  setUp(() => harness.setUp());
  tearDown(() => harness.tearDown());

  const t = Timeout(Duration(seconds: 60));

  /// Открыть /search на фикстурном контенте (гость закрыт guard'ом —
  /// сначала регистрируем пользователя).
  Future<void> openSearch(WidgetTester tester) async {
    await harness.registerUser(tester);
    await harness.pumpApp(
      tester,
      initialLocation: AppConstants.routeSearch,
      referenceRepository: ArticleRepository.fromRaw(p8p9ReferenceFixtures),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'форма: поле поиска, счётчик, чипы «Все» и сложности',
    timeout: t,
    (tester) async {
      await openSearch(tester);

      expect(find.byKey(const Key('search-field')), findsOneWidget);
      expect(find.byKey(const Key('diff-filter-all')), findsOneWidget);
      expect(find.byKey(const Key('diff-filter-beginner')), findsOneWidget);
      expect(find.byKey(const Key('diff-filter-intermediate')), findsOneWidget);
      expect(find.byKey(const Key('diff-filter-advanced')), findsOneWidget);
      expect(find.text('Найдено: 4'), findsOneWidget);
    },
  );

  testWidgets('ввод названия сужает список результатов', timeout: t, (
    tester,
  ) async {
    await openSearch(tester);

    await tester.enterText(find.byKey(const Key('search-field')), 'цикл');
    await tester.pump();

    expect(find.text('Найдено: 1'), findsOneWidget);
    expect(find.byKey(const Key('search-result-fx_syn_loop')), findsOneWidget);
    expect(find.byKey(const Key('search-result-fx_syn_var')), findsNothing);
    expect(find.byKey(const Key('search-result-fx_stl_vector')), findsNothing);
  });

  testWidgets('поиск ловит по тегу, а не только по названию', timeout: t, (
    tester,
  ) async {
    await openSearch(tester);

    await tester.enterText(find.byKey(const Key('search-field')), 'stl');
    await tester.pump();

    expect(find.text('Найдено: 2'), findsOneWidget);
    expect(
      find.byKey(const Key('search-result-fx_stl_vector')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('search-result-fx_stl_map')), findsOneWidget);
  });

  testWidgets(
    'чипы меняют фильтр сложности (и совмещаются с запросом)',
    timeout: t,
    (tester) async {
      await openSearch(tester);

      // «advanced» → только fx_stl_vector.
      await tester.tap(find.byKey(const Key('diff-filter-advanced')));
      await tester.pump();

      expect(find.text('Найдено: 1'), findsOneWidget);
      expect(
        find.byKey(const Key('search-result-fx_stl_vector')),
        findsOneWidget,
      );

      // Запрос поверх фильтра: «stl» ничего не исключает, остаётся 1.
      await tester.enterText(find.byKey(const Key('search-field')), 'stl');
      await tester.pump();
      expect(find.text('Найдено: 1'), findsOneWidget);

      // Несовместимый запрос с фильтром → пусто.
      await tester.enterText(find.byKey(const Key('search-field')), 'переменн');
      await tester.pump();
      expect(find.byKey(const Key('search-empty')), findsOneWidget);

      // «Все» снимает фильтр.
      await tester.tap(find.byKey(const Key('diff-filter-all')));
      await tester.pump();
      expect(find.byKey(const Key('search-result-fx_syn_var')), findsOneWidget);
      expect(find.byKey(const Key('search-empty')), findsNothing);
    },
  );

  testWidgets('бессмыслица → EmptyState «Ничего не найдено»', timeout: t, (
    tester,
  ) async {
    await openSearch(tester);

    await tester.enterText(find.byKey(const Key('search-field')), 'яяя');
    await tester.pump();

    expect(find.byKey(const Key('search-empty')), findsOneWidget);
    expect(find.text('Ничего не найдено'), findsOneWidget);
    expect(find.byKey(const Key('search-results-count')), findsNothing);
  });

  testWidgets(
    'кнопка очистки поля стирает запрос (возвращает всё)',
    timeout: t,
    (tester) async {
      await openSearch(tester);

      await tester.enterText(find.byKey(const Key('search-field')), 'vector');
      await tester.pump();
      expect(find.text('Найдено: 1'), findsOneWidget);

      await tester.tap(find.byKey(const Key('search-clear')));
      await tester.pump();
      expect(find.text('Найдено: 4'), findsOneWidget);
      expect(find.byKey(const Key('search-clear')), findsNothing);
    },
  );

  testWidgets('тап результата открывает статью', timeout: t, (tester) async {
    await openSearch(tester);

    await tester.tap(find.byKey(const Key('search-result-fx_syn_var')));
    await tester.pumpAndSettle();
    await harness.settleRealIo(tester);

    expect(find.byType(ArticleScreen), findsOneWidget);
    expect(find.text('Переменные'), findsOneWidget);

    // Запрос сохранился (возврат с кнопки «назад» — та же выдача).
    // Прямая проверка возвращения на поиск: system back недоступен в
    // тестах — проверим через роутер: ArticleScreen поверх поиск не
    // «перезаписал» (поисковый экран в стеке, go_router сохраняет).
  });
}
