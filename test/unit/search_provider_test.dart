import 'package:flutter_test/flutter_test.dart';
import 'package:mob_kurs/features/reference/article_model.dart';
import 'package:mob_kurs/features/reference/article_repository.dart';
import 'package:mob_kurs/features/search/search_provider.dart';

import '../widget/fixtures.dart';

/// Юнит-тесты поиска (P8): матчинг по title/summary/tags, фильтр
/// сложности, результат привязан к статье и категории.
void main() {
  late ArticleRepository articles;
  late SearchProvider search;

  setUp(() {
    articles = ArticleRepository.fromRaw(p8p9ReferenceFixtures);
    search = SearchProvider(articles);
  });

  group('Матчинг запроса', () {
    test('пустой запрос → все статьи всех категорий', () {
      expect(search.query, '');
      expect(search.difficulty, isNull, reason: 'фильтр «Все»');
      expect(search.results, hasLength(4));
    });

    test('по title — без учёта регистра', () {
      search.setQuery('перем');
      expect(search.results.map((r) => r.article.id).toList(), ['fx_syn_var']);
    });

    test('по summary', () {
      search.setQuery('динамический');
      expect(search.results.map((r) => r.article.id).toList(), [
        'fx_stl_vector',
      ]);
    });

    test('по tag — заглавный запрос ловит тег строчными (STL)', () {
      search.setQuery('STL');
      final ids = search.results.map((r) => r.article.id).toSet();
      expect(ids, {'fx_stl_vector', 'fx_stl_map'});
    });

    test('ничего не найдено → пустой результат', () {
      search.setQuery('абракадабра');
      expect(search.results, isEmpty);
    });

    test('сброс возвращает полный список', () {
      search.setQuery('перем');
      expect(search.results, hasLength(1));
      search.reset();
      expect(search.query, '');
      expect(search.difficulty, isNull);
      expect(search.results, hasLength(4));
    });
  });

  group('Фильтр сложности', () {
    test('фильтр по сложности без запроса', () {
      search.setDifficulty(Difficulty.intermediate);
      expect(search.results.map((r) => r.article.id).toSet(), {
        'fx_syn_loop',
        'fx_stl_map',
      });

      search.setDifficulty(Difficulty.advanced);
      expect(search.results.map((r) => r.article.id).toList(), [
        'fx_stl_vector',
      ]);

      // «Все»: фильтр снимается.
      search.setDifficulty(null);
      expect(search.results, hasLength(4));
    });

    test('запрос + фильтр работают одновременно (И)', () {
      search.setQuery('stl');
      search.setDifficulty(Difficulty.advanced);
      expect(search.results.map((r) => r.article.id).toList(), [
        'fx_stl_vector',
      ]);
    });
  });

  group('Результат', () {
    test('строка результата содержит статью и её категорию', () {
      final result = search.results
          .where((r) => r.article.id == 'fx_stl_vector')
          .single;
      expect(result.article.title, 'Vector');
      expect(result.category.id, 'stl');
      expect(result.category.title, 'Контейнеры STL');
    });

    test('setQuery/setDifficulty уведомляют слушателей', () {
      var notified = 0;
      search.addListener(() => notified++);
      search.setQuery('циклы');
      search.setDifficulty(Difficulty.intermediate);
      expect(notified, 2);
    });
  });
}
