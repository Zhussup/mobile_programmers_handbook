import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mob_kurs/core/constants/app_constants.dart';
import 'package:mob_kurs/features/playground/snippet_model.dart';
import 'package:mob_kurs/features/playground/snippet_repository.dart';
import 'package:mob_kurs/features/playground/screens/snippet_editor_screen.dart';
import 'package:mob_kurs/features/reference/article_repository.dart';

import 'fixtures.dart';
import 'harness.dart';

/// Виджет-тест generation-токенов (P13): `/playground/edit/:id` при СМЕНЕ
/// ПОЛЬЗОВАТЕЛЯ, пока загрузка сниппетов ещё в полёте — канон
/// [UserScopedProvider]: устаревший ответ не применяется.
///
/// Виджет-уровень: данные user1 не должны подставиться в редактор user2;
/// экран обязан показать «Сниппет не найден», а данные user1 должны остаться
/// в БД нетронутыми (изоляция — logout ничего не удаляет).
void main() {
  final harness = AppHarness();

  setUp(() => harness.setUp());
  tearDown(() => harness.tearDown());

  const t = Timeout(Duration(seconds: 120));

  testWidgets(
    'edit/:id: пользователь сменился в середине загрузки — данные user1 не подставлены',
    timeout: t,
    (tester) async {
      // 1. «Прошлый запуск»: user1 вошёл, его сниппет в БД.
      await harness.registerUser(tester);
      final user1 = harness.session.currentUser!;
      await tester.runAsync(() async {
        await SnippetRepository(db: harness.db).create(
          userId: user1.id,
          title: 'Сниппет user1',
          language: SnippetLanguage.cpp,
          code: 'int secret = 1;',
        );
      });

      // 2. Второй пользователь — в БД, но ещё не вошёл.
      await harness.seedUser(
        tester,
        username: 'user2',
        email: 'user2@example.com',
        password: 'пароль123',
      );

      // 3. ЕДИНСТВЕННЫЙ pump /playground/edit/<id> под user1: провайдер
      //    создан, первая загрузка user1 в полёте (settle НЕ зовём —
      //    нужен разгар загрузки; следующий «кадр» придёт после смены).
      await harness.pumpApp(
        tester,
        initialLocation: AppConstants.snippetEditPath(1),
        referenceRepository: ArticleRepository.fromRaw(p8p9ReferenceFixtures),
      );

      // 4. Смена пользователя ПОСЛЕ старта загрузки: logout user1 → вход
      //    user2. При каждом notify сессии провайдер начинает перезагрузку —
      //    «в полёте» ответ user1 устаревает по generation-токену.
      await tester.runAsync(() async {
        await harness.session.logout();
        await harness.session.login(
          loginOrEmail: 'user2',
          password: 'пароль123',
        );
      });
      await harness.settleRealIo(tester);
      await tester.pumpAndSettle();
      await harness.settleRealIo(tester);
      await tester.pumpAndSettle();
      await tester.pump();

      // 5. Редактор не подставил чужие данные: экран-заглушка «не найден».
      expect(find.byType(SnippetEditorScreen), findsOneWidget);
      expect(find.byKey(const Key('snippet-not-found')), findsOneWidget);
      expect(find.text('Сниппет user1'), findsNothing);
      expect(
        find.byType(CodeField),
        findsNothing,
        reason: 'форма не строится, пока сниппет не подтверждён',
      );

      // 6. Данные user1 не потеряны: сниппет остался в БД под user1
      //    (logout ничего не удаляет).
      final user1Id = user1.id;
      await tester.runAsync(() async {
        final rows = await harness.db.query(
          'user_snippets',
          where: 'user_id = ?',
          whereArgs: [user1Id],
        );
        expect(rows, hasLength(1));
        expect(rows.single['title'], 'Сниппет user1');
      });
    },
  );

  testWidgets(
    'edit/:id: после смены пользователя вернулся user1 — его сниппет открывается',
    timeout: t,
    (tester) async {
      // Сниппет user1 в БД; user2 сеансом не владеет (см. сценарий выше).
      await harness.registerUser(tester);
      await tester.runAsync(() async {
        final user1 = harness.session.currentUser!;
        await SnippetRepository(db: harness.db).create(
          userId: user1.id,
          title: 'Сниппет user1',
          language: SnippetLanguage.cpp,
          code: 'int secret = 1;',
        );
      });

      await harness.pumpApp(
        tester,
        initialLocation: AppConstants.routePlayground,
        referenceRepository: ArticleRepository.fromRaw(p8p9ReferenceFixtures),
      );
      await tester.pumpAndSettle();
      await harness.settleRealIo(tester);

      // Открыть редактирование своего сниппета: предзаполнение на месте.
      harness.goRoute(tester, AppConstants.snippetEditPath(1));
      await tester.pumpAndSettle();
      await harness.settleRealIo(tester);

      expect(find.byKey(const Key('snippet-not-found')), findsNothing);
      expect(find.text('Сниппет user1'), findsOneWidget);
      final field = tester.widget<CodeField>(
        find.byKey(const Key('snippet-code-editor')),
      );
      expect(field.controller.text, 'int secret = 1;');
    },
  );
}
