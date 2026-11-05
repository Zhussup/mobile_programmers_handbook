import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mob_kurs/features/playground/screens/snippet_editor_screen.dart';
import 'package:mob_kurs/features/reference/article_repository.dart';
import 'package:mob_kurs/features/reference/screens/article_screen.dart';

import 'fixtures.dart';
import 'harness.dart';

/// E2E-сценарий песочницы (P13): статья → «Открыть в песочнике» →
/// сохранить сниппет → правка → удаление — одним живым прогоном через
/// экраны приложения (критерий «функции корректно взаимосвязаны»).
///
/// БД-операции (создание/правка/удаление) — реальная IO: тапы по их кнопкам
/// через [AppHarness.tapAndWaitReal], навигации — в fake-времени.
void main() {
  final harness = AppHarness();

  setUp(() => harness.setUp());
  tearDown(() => harness.tearDown());

  const t = Timeout(Duration(seconds: 120));

  /// Дренаж снекбара (см. канон).
  Future<void> drainSnackBar(WidgetTester tester) async {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(seconds: 5));
    });
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 1));
  }

  /// Текст контроллера редактора кода.
  CodeController codeController(WidgetTester tester) {
    final field = tester.widget<CodeField>(
      find.byKey(const Key('snippet-code-editor')),
    );
    return field.controller;
  }

  testWidgets(
    'статья → копия в песочнице → сохранить → правка → удалить (e2e)',
    timeout: t,
    (tester) async {
      // 1. Открыта статья (фикстурный контент) — история пишется (P9).
      await harness.registerUser(tester);
      await harness.pumpApp(
        tester,
        initialLocation: '/article/fx_syn_var',
        referenceRepository: ArticleRepository.fromRaw(p8p9ReferenceFixtures),
      );
      await tester.pumpAndSettle();
      await harness.settleRealIo(tester);
      expect(find.byType(ArticleScreen), findsOneWidget);

      // 2. «Открыть в песочнице»: черновик с кодом статьи → редактор создания.
      await tester.tap(find.byKey(const Key('article-open-in-playground')));
      await tester.pumpAndSettle();
      expect(find.byType(SnippetEditorScreen), findsOneWidget);
      expect(find.text('Новый сниппет'), findsOneWidget);
      expect(codeController(tester).text, 'int main() { return 0; }');

      // 3. Название + сохранение: сниппет появляется в списке песочницы.
      await tester.enterText(
        find.byKey(const Key('snippet-title')),
        'Копия из статьи',
      );
      await harness.tapAndWaitReal(tester, const Key('snippet-save'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('playground-empty')), findsNothing);
      expect(find.text('Копия из статьи'), findsOneWidget);
      expect(find.text('Сохранено'), findsOneWidget);
      await drainSnackBar(tester);

      // 4. Правка: карточка → предзаполнение → новое имя и код → сохранить.
      await tester.tap(find.byKey(const Key('snippet-card-title')));
      await tester.pumpAndSettle();
      expect(find.text('Редактирование'), findsOneWidget);
      expect(find.text('Копия из статьи'), findsOneWidget);
      expect(codeController(tester).text, 'int main() { return 0; }');

      await tester.enterText(
        find.byKey(const Key('snippet-title')),
        'Копия v2',
      );
      await tester.enterText(
        find.byKey(const Key('snippet-code-editor')),
        'int b = 7;',
      );
      await harness.tapAndWaitReal(tester, const Key('snippet-save'));
      await tester.pumpAndSettle();

      // Список: обновлённая карточка, прежнего имени нет.
      expect(find.text('Копия v2'), findsOneWidget);
      expect(find.text('Копия из статьи'), findsNothing);
      expect(find.text('Сохранено'), findsOneWidget);
      await drainSnackBar(tester);

      // 5. Удаление: карточка → «Удалить» → диалог → пустой список + снекбар.
      await tester.tap(find.byKey(const Key('snippet-card-title')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('snippet-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('snippet-delete')));
      await tester.pumpAndSettle();
      expect(find.text('Удалить сниппет?'), findsOneWidget);

      await tester.tap(find.byKey(const Key('snippet-delete-confirm')));
      await tester.pumpAndSettle();
      await harness.settleRealIo(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('playground-empty')), findsOneWidget);
      expect(find.text('Копия v2'), findsNothing);
      expect(find.text('Удалено'), findsOneWidget);
      await drainSnackBar(tester);
    },
  );

  testWidgets(
    'e2e: после полного цикла сниппетов в БД не осталось строк (delete удалён)',
    timeout: t,
    (tester) async {
      // Упрощённая проверка «чистоты» сценария: создаём и удаляем один
      // сниппет, затем читаем таблицу напрямую.
      await harness.registerUser(tester);
      await harness.pumpApp(
        tester,
        initialLocation: '/article/fx_syn_var',
        referenceRepository: ArticleRepository.fromRaw(p8p9ReferenceFixtures),
      );
      await tester.pumpAndSettle();
      await harness.settleRealIo(tester);

      await tester.tap(find.byKey(const Key('article-open-in-playground')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('snippet-title')),
        'ВрЕмЕнный',
      );
      await harness.tapAndWaitReal(tester, const Key('snippet-save'));
      await tester.pumpAndSettle();
      await drainSnackBar(tester);

      await tester.tap(find.byKey(const Key('snippet-card-title')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('snippet-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('snippet-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('snippet-delete-confirm')));
      await tester.pumpAndSettle();
      await harness.settleRealIo(tester);
      await tester.pumpAndSettle();

      // В БД не осталось сниппетов этого пользователя (delete — DELETE в БД,
      // не «скрытие»).
      final userId = harness.session.currentUser!.id;
      await tester.runAsync(() async {
        final rows = await harness.db.query(
          'user_snippets',
          where: 'user_id = ?',
          whereArgs: [userId],
        );
        expect(rows, isEmpty);
      });
    },
  );
}
