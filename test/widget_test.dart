import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mob_kurs/app.dart';
import 'package:mob_kurs/core/constants/app_constants.dart';

/// Смок-тест каркаса (P0/P1): приложение строится, сплэш показывает
/// логотип и название, затем срабатывает таймер сплэша (переход на
/// экран авторизации).
void main() {
  const appName = AppConstants.appName;

  Future<SharedPreferences> preparePrefs() async {
    SharedPreferences.setMockInitialValues({});
    return SharedPreferences.getInstance();
  }

  testWidgets('Смок-тест: приложение строится, сплэш содержит название',
      (tester) async {
    final prefs = await preparePrefs();

    await tester.pumpWidget(
      MobKursApp(prefs: prefs, initialThemeMode: ThemeMode.system),
    );

    // Сплэш: название приложения на экране.
    expect(find.text(appName), findsOneWidget);
    expect(find.text('C++ и Dart/Flutter с примерами кода'), findsOneWidget);
    // Логотип присутствует.
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('Смок-тест: сплэш через таймер открывает экран авторизации',
      (tester) async {
    final prefs = await preparePrefs();

    await tester.pumpWidget(
      MobKursApp(prefs: prefs, initialThemeMode: ThemeMode.system),
    );

    // Прокрутить таймер сплэша (1.5 с) и дождаться перехода.
    await tester.pump(AppConstants.splashDuration + const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Авторизация'), findsOneWidget);
  });
}