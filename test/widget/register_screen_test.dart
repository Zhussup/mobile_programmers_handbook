import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mob_kurs/core/constants/app_constants.dart';

import 'harness.dart';

/// Виджет-тесты экрана регистрации (P3): несовпадение паролей, ошибка
/// уникальности, успешная регистрация → /home.
void main() {
  final harness = AppHarness();

  /// Таймаут теста (иначе зависший тест держит весь прогон 30 минут).
  const t = Timeout(Duration(seconds: 60));

  setUp(() => harness.setUp());
  tearDown(() => harness.tearDown());

  Future<void> openRegister(WidgetTester tester) async {
    await harness.pumpApp(tester, initialLocation: AppConstants.routeRegister);
    expect(find.widgetWithText(AppBar, 'Регистрация'), findsOneWidget);
  }

  Future<void> fillForm(
    WidgetTester tester, {
    required String username,
    required String email,
    required String password,
    required String confirm,
  }) async {
    await tester.enterText(
      find.byKey(const Key('register-username')),
      username,
    );
    await tester.enterText(find.byKey(const Key('register-email')), email);
    await tester.enterText(
      find.byKey(const Key('register-password')),
      password,
    );
    await tester.enterText(find.byKey(const Key('register-confirm')), confirm);
    await tester.pump();
  }

  testWidgets(
    'Несовпадение паролей → сообщение «Пароли не совпадают»',
    timeout: t,
    (tester) async {
      await openRegister(tester);
      await fillForm(
        tester,
        username: 'user1',
        email: 'user1@example.com',
        password: 'пароль123',
        confirm: 'пароль456',
      );

      await tester.tap(find.byKey(const Key('register-submit')));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Пароли не совпадают'), findsOneWidget);
      // Регистрация не выполнена — мы всё ещё на форме.
      expect(find.widgetWithText(AppBar, 'Регистрация'), findsOneWidget);
    },
  );

  testWidgets('Пустые поля → сообщения «Введите …»', timeout: t, (
    tester,
  ) async {
    await openRegister(tester);

    await tester.tap(find.byKey(const Key('register-submit')));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Введите имя пользователя'), findsOneWidget);
    expect(find.text('Введите email'), findsOneWidget);
    expect(find.text('Введите пароль'), findsOneWidget);
    // «Повторите пароль» — и метка поля, и сообщение об ошибке.
    expect(find.text('Повторите пароль'), findsNWidgets(2));
  });

  testWidgets(
    'Занятое имя (в другом регистре) → ошибка на поле username',
    timeout: t,
    (tester) async {
      await harness.seedUser(
        tester,
        username: 'Иван',
        email: 'ivan@example.com',
      );

      await openRegister(tester);
      await fillForm(
        tester,
        username: 'иван',
        email: 'new@example.com',
        password: 'пароль123',
        confirm: 'пароль123',
      );

      // Обработчик ждёт реальной IO (SQLite ffi) — тап + ожидание в
      // реальном цикле событий (runAsync).
      await harness.tapAndWaitReal(tester, const Key('register-submit'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Имя пользователя уже занято'), findsOneWidget);
    },
  );

  testWidgets('Занятый email → ошибка на поле email', timeout: t, (
    tester,
  ) async {
    await harness.seedUser(tester, username: 'Иван', email: 'ivan@example.com');

    await openRegister(tester);
    await fillForm(
      tester,
      username: 'Пётр',
      email: 'IVAN@EXAMPLE.COM',
      password: 'пароль123',
      confirm: 'пароль123',
    );

    // Обработчик ждёт реальной IO (SQLite ffi) — тап + ожидание в
    // реальном цикле событий (runAsync).
    await harness.tapAndWaitReal(tester, const Key('register-submit'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Email уже зарегистрирован'), findsOneWidget);
  });

  testWidgets('Успешная регистрация: вход и переход на /home', timeout: t, (
    tester,
  ) async {
    await openRegister(tester);
    await fillForm(
      tester,
      username: 'новыйПользователь',
      email: 'new@example.com',
      password: 'пароль123',
      confirm: 'пароль123',
    );

    await harness.tapAndWaitReal(tester, const Key('register-submit'));
    await tester.pumpAndSettle();

    // Мы на главной: вошли сразу после регистрации (критерий «связка»).
    expect(find.widgetWithText(AppBar, 'Главная'), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Регистрация'), findsNothing);

    // Сессия сохранена: пользователь отображается в профиле.
    expect(harness.session.state.isAuthorized, isTrue);
  });

  testWidgets('Ссылка «Уже есть аккаунт? Войти» ведёт на /login', timeout: t, (
    tester,
  ) async {
    await openRegister(tester);

    await tester.ensureVisible(find.text('Уже есть аккаунт? Войти'));
    await tester.tap(find.text('Уже есть аккаунт? Войти'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Авторизация'), findsOneWidget);
  });
}
