import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mob_kurs_admin/core/theme/app_theme.dart';
import 'package:mob_kurs_admin/features/articles/articles_provider.dart';
import 'package:mob_kurs_admin/features/articles/articles_screen.dart';
import 'package:provider/provider.dart';

import 'fakes/fake_api_client.dart';

Map<String, dynamic> _article({bool published = false}) {
  return <String, dynamic>{
    'id': 'arrays',
    'category_id': 'basics',
    'title': 'Массивы',
    'summary': 'Введение в массивы',
    'difficulty': 'beginner',
    'tags': <String>['cpp', 'массивы'],
    'blocks_json': '[]',
    'is_published': published ? 1 : 0,
    'updated_at': '2026-01-02T10:00:00Z',
  };
}

Widget _wrap(FakeApiClient fake) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: ChangeNotifierProvider(
      create: (_) => ArticlesProvider(api: fake),
      child: const Scaffold(body: ArticlesScreen()),
    ),
  );
}

void main() {
  testWidgets('список статей и публикация', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fake = FakeApiClient();
    fake.onData('GET', '/admin/categories', <dynamic>[
      <String, dynamic>{'id': 'basics', 'title': 'Основы'},
    ]);
    fake.onData('GET', '/admin/articles', <dynamic>[_article()]);
    fake.on('PATCH', '/admin/articles/arrays/publish', (request) {
      final body = request.body! as Map<String, dynamic>;
      return _article(published: body['published'] == true);
    });

    await tester.pumpWidget(_wrap(fake));
    await tester.pumpAndSettle();

    expect(find.text('Массивы'), findsOneWidget);
    expect(find.text('Основы'), findsOneWidget);
    expect(find.text('Черновик'), findsOneWidget);

    await tester.tap(find.byTooltip('Опубликовать'));
    await tester.pumpAndSettle();

    expect(find.text('Опубликована'), findsOneWidget);
    expect(find.text('Черновик'), findsNothing);

    final patchRequests = fake.requests.where(
      (request) =>
          request.method == 'PATCH' &&
          request.path == '/admin/articles/arrays/publish',
    );
    expect(patchRequests, hasLength(1));
    expect(
      (patchRequests.first.body! as Map<String, dynamic>)['published'],
      isTrue,
    );
  });
}
