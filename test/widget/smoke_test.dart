import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mob_kurs/core/constants/app_constants.dart';

import 'harness.dart';

/// Адаптированный смок-тест каркаса (P0/P1 + P2/P4 init-флоу):
/// приложение строится, сплэш показывает лого и название, таймер сплэша
/// ведёт на /login для гостя и на /home для вошедшего пользователя.
void main() {
  final harness = AppHarness();

  setUp(() => harness.setUp());
  tearDown(() => harness.tearDown());

  testWidgets('Смок-тест: приложение строится, сплэш содержит название',
      (tester) async {
    await harness.pumpApp(tester, initialLocation: AppConstants.routeSplash);

    // Сплэш: название приложения на экране.
    expect(find.text(AppConstants.appName), findsOneWidget);
    expect(find.text('C++ и Dart/Flutter с примерами кода'), findsOneWidget);
  });

  testWidgets('Смок-тест: сплэш гостя через таймер ведёт на /login',
      (tester) async {
    await harness.pumpApp(tester, initialLocation: AppConstants.routeSplash);

    // Прокрутить таймер сплэша (1.5 с) и дождаться перехода.
    await tester.pump(AppConstants.splashDuration + const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(find.widgetWithText(AppBar, 'Авторизация'), findsOneWidget);
  });

  testWidgets(
      'Смок-тест: при восстановленной сессии сплэш ведёт на /home (перезапуск '
      'сразу на главную, без логина)', (tester) async {
    // «Прошлый запуск»: пользователь зарегистрировался и вошёл.
    await harness.registerUser(tester);

    await harness.pumpApp(tester, initialLocation: AppConstants.routeSplash);
    expect(find.text(AppConstants.appName), findsOneWidget);

    // Таймер сплэша → /home.
    await tester.pump(AppConstants.splashDuration + const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(find.widgetWithText(AppBar, 'Главная'), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Авторизация'), findsNothing);
  });
}
