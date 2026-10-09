import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mob_kurs/core/constants/app_constants.dart';
import 'package:mob_kurs/features/reference/article_repository.dart';
import 'package:mob_kurs/features/reference/screens/article_screen.dart';
import 'package:mob_kurs/features/reference/screens/history_screen.dart';

import 'fixtures.dart';
import 'harness.dart';

/// Виджет-тесты истории (P9): открытие статьи → запись; экран /history —
/// карточки, «Очистить» с диалогом подтверждения, EmptyState, снекбар.
///
/// Начальный маршруты pumpApp учитывыается только на первом pump, поэтому
/// последующие переходы — программные (harness.goRoute).
void main() {
  final harness = AppHarness();

  setUp(() => harness.setUp());
  tearDown(() => harness.tearDown());

  const t = Timeout(Duration(seconds: 60));

  /// Зарегистрировать пользователя и открыть статьи (каждая — запись в
  /// историю). Текущий экран после вызова — последняя открытая статья.
  Future<void> registerAndView(
    WidgetTester tester, {
    List<String> articles = const ['fx_syn_var'],
  }) async {
    await harness.registerUser(tester);
    await harness.pumpApp(
      tester,
      initialLocation: '/article/${articles.first}',
      referenceRepository: ArticleRepository.fromRaw(p8p9ReferenceFixtures),
    );
    await tester.pumpAndSettle();
    // postFrame-запись истории — реальная IO: дождаться завершения.
    await harness.settleRealIo(tester);

    for (final id in articles.skip(1)) {
      harness.goRoute(tester, '/article/$id');
      await tester.pumpAndSettle();
      await harness.settleRealIo(tester);
    }
  }

  /// Перейти на /history и дождаться отрисовки списка.
  Future<void> openHistory(WidgetTester tester) async {
    harness.goRoute(tester, AppConstants.routeHistory);
    await tester.pumpAndSettle();
  }

  /// Дренаж снекбара: снекбар показан внутри runAsync-окна — сначала
  /// выжидаем реальный 4-секундный таймер, затем fake-время анимаций.
  Future<void> drainSnackBar(WidgetTester tester) async {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(seconds: 5));
    });
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 1));
  }

  /// Открыть диалог очистки (чистый UI-тап, без реальной IO).
  Future<void> openClearDialog(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('history-clear')));
    await tester.pumpAndSettle();
  }

  testWidgets('гость: /history закрыт auth-guard (→ /login)', timeout: t, (
    tester,
  ) async {
    await harness.pumpApp(
      tester,
      initialLocation: AppConstants.routeHistory,
      referenceRepository: ArticleRepository.fromRaw(p8p9ReferenceFixtures),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HistoryScreen), findsNothing);
    expect(find.widgetWithText(AppBar, 'Авторизация'), findsOneWidget);
  });

  testWidgets(
    'открыл статью → она в истории, заголовок секции на месте',
    timeout: t,
    (tester) async {
      await registerAndView(tester);
      await openHistory(tester);

      expect(find.byType(HistoryScreen), findsOneWidget);
      expect(find.byKey(const Key('history-section-title')), findsOneWidget);
      expect(find.text('Недавно смотрели'), findsOneWidget);
      expect(find.byKey(const Key('history-entry-fx_syn_var')), findsOneWidget);
      expect(find.text('Переменные'), findsOneWidget);
      // Кнопка «Очистить» есть — есть что чистить.
      expect(find.byKey(const Key('history-clear')), findsOneWidget);
    },
  );

  testWidgets('порядок: свежий просмотр выше (две статьи)', timeout: t, (
    tester,
  ) async {
    await registerAndView(tester, articles: ['fx_syn_var', 'fx_stl_vector']);
    await openHistory(tester);

    final varTop = tester.getTopLeft(
      find.byKey(const Key('history-entry-fx_syn_var')),
    );
    final vecTop = tester.getTopLeft(
      find.byKey(const Key('history-entry-fx_stl_vector')),
    );
    // fx_stl_vector открыта последней — выше.
    expect(vecTop.dy, lessThan(varTop.dy));
  });

  testWidgets(
    'очистка: диалог → подтверждение → пусто + снекбар «История очищена»',
    timeout: t,
    (tester) async {
      await registerAndView(tester);
      await openHistory(tester);
      expect(find.byKey(const Key('history-entry-fx_syn_var')), findsOneWidget);

      await openClearDialog(tester);
      expect(find.text('Очистить историю?'), findsOneWidget);

      await harness.tapAndWaitReal(tester, const Key('history-clear-confirm'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const Key('history-empty')), findsOneWidget);
      expect(find.text('История пуста'), findsOneWidget);
      expect(find.text('История очищена'), findsOneWidget);
      // Кнопки «Очистить» больше нет.
      expect(find.byKey(const Key('history-clear')), findsNothing);

      await drainSnackBar(tester);
    },
  );

  testWidgets('очистка: отмена в диалоге сохраняет список', timeout: t, (
    tester,
  ) async {
    await registerAndView(tester);
    await openHistory(tester);
    expect(find.byKey(const Key('history-entry-fx_syn_var')), findsOneWidget);

    await openClearDialog(tester);
    expect(find.text('Очистить историю?'), findsOneWidget);

    // Отмена: чистый UI-тап, реальной IO нет.
    await tester.tap(find.byKey(const Key('history-clear-cancel')));
    await tester.pumpAndSettle();

    // Запись осталась, диалог закрыт.
    expect(find.byKey(const Key('history-entry-fx_syn_var')), findsOneWidget);
    expect(find.text('Очистить историю?'), findsNothing);
    expect(find.byKey(const Key('history-clear')), findsOneWidget);
  });

  testWidgets(
    'пустая история: EmptyState и кнопки «Очистить» нет',
    timeout: t,
    (tester) async {
      await harness.registerUser(tester);
      await harness.pumpApp(
        tester,
        initialLocation: AppConstants.routeHistory,
        referenceRepository: ArticleRepository.fromRaw(p8p9ReferenceFixtures),
      );
      await tester.pumpAndSettle();
      await harness.settleRealIo(tester);

      expect(find.byKey(const Key('history-empty')), findsOneWidget);
      expect(find.byKey(const Key('history-clear')), findsNothing);
      expect(find.byKey(const Key('history-section-title')), findsNothing);
    },
  );

  testWidgets('переход из истории в статью рендерит статью', timeout: t, (
    tester,
  ) async {
    await registerAndView(tester);
    await openHistory(tester);
    expect(find.byKey(const Key('history-entry-fx_syn_var')), findsOneWidget);

    await tester.tap(find.byKey(const Key('history-entry-fx_syn_var')));
    await tester.pumpAndSettle();
    await harness.settleRealIo(tester);

    expect(find.byType(ArticleScreen), findsOneWidget);
    // История не дублируется: одна строка на статью.
    expect(
      find.byKey(const Key('history-entry-fx_syn_var')).evaluate().length,
      findsOneWidget,
    );
  });
}
