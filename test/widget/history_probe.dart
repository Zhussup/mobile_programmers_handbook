import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:mob_kurs/core/constants/app_constants.dart';
import 'package:mob_kurs/features/reference/article_repository.dart';

import 'fixtures.dart';
import 'harness.dart';

void main() {
  final harness = AppHarness();

  setUp(() => harness.setUp());
  tearDown(() => harness.tearDown());

  const t = Timeout(Duration(seconds: 60));

  testWidgets('probe: маршрут /history после pumpApp', timeout: t, (tester) async {
    await harness.registerUser(tester);
    debugPrint('PROBE user=${harness.session.currentUser?.id}');

    await harness.pumpApp(
      tester,
      initialLocation: '/article/fx_syn_var',
      referenceRepository: ArticleRepository.fromRaw(p8p9ReferenceFixtures),
    );
    await tester.pumpAndSettle();
    await harness.settleRealIo(tester);

    await harness.pumpApp(
      tester,
      initialLocation: AppConstants.routeHistory,
      referenceRepository: ArticleRepository.fromRaw(p8p9ReferenceFixtures),
    );
    await tester.pumpAndSettle();
    await harness.settleRealIo(tester);

    final context = tester.element(find.byType(Scaffold).first);
    debugPrint('PROBE location=${GoRouter.of(context).routeInformationProvider.value.uri}');
    debugPrint('PROBE appbar-title=');
    for (final w in find.byType(AppBar).evaluate()) {
      final appBar = w.widget as AppBar;
      final title = appBar.title;
      debugPrint('  TITLE=${title is Text ? title.data : title}');
    }
  });
}
