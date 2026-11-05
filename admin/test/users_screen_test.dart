import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mob_kurs_admin/core/theme/app_theme.dart';
import 'package:mob_kurs_admin/features/users/users_provider.dart';
import 'package:mob_kurs_admin/features/users/users_screen.dart';
import 'package:provider/provider.dart';

import 'fakes/fake_api_client.dart';

Map<String, dynamic> _user({
  required int id,
  required String username,
  required String email,
  required String role,
  int blocked = 0,
}) {
  return <String, dynamic>{
    'id': id,
    'username': username,
    'email': email,
    'role': role,
    'is_blocked': blocked,
    'created_at': '2026-01-0${id}T10:00:00Z',
  };
}

Widget _wrap(FakeApiClient fake) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: ChangeNotifierProvider(
      create: (_) => UsersProvider(api: fake, currentUserId: 1),
      child: const Scaffold(body: UsersScreen()),
    ),
  );
}

void main() {
  testWidgets('список пользователей и блокировка', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fake = FakeApiClient();
    fake.onData('GET', '/admin/users', <dynamic>[
      _user(
        id: 1,
        username: 'admin',
        email: 'admin@example.com',
        role: 'admin',
      ),
      _user(
        id: 2,
        username: 'reader',
        email: 'reader@example.com',
        role: 'user',
      ),
    ]);
    fake.on('PATCH', '/admin/users/2/block', (request) {
      final body = request.body! as Map<String, dynamic>;
      final blocked = body['blocked'] == true;
      return _user(
        id: 2,
        username: 'reader',
        email: 'reader@example.com',
        role: 'user',
        blocked: blocked ? 1 : 0,
      );
    });

    await tester.pumpWidget(_wrap(fake));
    await tester.pumpAndSettle();

    expect(find.text('admin'), findsOneWidget);
    expect(find.text('reader@example.com'), findsOneWidget);
    expect(find.text('Всего: 2'), findsOneWidget);

    // Свою учётную запись блокировать нельзя — кнопка отключена.
    final lockButtons = find.widgetWithIcon(IconButton, Icons.lock_outline);
    expect(lockButtons, findsNWidgets(2));
    expect(tester.widget<IconButton>(lockButtons.at(0)).onPressed, isNull);

    // Блокировка другого пользователя — через подтверждение.
    await tester.tap(lockButtons.at(1));
    await tester.pumpAndSettle();

    expect(find.text('Заблокировать пользователя?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Заблокировать'));
    await tester.pumpAndSettle();

    expect(find.text('Заблокирован'), findsOneWidget);
    final patchRequests = fake.requests.where(
      (request) =>
          request.method == 'PATCH' && request.path == '/admin/users/2/block',
    );
    expect(patchRequests, hasLength(1));
    expect(
      (patchRequests.first.body! as Map<String, dynamic>)['blocked'],
      isTrue,
    );
  });
}
