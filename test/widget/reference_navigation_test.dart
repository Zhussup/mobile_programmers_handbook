import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChannels;
import 'package:flutter_test/flutter_test.dart';

import 'package:mob_kurs/core/constants/app_constants.dart';
import 'package:mob_kurs/core/widgets/code_block.dart';
import 'package:mob_kurs/core/widgets/empty_state.dart';
import 'package:mob_kurs/features/reference/screens/article_screen.dart';
import 'package:mob_kurs/features/reference/screens/category_articles_screen.dart';

import 'harness.dart';

/// Виджет-тесты справочника на РЕАЛЬНОМ контенте (P6): главная → категория
/// → статья; вкладки без ошибок; неизвестные id → экран-заглушка.
void main() {
  final harness = AppHarness();

  setUp(() => harness.setUp());
  tearDown(() => harness.tearDown());

  const t = Timeout(Duration(seconds: 60));

  /// Открыть статью hello_world: /home → категория → статья.
  Future<void> openArticle(WidgetTester tester) async {
    await harness.pumpApp(tester, initialLocation: AppConstants.routeHome);

    await tester.tap(find.byKey(const Key('home-category-syntax')));
    await tester.pumpAndSettle();

    expect(find.byType(CategoryArticlesScreen), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Синтаксис C++'), findsOneWidget);

    await tester.tap(find.byKey(const Key('article-card-cpp_syn_hello_world')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Главная: приветствие по имени + категории + скрытая «Продолжить»',
    timeout: t,
    (tester) async {
      await harness.registerUser(tester);
      await harness.pumpApp(tester, initialLocation: AppConstants.routeHome);

      expect(find.text('Привет, user1!'), findsOneWidget);
      expect(find.byKey(const Key('home-category-syntax')), findsOneWidget);
      expect(find.byKey(const Key('home-category-algorithms')), findsOneWidget);
      // Истории нет — секция «Продолжить» скрыта (заготовка P9).
      expect(find.text('Продолжить'), findsNothing);
    },
  );

  testWidgets('Главная → категория → статья: блоки рендерятся', timeout: t, (
    tester,
  ) async {
    await harness.registerUser(tester);
    await openArticle(tester);

    // Статья: заголовок в AppBar, подзаголовок и код из контента.
    expect(
      find.widgetWithText(AppBar, 'Первая программа: Hello, World!'),
      findsOneWidget,
    );
    expect(find.text('Разбор файла построчно'), findsOneWidget);
    expect(find.byType(CodeBlock), findsOneWidget);
    expect(find.text('Показать вывод'), findsOneWidget);

    // Вывод программы раскрывается (сначала прокрутка — переключатель
    // может быть ниже видимой области).
    await tester.ensureVisible(find.byKey(const Key('output-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('output-toggle')));
    await tester.pump();
    expect(find.text('Hello, World!'), findsOneWidget);
  });

  testWidgets(
    'Список категории отсортирован: beginner раньше сложных',
    timeout: t,
    (tester) async {
      await harness.registerUser(tester);
      await harness.pumpApp(tester, initialLocation: AppConstants.routeHome);

      await tester.tap(find.byKey(const Key('home-category-algorithms')));
      await tester.pumpAndSettle();

      // Первая карточка — beginner «Условия…», последняя — intermediate.
      expect(find.text('Условия: if / else и switch'), findsOneWidget);
      expect(find.text('Рекурсия'), findsOneWidget);

      // Порядок по позициям: «Условия…» выше «Сортировки пузырьком».
      final first = tester
          .getTopLeft(find.text('Условия: if / else и switch'))
          .dy;
      final sort = tester.getTopLeft(find.text('Сортировка пузырьком')).dy;
      expect(first, lessThan(sort));
    },
  );

  testWidgets('Копирование из статьи: снекбар «Скопировано»', timeout: t, (
    tester,
  ) async {
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (message) async {
        if (message.method == 'Clipboard.setData') {
          final arguments = message.arguments as Map<Object?, Object?>;
          clipboardText = arguments['text'] as String?;
        }
        return null;
      },
    );

    await harness.registerUser(tester);
    await openArticle(tester);

    await tester.ensureVisible(find.byKey(const Key('code-copy')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('code-copy')));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Скопировано'), findsOneWidget);
    expect(clipboardText, contains('int main'));

    // Дренаж снекбара (иначе pending timer).
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets(
    'Неизвестная категория → экран-заглушка (не падение)',
    timeout: t,
    (tester) async {
      await harness.registerUser(tester);
      await harness.pumpApp(
        tester,
        initialLocation: '/reference/нет-такой-категории',
      );

      expect(find.byKey(const Key('category-not-found')), findsOneWidget);
      expect(find.byType(CategoryArticlesScreen), findsOneWidget);
    },
  );

  testWidgets('Неизвестная статья → экран-заглушка (не падение)', timeout: t, (
    tester,
  ) async {
    await harness.registerUser(tester);
    await harness.pumpApp(tester, initialLocation: '/article/no_such_article');

    expect(find.byKey(const Key('article-not-found')), findsOneWidget);
    expect(find.byType(ArticleScreen), findsOneWidget);
    expect(find.byType(EmptyState), findsOneWidget);
  });

  testWidgets(
    'Все четыре вкладки переключаются без ошибок, состояние живое',
    timeout: t,
    (tester) async {
      await harness.registerUser(tester);
      await harness.pumpApp(tester, initialLocation: AppConstants.routeHome);

      // Справочник (иконки невыбранных вкладок — outlined-варианты).
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.byIcon(Icons.menu_book_outlined),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('reference-category-syntax')),
        findsOneWidget,
      );

      // Песочница.
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.byIcon(Icons.code_outlined),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Песочница кода появится в P10'), findsOneWidget);

      // Профиль: имя и email пользователя в карточке.
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.byIcon(Icons.person_outline),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('user1'), findsOneWidget);
      expect(find.text('user1@example.com'), findsOneWidget);

      // Возврат на «Главную»: приветствие на месте (IndexedStack хранит
      // состояние вкладок).
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.byIcon(Icons.home_outlined),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Привет, user1!'), findsOneWidget);
    },
  );

  testWidgets('Гость: /article/:id закрыт auth-guard (→ /login)', timeout: t, (
    tester,
  ) async {
    await harness.pumpApp(tester, initialLocation: '/article/cpp_syn_io');
    expect(find.byType(ArticleScreen), findsNothing);
    expect(find.widgetWithText(AppBar, 'Авторизация'), findsOneWidget);
  });
}
