import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mob_kurs_admin/app.dart';
import 'package:mob_kurs_admin/core/network/api_exception.dart';
import 'package:mob_kurs_admin/features/auth/auth_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_api_client.dart';

Future<AuthProvider> _pumpLogin(WidgetTester tester, FakeApiClient fake) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final auth = AuthProvider(fake, prefs);
  await tester.pumpWidget(
    AdminApp(api: fake, auth: auth, initialLocation: '/login'),
  );
  await tester.pumpAndSettle();
  return auth;
}

Future<void> _fillCredentials(
  WidgetTester tester, {
  required String login,
  required String password,
}) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), login);
  await tester.enterText(fields.at(1), password);
  await tester.tap(find.widgetWithText(FilledButton, 'Войти'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('вход администратора открывает панель управления', (
    tester,
  ) async {
    final fake = FakeApiClient();
    fake.onData('POST', '/auth/login', <String, dynamic>{
      'token': 'admin-token',
      'user': <String, dynamic>{
        'id': 1,
        'username': 'admin',
        'email': 'admin@example.com',
        'role': 'admin',
        'is_blocked': 0,
      },
    });
    fake.onData('GET', '/admin/users', <dynamic>[]);
    fake.onData('GET', '/admin/articles', <dynamic>[]);

    final auth = await _pumpLogin(tester, fake);
    await _fillCredentials(tester, login: 'admin', password: 'admin123');

    expect(fake.token, 'admin-token');
    expect(auth.isAuthenticated, isTrue);
    expect(find.text('Панель управления'), findsWidgets);
    expect(
      find.text('Вход для администратора мобильного приложения'),
      findsNothing,
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('admin_auth_token'), 'admin-token');
  });

  testWidgets('неверные данные показывают ошибку и не пускают в панель', (
    tester,
  ) async {
    final fake = FakeApiClient();
    fake.onError(
      'POST',
      '/auth/login',
      const ApiException(
        kind: ApiErrorKind.unauthorized,
        statusCode: 401,
        message: 'Неверный логин или пароль',
      ),
    );

    final auth = await _pumpLogin(tester, fake);
    await _fillCredentials(tester, login: 'admin', password: 'wrong');

    expect(auth.isAuthenticated, isFalse);
    expect(fake.token, isNull);
    expect(find.text('Неверный логин или пароль'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Войти'), findsOneWidget);
  });

  testWidgets('пользователь без роли admin получает отказ', (tester) async {
    final fake = FakeApiClient();
    fake.onData('POST', '/auth/login', <String, dynamic>{
      'token': 'user-token',
      'user': <String, dynamic>{
        'id': 2,
        'username': 'user',
        'email': 'user@example.com',
        'role': 'user',
        'is_blocked': 0,
      },
    });
    fake.onData('POST', '/auth/logout', null);

    final auth = await _pumpLogin(tester, fake);
    await _fillCredentials(tester, login: 'user', password: 'user123');

    expect(auth.isAuthenticated, isFalse);
    expect(fake.token, isNull);
    expect(find.text('Доступ только для администратора'), findsOneWidget);
    expect(
      fake.requests.any(
        (request) => request.method == 'POST' && request.path == '/auth/logout',
      ),
      isTrue,
      reason: 'токен не-администратора должен быть аннулирован',
    );
  });
}
