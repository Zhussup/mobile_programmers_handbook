import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mob_kurs/core/constants/app_constants.dart';
import 'package:mob_kurs/features/playground/snippet_model.dart';
import 'package:mob_kurs/features/playground/snippet_provider.dart';
import 'package:mob_kurs/features/playground/screens/playground_screen.dart';
import 'package:mob_kurs/features/playground/screens/snippet_editor_screen.dart';
import 'package:mob_kurs/features/reference/article_repository.dart';

import 'fixtures.dart';
import 'harness.dart';

/// Виджет-тесты песочницы (P10): список + создание (FAB), удаление с
/// диалогом, редактирование и одноразовый черновик «Открыть в песочнице»
/// из статьи (подводный камень №8 из плана: маршрут без аргументов, данные
/// — через draft-провайдер).
///
/// БД-операции (create/update/delete сниппета) — реальная IO: тапы по их
/// кнопкам — через [AppHarness.tapAndWaitReal], навигации — в fake-времени.
void main() {
  final harness = AppHarness();

  setUp(() => harness.setUp());
  tearDown(() => harness.tearDown());

  const t = Timeout(Duration(seconds: 90));

  /// Дренаж снекбара: реальный 4-секундный таймер затем fake-время анимаций.
  Future<void> drainSnackBar(WidgetTester tester) async {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(seconds: 5));
    });
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 1));
  }

  /// Текст контроллера редактора кода (проверка подсветки/предзаполнения).
  CodeController codeController(WidgetTester tester) {
    final field = tester.widget<CodeField>(
      find.byKey(const Key('snippet-code-editor')),
    );
    return field.controller;
  }

  /// Открыть песочницу зарегистрированного пользователя (пустой список).
  Future<void> openPlayground(WidgetTester tester) async {
    await harness.registerUser(tester);
    await harness.pumpApp(
      tester,
      initialLocation: AppConstants.routePlayground,
      referenceRepository: ArticleRepository.fromRaw(p8p9ReferenceFixtures),
    );
    await tester.pumpAndSettle();
    // Стартовая перезагрузка сниппетов — реальная IO.
    await harness.settleRealIo(tester);
    expect(find.byKey(const Key('playground-empty')), findsOneWidget);
  }

  /// Создать сниппет через ПРОВАЙДЕР ПРИЛОЖЕНИЯ (список и уведомления — как
  /// в живом сценарии). Текущий экран — /playground со свежим списком.
  Future<void> createViaProvider(
    WidgetTester tester, {
    required String title,
    String code = 'int a;',
    SnippetLanguage language = SnippetLanguage.cpp,
    String? output,
  }) async {
    final context = tester.element(find.byKey(const Key('playground-fab')));
    final provider = context.read<SnippetProvider>();
    await tester.runAsync(() async {
      await provider.create(
        title: title,
        language: language,
        code: code,
        expectedOutput: output,
      );
    });
    await tester.pumpAndSettle();
  }

  testWidgets(
    'создание: FAB → форма → сохранить → карточка на месте',
    timeout: t,
    (tester) async {
      await openPlayground(tester);
      expect(find.byKey(const Key('playground-fab')), findsOneWidget);

      // FAB → экран создания.
      await tester.tap(find.byKey(const Key('playground-fab')));
      await tester.pumpAndSettle();
      expect(find.byType(SnippetEditorScreen), findsOneWidget);
      expect(find.text('Новый сниппет'), findsOneWidget);

      // Заполнение формы: имя, язык по умолчанию C++, код.
      await tester.enterText(
        find.byKey(const Key('snippet-title')),
        'Переменная',
      );
      await tester.enterText(
        find.byKey(const Key('snippet-code-editor')),
        'int a = 5;',
      );

      // Сохранение: INSERT + снекбар + возврат к списку (реальная IO).
      await harness.tapAndWaitReal(tester, const Key('snippet-save'));
      await tester.pumpAndSettle();

      // Список перерисовался: карточка вместо EmptyState.
      expect(find.byKey(const Key('playground-empty')), findsNothing);
      expect(find.text('Переменная'), findsOneWidget);
      expect(find.textContaining('int a = 5;'), findsOneWidget);
      expect(find.text('Сохранено'), findsOneWidget);

      await drainSnackBar(tester);
    },
  );

  testWidgets(
    'создание: пустое название не сохраняется (валидация на месте)',
    timeout: t,
    (tester) async {
      await openPlayground(tester);

      await tester.tap(find.byKey(const Key('playground-fab')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('snippet-code-editor')),
        'int a;',
      );

      await harness.tapAndWaitReal(tester, const Key('snippet-save'));
      await tester.pumpAndSettle();

      // Всё ещё на экране редактора, с ошибкой у поля названия.
      expect(find.byType(SnippetEditorScreen), findsOneWidget);
      expect(find.text('Введите название сниппета'), findsOneWidget);
      // Снекбара сохранения нет.
      expect(find.text('Сохранено'), findsNothing);
    },
  );

  testWidgets(
    'редактирование: карточка → форма с данными → новое название видно',
    timeout: t,
    (tester) async {
      await openPlayground(tester);
      await createViaProvider(tester, title: 'Старое имя');

      // Открытие карточки → экран редактирования с предзаполнением.
      await tester.tap(find.byKey(const Key('snippet-card-title')));
      await tester.pumpAndSettle();
      expect(find.text('Редактирование'), findsOneWidget);
      expect(find.text('Старое имя'), findsOneWidget);
      expect(codeController(tester).text, 'int a;');

      // Меняем название и сохраняем (реальная IO).
      await tester.enterText(
        find.byKey(const Key('snippet-title')),
        'Новое имя',
      );
      await harness.tapAndWaitReal(tester, const Key('snippet-save'));
      await tester.pumpAndSettle();

      // Список показывает обновлённый заголовок.
      expect(find.text('Новое имя'), findsOneWidget);
      expect(find.text('Старое имя'), findsNothing);
      expect(find.text('Сохранено'), findsOneWidget);
      await drainSnackBar(tester);
    },
  );

  testWidgets(
    'удаление: диалог → подтверждение → сниппет исчез, снекбар «Удалено»',
    timeout: t,
    (tester) async {
      await openPlayground(tester);
      await createViaProvider(tester, title: 'Под удаление');

      await tester.tap(find.byKey(const Key('snippet-card-title')));
      await tester.pumpAndSettle();
      expect(find.text('Под удаление'), findsOneWidget);

      // Диалог подтверждения (кнопки на дне формы — прокрутить к ним).
      await tester.ensureVisible(find.byKey(const Key('snippet-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('snippet-delete')));
      await tester.pumpAndSettle();

      // Отмена в диалоге ничего не удаляет.
      await tester.tap(find.byKey(const Key('snippet-delete-cancel')));
      await tester.pumpAndSettle();
      expect(find.byType(SnippetEditorScreen), findsOneWidget);

      // Повтор: подтверждение — удаление (реальная IO) и возврат к списку.
      await tester.tap(find.byKey(const Key('snippet-delete')));
      await tester.pumpAndSettle();
      // Повтор: подтверждение — по канону (диалог): tap в fake-времени →
      // pop-анимация диалога доигрывается в pumpAndSettle, только после
      // этого начинается удаление — его БД-IO требует реального времени.
      await tester.tap(find.byKey(const Key('snippet-delete-confirm')));
      await tester.pumpAndSettle();
      await harness.settleRealIo(tester);
      // pop-анимация редактора и вводная анимация снекбара.
      await tester.pumpAndSettle();

      // Список пуст, карточки нет, снекбар наблюдаем (подводный камень №6).
      expect(find.byKey(const Key('playground-empty')), findsOneWidget);
      expect(find.text('Под удаление'), findsNothing);
      expect(find.text('Удалено'), findsOneWidget);
      await drainSnackBar(tester);
    },
  );

  testWidgets(
    '«Открыть в песочнице» из статьи: черновик подставлен, расходуется один раз',
    timeout: t,
    (tester) async {
      await harness.registerUser(tester);
      await harness.pumpApp(
        tester,
        initialLocation: '/article/fx_syn_var',
        referenceRepository: ArticleRepository.fromRaw(p8p9ReferenceFixtures),
      );
      await tester.pumpAndSettle();
      await harness.settleRealIo(tester); // postFrame-запись истории

      // Кнопка под код-блоком статьи.
      expect(
        find.byKey(const Key('article-open-in-playground')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('article-open-in-playground')));
      await tester.pumpAndSettle();

      // Вкладка песочницы: черновик сразу открыл редактор создания.
      expect(
        find.byType(PlaygroundScreen),
        findsNothing,
        reason: 'список под стеком — наверху редактор',
      );
      expect(find.byType(SnippetEditorScreen), findsOneWidget);
      expect(find.text('Новый сниппет'), findsOneWidget);
      expect(codeController(tester).text, 'int main() { return 0; }');
      expect(find.text('Сохранено'), findsNothing);

      // Отмена → список вкладки песочницы (без сниппетов пока нет).
      await tester.tap(find.byKey(const Key('snippet-cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('playground-empty')), findsOneWidget);

      // Черновик одноразовый: новое создание — пустой редактор.
      await tester.tap(find.byKey(const Key('playground-fab')));
      await tester.pumpAndSettle();
      expect(find.byType(SnippetEditorScreen), findsOneWidget);
      expect(codeController(tester).text, isEmpty);
    },
  );

  testWidgets(
    'маршрут /playground/edit/999999 без данных → EmptyState «не найден»',
    timeout: t,
    (tester) async {
      await openPlayground(tester);
      harness.goRoute(tester, AppConstants.snippetEditPath(999999));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('snippet-not-found')), findsOneWidget);
    },
  );
}
