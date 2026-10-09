import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mob_kurs/core/constants/app_constants.dart';
import 'package:mob_kurs/features/profile/screens/profile_screen.dart';

import 'harness.dart';

/// Виджет-тесты экрана авторизации и выхода (P4): неизвестный пользователь,
/// неверный пароль, корректные данные → /home, переход к регистрации.
void main() {
  final harness = AppHarness();

  setUp(() => harness.setUp());
  tearDown(() => harness.tearDown());

  /// Таймаут теста (иначе зависший тест держит весь прогон 30 минут).
  const t = Timeout(Duration(seconds: 60));

  Future<void> fillAndSubmit(
    WidgetTester tester, {
    required String login,
    required String password,
  }) async {
    await tester.enterText(find.byKey(const Key('login-field')), login);
    await tester.enterText(find.byKey(const Key('login-password')), password);
    await tester.pump();

    // Обработчик «Войти» ждёт реальной IO (SQLite ffi): нажатие + ожидание
    // завершения операции — в реальном цикле событий (runAsync).
    await harness.tapAndWaitReal(tester, const Key('login-submit'));
  }

  Future<void> drainSnackBar(WidgetTester tester) async {
    // SnackBar самоуничтожается по таймеру (4 с), затем играет обратную
    // анимацию — прогнать оба этапа, иначе «pending timer» в конце теста.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('Неизвестный пользователь → сообщение об ошибке', timeout: t, (
    tester,
  ) async {
    await harness.pumpApp(tester, initialLocation: AppConstants.routeLogin);
    expect(find.widgetWithText(AppBar, 'Авторизация'), findsOneWidget);

    // Пара прокруток для завершения анимации появления SnackBar.
    await fillAndSubmit(tester, login: 'нетакого', password: 'пароль123');
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Неверный логин или пароль'), findsOneWidget);
    // Мы всё ещё на экране авторизации.
    expect(find.widgetWithText(AppBar, 'Авторизация'), findsOneWidget);
    await drainSnackBar(tester);
  });

  testWidgets('Неверный пароль → сообщение об ошибке', timeout: t, (
    tester,
  ) async {
    await harness.seedUser(tester, username: 'user1');

    await harness.pumpApp(tester, initialLocation: AppConstants.routeLogin);
    await fillAndSubmit(tester, login: 'user1', password: 'другойПароль');
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Неверный логин или пароль'), findsOneWidget);
    await drainSnackBar(tester);
  });

  testWidgets(
    'Ошибка входа появляется снова после повторной попытки',
    timeout: t,
    (tester) async {
      await harness.pumpApp(tester, initialLocation: AppConstants.routeLogin);

      await fillAndSubmit(tester, login: 'нетакого', password: 'плохой');
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Неверный логин или пароль'), findsOneWidget);
      await drainSnackBar(tester);
      expect(find.text('Неверный логин или пароль'), findsNothing);

      await fillAndSubmit(tester, login: 'нетакого2', password: 'плохой');
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Неверный логин или пароль'), findsOneWidget);
      await drainSnackBar(tester);
    },
  );

  testWidgets('Корректные данные → переход на /home', timeout: t, (
    tester,
  ) async {
    await harness.seedUser(tester, username: 'user1');

    await harness.pumpApp(tester, initialLocation: AppConstants.routeLogin);
    await fillAndSubmit(tester, login: 'user1', password: 'пароль123');
    await tester.pump(const Duration(seconds: 1));

    expect(find.widgetWithText(AppBar, 'Главная'), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Авторизация'), findsNothing);

    // Сессия сохранена (критерий «связка»: повторная авторизация и persist).
    expect(harness.session.state.isAuthorized, isTrue);
  });

  testWidgets('Вход по email → переход на /home', timeout: t, (tester) async {
    await harness.seedUser(tester, username: 'user1');

    await harness.pumpApp(tester, initialLocation: AppConstants.routeLogin);
    await fillAndSubmit(
      tester,
      login: 'user1@example.com',
      password: 'пароль123',
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.widgetWithText(AppBar, 'Главная'), findsOneWidget);
  });

  testWidgets(
    'Ссылка «Нет аккаунта? Зарегистрироваться» ведёт на /register',
    timeout: t,
    (tester) async {
      await harness.pumpApp(tester, initialLocation: AppConstants.routeLogin);

      await tester.ensureVisible(find.text('Нет аккаунта? Зарегистрироваться'));
      await tester.tap(find.text('Нет аккаунта? Зарегистрироваться'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'Регистрация'), findsOneWidget);
    },
  );

  testWidgets(
    'Выход через профиль: диалог → /login, закрытые разделы снова закрыты',
    timeout: t,
    (tester) async {
      // Вошедший пользователь.
      await harness.registerUser(tester);
      await harness.pumpApp(tester, initialLocation: AppConstants.routeProfile);

      expect(find.byType(ProfileScreen), findsOneWidget);

      // Открыть диалог подтверждения.
      await tester.tap(find.byKey(const Key('logout-button')));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Выйти из аккаунта?'), findsOneWidget);

      // Подтвердить выход: закрытие диалога (обратная анимация, logout
      // выполняется по закрытию) и переход на /login.
      await harness.tapAndWaitReal(tester, const Key('logout-confirm'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Оказались на авторизации: доступ к закрытым разделам требует входа.
      expect(find.widgetWithText(AppBar, 'Авторизация'), findsOneWidget);
      expect(find.byType(ProfileScreen), findsNothing);
    },
  );
}
