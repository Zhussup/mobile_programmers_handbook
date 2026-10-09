import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mob_kurs/core/constants/app_constants.dart';
import 'package:mob_kurs/features/auth/session_provider.dart';
import 'package:mob_kurs/features/profile/screens/profile_edit_screen.dart';
import 'package:mob_kurs/features/profile/screens/profile_screen.dart';

import 'harness.dart';

/// Виджет-тесты профиля 2.0 (P11): экран редактирования — валидация полей,
/// inline-ошибки уникальности, успешное сохранение (сессия обновляется),
/// смена пароля (нужен старый), выбор цвета аватара.
///
/// БД-операции (сохранение профиля/пароля) — реальная IO: тапы по их
/// кнопкам — через [AppHarness.tapAndWaitReal].
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

  /// Открыть редактирование профиля: /profile → кнопка «Редактировать».
  Future<void> openProfileEdit(WidgetTester tester) async {
    await harness.registerUser(tester);
    await harness.pumpApp(tester, initialLocation: AppConstants.routeProfile);
    await tester.pumpAndSettle();
    await harness.settleRealIo(tester);

    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.byKey(const Key('profile-edit-open')), findsOneWidget);
    await tester.tap(find.byKey(const Key('profile-edit-open')));
    await tester.pumpAndSettle();

    expect(find.byType(ProfileEditScreen), findsOneWidget);
  }

  testWidgets(
    'валидация: латиница с недопустимым символом → ошибка поля имени',
    timeout: t,
    (tester) async {
      await openProfileEdit(tester);

      await tester.enterText(
        find.byKey(const Key('profile-edit-username')),
        'bad name!',
      );
      // Валидация только по submit.
      await tester.ensureVisible(find.byKey(const Key('profile-edit-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('profile-edit-save')));
      await tester.pumpAndSettle();

      expect(
        find.text('Имя пользователя может содержать только буквы, цифры и «_»'),
        findsOneWidget,
      );
      // Всё ещё на экране редактирования (без pop).
      expect(find.byType(ProfileEditScreen), findsOneWidget);
      expect(find.text('Сохранено'), findsNothing);
    },
  );

  testWidgets(
    'уникальность: занятое имя вторым пользователем → inline-ошибка поля',
    timeout: t,
    (tester) async {
      // Чужой пользователь уже в БД (registration без входа).
      await harness.seedUser(
        tester,
        username: 'second',
        email: 'second@example.com',
      );
      await openProfileEdit(tester);

      await tester.enterText(
        find.byKey(const Key('profile-edit-username')),
        'second',
      );
      await tester.ensureVisible(find.byKey(const Key('profile-edit-save')));
      await tester.pumpAndSettle();
      // Сохранение: проверка уникальности в БД (реальная IO).
      await harness.tapAndWaitReal(tester, const Key('profile-edit-save'));
      await tester.pumpAndSettle();

      expect(find.text('Имя пользователя уже занято'), findsOneWidget);
      expect(find.byType(ProfileEditScreen), findsOneWidget);
    },
  );

  testWidgets(
    'сохранение: имя и email обновлены в карточке профиля и в сессии',
    timeout: t,
    (tester) async {
      await openProfileEdit(tester);

      await tester.enterText(
        find.byKey(const Key('profile-edit-username')),
        'Петя',
      );
      await tester.enterText(
        find.byKey(const Key('profile-edit-email')),
        'petya@example.com',
      );
      await tester.ensureVisible(find.byKey(const Key('profile-edit-save')));
      await tester.pumpAndSettle();
      await harness.tapAndWaitReal(tester, const Key('profile-edit-save'));
      await tester.pumpAndSettle();

      // Возврат на /profile: карточка показывает новые данные.
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.text('Сохранено'), findsOneWidget);
      expect(find.text('Петя'), findsOneWidget);
      expect(find.text('petya@example.com'), findsOneWidget);

      // Сессия тоже обновилась (экраны-через-currentUser).
      final context = tester.element(find.byType(ProfileScreen));
      final session = context.read<SessionProvider>();
      expect(session.currentUser!.username, 'Петя');
      expect(session.currentUser!.email, 'petya@example.com');

      await drainSnackBar(tester);
    },
  );

  testWidgets(
    'цвет аватара: выбор свотча и сохранение меняет цвет',
    timeout: t,
    (tester) async {
      await openProfileEdit(tester);

      // Палитра — 8 фиксированных цветов; выбран первый по умолчанию
      // ('#2AA79B' — user с ним зарегистрирован).
      for (final hex in AppConstants.avatarPalette) {
        expect(
          find.byKey(Key('profile-color-${hex.replaceFirst('#', '').toLowerCase()}')),
          findsOneWidget,
          reason: 'свотч $hex должен быть в палитре',
        );
      }

      await tester.enterText(
        find.byKey(const Key('profile-edit-username')),
        'Петя',
      ); // чтобы было что сохранять вместе с цветом
      await tester.tap(find.byKey(const Key('profile-color-8c6ff0')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('profile-edit-save')));
      await tester.pumpAndSettle();
      await harness.tapAndWaitReal(tester, const Key('profile-edit-save'));
      await tester.pumpAndSettle();

      // Сессия обновилась: цвет пользователя уже новый.
      final context = tester.element(find.byType(ProfileScreen));
      final session = context.read<SessionProvider>();
      expect(session.currentUser!.avatarColor, '#8C6FF0');

      await drainSnackBar(tester);
    },
  );

  testWidgets(
    'пароль: неверный старый → inline «Неверный старый пароль»',
    timeout: t,
    (tester) async {
      await openProfileEdit(tester);

      await tester.enterText(
        find.byKey(const Key('profile-password-old')),
        'НЕВЕРНЫЙ',
      );
      await tester.enterText(
        find.byKey(const Key('profile-password-new')),
        'новыйПароль456',
      );
      await tester.enterText(
        find.byKey(const Key('profile-password-confirm')),
        'новыйПароль456',
      );
      await tester.ensureVisible(
        find.byKey(const Key('profile-password-save')),
      );
      await tester.pumpAndSettle();
      await harness.tapAndWaitReal(
        tester,
        const Key('profile-password-save'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Неверный старый пароль'), findsOneWidget);
      // Всё ещё на экране редактирования (без pop).
      expect(find.byType(ProfileEditScreen), findsOneWidget);
    },
  );

  testWidgets(
    'пароль: корректная смена → «Пароль изменён», вход по новому работает',
    timeout: t,
    (tester) async {
      final password = 'пароль123';
      await openProfileEdit(tester);

      await tester.enterText(
        find.byKey(const Key('profile-password-old')),
        password,
      );
      await tester.enterText(
        find.byKey(const Key('profile-password-new')),
        'новыйПароль456',
      );
      await tester.enterText(
        find.byKey(const Key('profile-password-confirm')),
        'новыйПароль456',
      );
      await tester.ensureVisible(
        find.byKey(const Key('profile-password-save')),
      );
      await tester.pumpAndSettle();
      await harness.tapAndWaitReal(
        tester,
        const Key('profile-password-save'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Пароль изменён'), findsOneWidget);

      // Вход по НОВОМУ паролю работает (старый — нет: юнит-тесты репозитория).
      await tester.runAsync(() async {
        await harness.session.logout();
        final again = await harness.session.login(
          loginOrEmail: 'user1',
          password: 'новыйПароль456',
        );
        expect(again.username, 'user1');
      });

      await drainSnackBar(tester);
    },
  );

  testWidgets(
    'статистика: три карточки с нулями у нового пользователя',
    timeout: t,
    (tester) async {
      await harness.registerUser(tester);
      await harness.pumpApp(tester, initialLocation: AppConstants.routeProfile);
      await tester.pumpAndSettle();
      await harness.settleRealIo(tester);

      expect(find.byKey(const Key('profile-stats-read')), findsOneWidget);
      expect(find.byKey(const Key('profile-stats-favorites')), findsOneWidget);
      expect(find.byKey(const Key('profile-stats-snippets')), findsOneWidget);
      expect(find.text('0'), findsNWidgets(3));
      expect(find.text('Прочитано'), findsOneWidget);
      expect(find.text('В избранном'), findsOneWidget);
      expect(find.text('Сниппеты'), findsOneWidget);
    },
  );
}