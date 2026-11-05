import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mob_kurs/core/constants/app_constants.dart';
import 'package:mob_kurs/features/reference/article_repository.dart';
import 'package:mob_kurs/features/home/screens/home_screen.dart';
import 'package:mob_kurs/features/reference/screens/article_screen.dart';

import 'fixtures.dart';
import 'harness.dart';

/// Виджет-тесты «Продолжить» на home (P9): история есть → секция с
/// карточками; истории нет → секция скрыта; лимит — 5 записей.
void main() {
  final harness = AppHarness();

  setUp(() => harness.setUp());
  tearDown(() => harness.tearDown());

  const t = Timeout(Duration(seconds: 60));

  /// Зарегистрировать пользователя и просмотреть статьи (запись истории —
  /// реальная IO, после каждого открытия settleRealIo).
  Future<void> registerAndView(
    WidgetTester tester,
    List<String> articles,
  ) async {
    await harness.registerUser(tester);
    await harness.pumpApp(
      tester,
      initialLocation: '/article/${articles.first}',
      referenceRepository: ArticleRepository.fromRaw(p8p9ReferenceFixtures),
    );
    await tester.pumpAndSettle();
    await harness.settleRealIo(tester);

    for (final id in articles.skip(1)) {
      harness.goRoute(tester, '/article/$id');
      await tester.pumpAndSettle();
      await harness.settleRealIo(tester);
    }

    // Возврат на вкладку «Главная».
    harness.goRoute(tester, AppConstants.routeHome);
    await tester.pumpAndSettle();
  }

  testWidgets('история есть → секция «Продолжить» с карточками', timeout: t, (
    tester,
  ) async {
    await registerAndView(tester, ['fx_syn_var', 'fx_stl_vector']);

    expect(find.byType(HomeScreen), findsOneWidget, reason: 'мы на «Главной»');
    expect(find.widgetWithText(AppBar, 'Главная'), findsOneWidget);
    expect(find.text('Продолжить'), findsOneWidget);
    expect(find.byKey(const Key('home-recent-fx_syn_var')), findsOneWidget);
    expect(find.byKey(const Key('home-recent-fx_stl_vector')), findsOneWidget);

    // Свежий просмотр выше.
    final varTop = tester.getTopLeft(
      find.byKey(const Key('home-recent-fx_syn_var')),
    );
    final vecTop = tester.getTopLeft(
      find.byKey(const Key('home-recent-fx_stl_vector')),
    );
    expect(vecTop.dy, lessThan(varTop.dy));
  });

  testWidgets('истории нет → секция «Продолжить» скрыта', timeout: t, (
    tester,
  ) async {
    await harness.registerUser(tester);
    await harness.pumpApp(
      tester,
      initialLocation: AppConstants.routeHome,
      referenceRepository: ArticleRepository.fromRaw(p8p9ReferenceFixtures),
    );
    await tester.pumpAndSettle();
    await harness.settleRealIo(tester);

    expect(find.text('Продолжить'), findsNothing);
    expect(find.text('Категории'), findsOneWidget);
  });

  testWidgets(
    '"Продолжить" показывает не больше 5 карточек (лимит homeRecentLimit)',
    timeout: t,
    (tester) async {
      // Шесть статей в фикстурной категории.
      final repo = ArticleRepository.fromRaw([
        fixtureCategory(
          id: 'big',
          title: 'Большая категория',
          articles: [
            for (var i = 1; i <= 6; i++)
              fixtureArticle(id: 'fx_big_$i', title: 'Статья $i'),
          ],
        ),
      ]);
      final ids = [for (var i = 1; i <= 6; i++) 'fx_big_$i'];

      await harness.registerUser(tester);
      await harness.pumpApp(
        tester,
        initialLocation: '/article/${ids.first}',
        referenceRepository: repo,
      );
      await tester.pumpAndSettle();
      await harness.settleRealIo(tester);

      for (final id in ids.skip(1)) {
        harness.goRoute(tester, '/article/$id');
        await tester.pumpAndSettle();
        await harness.settleRealIo(tester);
      }

      harness.goRoute(tester, AppConstants.routeHome);
      await tester.pumpAndSettle();

      expect(find.text('Продолжить'), findsOneWidget);
      expect(find.byKey(const Key('home-recent-fx_big_6')), findsOneWidget);
      // Нижние карточки построены лениво — скроллим до fx_big_2.
      await tester.scrollUntilVisible(
        find.byKey(const Key('home-recent-fx_big_2')),
        150,
        scrollable: find
            .descendant(
              of: find.byType(HomeScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home-recent-fx_big_2')), findsOneWidget);
      // Самая старая (первая) — за пределами секции «Продолжить».
      expect(find.byKey(const Key('home-recent-fx_big_1')), findsNothing);
    },
  );

  testWidgets('тап по карточке «Продолжить» открывает статью', timeout: t, (
    tester,
  ) async {
    await registerAndView(tester, ['fx_syn_var']);

    expect(find.byKey(const Key('home-recent-fx_syn_var')), findsOneWidget);
    await tester.tap(find.byKey(const Key('home-recent-fx_syn_var')));
    await tester.pumpAndSettle();
    await harness.settleRealIo(tester);

    expect(find.byType(ArticleScreen), findsOneWidget);
    expect(find.text('Переменные'), findsOneWidget);
  });

  testWidgets('иконка истории в AppBar home открывает /history', timeout: t, (
    tester,
  ) async {
    await harness.registerUser(tester);
    await harness.pumpApp(
      tester,
      initialLocation: AppConstants.routeHome,
      referenceRepository: ArticleRepository.fromRaw(p8p9ReferenceFixtures),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('home-open-history')));
    await tester.pumpAndSettle();
    await harness.settleRealIo(tester);

    expect(find.byKey(const Key('history-empty')), findsOneWidget);
  });
}
