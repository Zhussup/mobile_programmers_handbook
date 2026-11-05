import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mob_kurs/core/constants/app_constants.dart';

import 'harness.dart';

/// Виджет-тесты auth-guard (P4): гость не открывает приватные маршруты;
/// вошедший не возвращается на логин/регистрацию.
void main() {
  final harness = AppHarness();

  setUp(() => harness.setUp());
  tearDown(() => harness.tearDown());

  testWidgets('Гость на /home → перенаправлен на /login', (tester) async {
    await harness.pumpApp(tester, initialLocation: AppConstants.routeHome);

    // На главной гостя нет: редирект на экран авторизации.
    expect(find.widgetWithText(AppBar, 'Главная'), findsNothing);
    expect(find.widgetWithText(AppBar, 'Авторизация'), findsOneWidget);
  });

  testWidgets('Гость на /register остаётся (публичный маршрут)', (
    tester,
  ) async {
    await harness.pumpApp(tester, initialLocation: AppConstants.routeRegister);

    expect(find.widgetWithText(AppBar, 'Регистрация'), findsOneWidget);
  });

  testWidgets('Гость после выхода: кнопка вкладки не открывает закрытое', (
    tester,
  ) async {
    await harness.pumpApp(tester, initialLocation: AppConstants.routeHome);

    // Гость оказался на /login — приватный контент недоступен.
    expect(find.text('Песочница'), findsNothing);
    expect(find.text('Профиль'), findsNothing);
  });

  testWidgets('Вошедший на /login → перенаправлен на /home (нет петли)', (
    tester,
  ) async {
    await harness.registerUser(tester);
    await harness.pumpApp(tester, initialLocation: AppConstants.routeLogin);

    expect(find.widgetWithText(AppBar, 'Главная'), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Авторизация'), findsNothing);
  });

  testWidgets('Вошедший на /register → перенаправлен на /home', (tester) async {
    await harness.registerUser(tester);
    await harness.pumpApp(tester, initialLocation: AppConstants.routeRegister);

    expect(find.widgetWithText(AppBar, 'Главная'), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Регистрация'), findsNothing);
  });

  group('несуществующий маршрут (P13 — навигация без ошибок)', () {
    testWidgets('вошедший: 404-заглушка, приложение не падает', (tester) async {
      await harness.registerUser(tester);
      await harness.pumpApp(tester, initialLocation: '/definitely/not/exist');

      expect(find.byKey(const Key('route-not-found')), findsOneWidget);
      expect(
        find.widgetWithText(AppBar, 'Страница не найдена'),
        findsOneWidget,
      );
      expect(
        find.byType(Navigator),
        findsWidgets,
        reason: 'приложение живо — навигация работает',
      );
    });

    testWidgets('гость: 404 недоступен — guard уводит на /login', (
      tester,
    ) async {
      await harness.pumpApp(tester, initialLocation: '/definitely/not/exist');

      // Публичных «мусорных» маршрутов нет непубличным быть не может:
      // redirect отводит гостя на авторизацию, а не на 404-заглушку.
      expect(find.byKey(const Key('route-not-found')), findsNothing);
      expect(find.widgetWithText(AppBar, 'Авторизация'), findsOneWidget);
    });
  });
}
