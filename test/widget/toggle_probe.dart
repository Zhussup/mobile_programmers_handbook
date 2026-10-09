import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/package.dart' hide Provider;
import 'package:provider/provider.dart';

import 'package:mob_kurs/core/constants/app_constants.dart';
import 'package:mob_kurs/features/reference/article_repository.dart';
import 'package:mob_kurs/features/reference/favorites_provider.dart';
import 'package:mob_kurs/features/reference/favorites_repository.dart';
import 'package:mob_kurs/features/reference/screens/favorites_screen.dart';

import 'fixtures.dart';
import 'harness.dart';

void main() {
  final harness = AppHarness();

  setUp(() => harness.setUp());
  tearDown(() => harness.tearDown());

  const t = Timeout(Duration(seconds: 60));

  testWidgets('probe2: rebuild после notify', timeout: t, (tester) async {
    await harness.registerUser(tester);
    await tester.runAsync(() async {
      final repository = FavoritesRepository(db: harness.db);
      await repository.toggle(harness.session.currentUser!.id, 'fx_syn_var');
      await repository.toggle(harness.session.currentUser!.id, 'fx_stl_vector');
    });
    await harness.pumpApp(
      tester,
      initialLocation: AppConstants.routeFavorites,
      referenceRepository: ArticleRepository.fromRaw(p8p9ReferenceFixtures),
    );
    await tester.pumpAndSettle();
    await harness.settleRealIo(tester);

    // Прямой toggle ВНУТРИ runAsync (как делает UI-обработчик).
    final context = tester.element(find.byType(FavoritesScreen));
    final favorites = Provider.of<FavoritesProvider>(context, listen: false);

    await tester.runAsync(() async {
      await favorites.toggle('fx_syn_var');
      debugPrint('PROBE toggle done');
    });
    await tester.pump();
    debugPrint('PROBE entries=${favorites.entries.map((e) => e.article.id).toList()}');
    debugPrint('PROBE texts=');
    for (final t in find.byType(Text).evaluate()) {
      final widget = t.widget as Text;
      debugPrint('  TEXT: ${widget.data ?? widget.toString()}');
    }
  });
}
