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
}
