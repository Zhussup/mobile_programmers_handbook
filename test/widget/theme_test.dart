import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mob_kurs/core/constants/app_constants.dart';
import 'package:mob_kurs/features/profile/theme_provider.dart';
import 'package:mob_kurs/features/reference/article_repository.dart';

import 'fixtures.dart';
import 'harness.dart';

/// Тема оформления (P12/P13): единый тёмный режим на всех экранах
/// (критерий «тёмная тема везде, ничего не блещет») и persist: переключение
/// на профиле → рестарт → та же тема (ключ `session_theme`).
///
/// Проверки по коду виджетов: MaterialApp.themeMode, яркость ThemeData, и
/// темы подсветки кода (atom-one-dark — и в блоке статьи, и в редакторе).
void main() {
  final harness = AppHarness();

  setUp(() => harness.setUp());
  tearDown(() => harness.tearDown());

  /// Тёмный ли у корневого MaterialApp режим.
  ThemeMode appMode(WidgetTester tester) =>
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode!;

  /// Яркость темы первого Scaffold (одинакова для всех — тема единая).
  Brightness scaffoldBrightness(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(Scaffold).first)).brightness;

  testWidgets(
    'тёмная тема на всех экранах: главная, справочник, статья, редактор, профиль',
    timeout: const Timeout(Duration(seconds: 120)),
    (tester) async {
      await harness.registerUser(tester);
      await harness.pumpApp(
        tester,
        initialLocation: AppConstants.routeHome,
        referenceRepository: ArticleRepository.fromRaw(p8p9ReferenceFixtures),
        themeMode: ThemeMode.dark,
      );
      await tester.pumpAndSettle();

      // Первая вкладка: тёмный Scaffold.
      expect(appMode(tester), ThemeMode.dark);
      expect(scaffoldBrightness(tester), Brightness.dark);

      // Статья: блок кода — тёмная подсветка atom-one-dark.
      harness.goRoute(tester, '/article/fx_syn_var');
      await tester.pumpAndSettle();
      await harness.settleRealIo(tester);
      expect(find.text('Переменные'), findsOneWidget);
      expect(scaffoldBrightness(tester), Brightness.dark);
      final highlight = tester.widget<HighlightView>(
        find.byType(HighlightView),
      );
      expect(
        highlight.theme['root']?.backgroundColor,
        atomOneDarkTheme['root']!.backgroundColor,
        reason: 'блок кода статьи — тёмная тема подсветки',
      );

      // Редактор сниппета: та же тёмная тема подсветки (CodeTheme).
      harness.goRoute(tester, '/playground/new');
      await tester.pumpAndSettle();
      final codeTheme = tester.widget<CodeTheme>(find.byType(CodeTheme));
      expect(
        codeTheme.data!.styles['root']?.backgroundColor,
        atomOneDarkTheme['root']!.backgroundColor,
        reason: 'в редакторе кода — та же тёмная подсветка',
      );
      expect(scaffoldBrightness(tester), Brightness.dark);

      // Профиль: тёмный Scaffold и после смены ничего не «слепит».
      harness.goRoute(tester, AppConstants.routeProfile);
      await tester.pumpAndSettle();
      expect(scaffoldBrightness(tester), Brightness.dark);
    },
  );

  testWidgets(
    'переключение на профиле: сразу тёмная тема + запись в prefs',
    timeout: const Timeout(Duration(seconds: 120)),
    (tester) async {
      await harness.registerUser(tester);
      await harness.pumpApp(
        tester,
        initialLocation: AppConstants.routeProfile,
        referenceRepository: ArticleRepository.fromRaw(p8p9ReferenceFixtures),
        themeMode: ThemeMode.light,
      );
      await tester.pumpAndSettle();
      await harness.settleRealIo(tester);

      // Карточка «Тема оформления» может быть ниже видимой области.
      await tester.scrollUntilVisible(
        find.text('Тёмная'),
        150.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Тёмная'));
      await tester.pumpAndSettle();

      // СРАЗУ тёмная (без ожидания следующего запуска).
      expect(appMode(tester), ThemeMode.dark);
      expect(scaffoldBrightness(tester), Brightness.dark);

      // И сохранена в prefs (persist — ключ `session_theme`).
      expect(harness.prefs.getString(AppConstants.prefSessionTheme), 'dark');
    },
  );

  testWidgets(
    'перезапуск приложения: тема восстанавливается из prefs',
    timeout: const Timeout(Duration(seconds: 120)),
    (tester) async {
      // «Прошлый запуск» оставил в prefs тёмную тему.
      harness.prefs.setString(AppConstants.prefSessionTheme, 'dark');

      // Новый запуск: main() читает prefs ДО runApp (modeFromString).
      await harness.pumpApp(
        tester,
        initialLocation: AppConstants.routeHome,
        referenceRepository: ArticleRepository.fromRaw(p8p9ReferenceFixtures),
        themeMode: ThemeProvider.modeFromString(
          harness.prefs.getString(AppConstants.prefSessionTheme),
        ),
      );
      await tester.pumpAndSettle();

      expect(appMode(tester), ThemeMode.dark);
      expect(scaffoldBrightness(tester), Brightness.dark);
    },
  );
}
