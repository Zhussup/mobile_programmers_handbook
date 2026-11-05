import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mob_kurs/core/constants/app_constants.dart';
import 'package:mob_kurs/features/reference/article_repository.dart';
import 'package:mob_kurs/features/reference/favorites_repository.dart';
import 'package:mob_kurs/features/reference/screens/article_screen.dart';
import 'package:mob_kurs/features/reference/screens/favorites_screen.dart';

import 'fixtures.dart';
import 'harness.dart';

/// Виджет-тесты избранного (P9): сердечко в статье ↔ список избранного,
/// удаление с карточки, снекбары, EmptyState, auth-guard.
void main() {
  final harness = AppHarness();

  setUp(() => harness.setUp());
  tearDown(() => harness.tearDown());

  const t = Timeout(Duration(seconds: 60));

  /// Открыть /favorites на фикстурном контенте у зарегистрированного
  /// пользователя.
  Future<void> pumpFavorites(WidgetTester tester) async {
    await harness.registerUser(tester);
    // Сидинг избранного через репозиторий (реальная IO — в runAsync).
    await tester.runAsync(() async {
      final repository = FavoritesRepository(db: harness.db);
      await repository.toggle(harness.session.currentUser!.id, 'fx_syn_var');
      await repository.toggle(harness.session.currentUser!.id, 'fx_stl_vector');
    });
    await harness.pumpApp(
      tester,
      initialLocation: AppConstants.routeFavorites,
      referenceRepository: ArticleRepository.fromRaw(p8p9ReferenceFixtures),
    );
    await tester.pumpAndSettle();
    // Первая загрузка провайдера — реальная IO: дать ей завершиться в
    // реальном цикле событий (подводный камень №3).
    await harness.settleRealIo(tester);
  }

  /// Дренаж снекбара (подводный камень №6): снекбар показан ВНУТРИ
  /// runAsync-окна — его 4-секундный таймер назначен в реальной зоне,
  /// поэтому сначала выжидаем реальное время (иначе таймер стреляет уже
  /// после teardown), затем доигрываем fake-время анимаций.
  Future<void> drainSnackBar(WidgetTester tester) async {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(seconds: 5));
    });
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('гость: /favorites закрыт auth-guard (→ /login)', timeout: t, (
    tester,
  ) async {
    await harness.pumpApp(
      tester,
      initialLocation: AppConstants.routeFavorites,
      referenceRepository: ArticleRepository.fromRaw(p8p9ReferenceFixtures),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FavoritesScreen), findsNothing);
    expect(find.widgetWithText(AppBar, 'Авторизация'), findsOneWidget);
  });

  testWidgets('список избранного: карточки + переход в статью', timeout: t, (
    tester,
  ) async {
    await pumpFavorites(tester);

    expect(find.byType(FavoritesScreen), findsOneWidget);
    expect(find.byKey(const Key('favorites-entry-fx_syn_var')), findsOneWidget);
    expect(
      find.byKey(const Key('favorites-entry-fx_stl_vector')),
      findsOneWidget,
    );
    expect(find.text('Переменные'), findsOneWidget);
    expect(find.text('Vector'), findsOneWidget);
    // Свежие раньше: последней добавляемую мы seeded первой... порядок:
    // fx_stl_vector добавлена второй — она выше.
    final varTop = tester.getTopLeft(
      find.byKey(const Key('favorites-entry-fx_syn_var')),
    );
    final vecTop = tester.getTopLeft(
      find.byKey(const Key('favorites-entry-fx_stl_vector')),
    );
    expect(vecTop.dy, lessThan(varTop.dy));

    // Переход в статью по тапу карточки.
    await tester.tap(find.byKey(const Key('favorites-entry-fx_syn_var')));
    await tester.pumpAndSettle();
    await harness.settleRealIo(tester);
    expect(find.byType(ArticleScreen), findsOneWidget);
  });

  testWidgets('удаление с карточки: снекбар + EmptyState', timeout: t, (
    tester,
  ) async {
    await pumpFavorites(tester);

    await harness.tapAndWaitReal(
      tester,
      const Key('favorite-remove-fx_syn_var'),
    );

    expect(find.text('Удалено из избранного'), findsOneWidget);
    // Вторая запись — Vector — осталась; список НЕ пуст.
    expect(find.byKey(const Key('favorites-entry-fx_syn_var')), findsNothing);
    expect(
      find.byKey(const Key('favorites-entry-fx_stl_vector')),
      findsOneWidget,
    );

    // Доснимаем вторую запись — теперь пусто.
    await harness.tapAndWaitReal(
      tester,
      const Key('favorite-remove-fx_stl_vector'),
    );
    expect(find.byKey(const Key('favorites-empty')), findsOneWidget);

    await drainSnackBar(tester);
  });

  testWidgets(
    'сердечко в статье: добавление → снекбар и filled-иконка',
    timeout: t,
    (tester) async {
      await harness.registerUser(tester);
      await harness.pumpApp(
        tester,
        initialLocation: '/article/fx_syn_var',
        referenceRepository: ArticleRepository.fromRaw(p8p9ReferenceFixtures),
      );
      await tester.pumpAndSettle();
      await harness.settleRealIo(tester);

      // Сначала не в избранном.
      expect(find.byKey(const Key('article-favorite')), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);

      await harness.tapAndWaitReal(tester, const Key('article-favorite'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Добавлено в избранное'), findsOneWidget);
      expect(find.byIcon(Icons.favorite), findsOneWidget);
      await drainSnackBar(tester);
    },
  );

  testWidgets(
    'сердечко в статье: повторный toggle → удалено, outline-иконка',
    timeout: t,
    (tester) async {
      await harness.registerUser(tester);
      await harness.pumpApp(
        tester,
        initialLocation: '/article/fx_syn_var',
        referenceRepository: ArticleRepository.fromRaw(p8p9ReferenceFixtures),
      );
      await tester.pumpAndSettle();
      await harness.settleRealIo(tester);

      await harness.tapAndWaitReal(tester, const Key('article-favorite'));
      expect(find.text('Добавлено в избранное'), findsOneWidget);
      await drainSnackBar(tester);

      await harness.tapAndWaitReal(tester, const Key('article-favorite'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Удалено из избранного'), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      await drainSnackBar(tester);
    },
  );
}
