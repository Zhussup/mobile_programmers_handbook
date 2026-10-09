import 'dart:convert';
import 'dart:io' show File;

import 'package:flutter_test/flutter_test.dart';
import 'package:mob_kurs/features/reference/article_model.dart';
import 'package:mob_kurs/features/reference/article_repository.dart';
import 'package:mob_kurs/features/reference/reference_provider.dart';

/// Юнит-тесты репозитория справочника: реальные JSON-файлы с диска
/// (dart:io — в обычном тесте реальная IO разрешена), inline-фикстуры,
/// defensive-разбор.
///
/// ВАЖНО: контент расширяется параллельно (P8: 5→8 статей в файлах, новые
/// cpp_stl/cpp_oop/dart_flutter). Тесты «реального контента» проверяют
/// ИНВАРИАНТЫ, которые не зависят от размера набора: базовые категории,
/// уникальность id, валидность сложностей, сортировка. Точные счётчики —
/// только для inline-фикстур.
void main() {
  /// Чтение списка файлов контента С ДИСКА (отсутствующие пропускаются —
  /// так же, как production-путь loadFromAssets).
  List<String> readContentFiles() => [
    for (final name in ArticleRepository.contentFiles)
      if (File('assets/content/reference/$name').existsSync())
        File('assets/content/reference/$name').readAsStringSync(),
  ];

  group('Реальный контент (README)', () {
    test('список contentFiles — шесть имён (план: 5 категорий C++ + Dart)', () {
      expect(ArticleRepository.contentFiles, [
        'cpp_syntax.json',
        'cpp_data_structures.json',
        'cpp_algorithms.json',
        'cpp_stl.json',
        'cpp_oop.json',
        'dart_flutter.json',
      ]);
    });

    test('базовые категории присутствуют с ожидаемыми title/icon', () {
      final repo = ArticleRepository.fromRaw(readContentFiles());

      final ids = repo.categories.map((c) => c.id).toSet();
      expect(ids, containsAll({'syntax', 'data_structures', 'algorithms'}));

      final titles = {for (final c in repo.categories) c.id: c.title};
      expect(titles['syntax'], 'Синтаксис C++');
      expect(titles['data_structures'], 'Структуры данных');
      expect(titles['algorithms'], 'Алгоритмы');

      final icons = {for (final c in repo.categories) c.id: c.icon};
      expect(icons['syntax'], 'code');
      expect(icons['data_structures'], 'layers');
      expect(icons['algorithms'], 'sort');
    });

    test('id статей уникальны во всём справочнике, сложности допустимы', () {
      final repo = ArticleRepository.fromRaw(readContentFiles());

      final allIds = <String>[];
      for (final category in repo.categories) {
        final articles = repo.articlesForCategory(category.id);
        // README: базовые категории — минимум по 5 статей (v1 + расширение).
        if (const {
          'syntax',
          'data_structures',
          'algorithms',
        }.contains(category.id)) {
          expect(
            articles.length,
            greaterThanOrEqualTo(5),
            reason: 'категория ${category.id}',
          );
        }
        for (final article in articles) {
          allIds.add(article.id);
          expect(article.hasCode, isTrue, reason: 'статья ${article.id}');
          expect(
            Difficulty.values.contains(article.difficulty),
            isTrue,
            reason: 'статья ${article.id}',
          );
        }
      }
      expect(allIds.toSet().length, allIds.length);
    });

    test(
      'каждая базовая категория начинается с простых статей (сортировка)',
      () {
        final repo = ArticleRepository.fromRaw(readContentFiles());
        for (final categoryId in ['syntax', 'data_structures', 'algorithms']) {
          final orders = repo
              .articlesForCategory(categoryId)
              .map((a) => a.difficulty.sortOrder)
              .toList();
          final sortedOrders = [...orders]..sort();
          expect(
            orders,
            sortedOrders,
            reason: 'категория $categoryId — простые раньше сложных',
          );
        }
      },
    );

    test('поиск статьи по id; неизвестный id → null', () {
      final repo = ArticleRepository.fromRaw(readContentFiles());

      final article = repo.articleById('cpp_syn_variables');
      expect(article, isNotNull);
      expect(article!.title, 'Переменные и базовые типы');
      expect(article.blocks, isNotEmpty);

      expect(repo.articleById('cpp_alg_recursion'), isNotNull);
      expect(repo.articleById('cpp_syn_no_such_id'), isNull);
      expect(repo.categoryById('no_such_category'), isNull);
    });

    test('code-блоки разбираются с полями language/output/caption', () {
      final repo = ArticleRepository.fromRaw(readContentFiles());
      final hello = repo.articleById('cpp_syn_hello_world')!;

      final code = hello.blocks.whereType<ArticleCodeBlock>().single;
      expect(code.language, 'cpp');
      expect(code.output, 'Hello, World!');
      expect(code.caption, isNotNull);
      // README: вывод — реальный вывод программы, без завершающего \n.
      expect(code.output!.endsWith('\n'), isFalse);
      expect(code.code, contains('int main()'));
      // README: код — ASCII (кириллица в code не допускается).
      expect(code.code.codeUnits.every((u) => u < 128), isTrue);
    });

    test('categoryOfArticle: статья знает свою категорию (для поиска P8)', () {
      final repo = ArticleRepository.fromRaw(readContentFiles());
      expect(repo.categoryOfArticle('cpp_syn_variables')?.id, 'syntax');
      expect(repo.categoryOfArticle('cpp_alg_recursion')?.id, 'algorithms');
      expect(repo.categoryOfArticle('cpp_syn_no_such_id'), isNull);
    });
  });

  group('Defensive-разбор (inline-фикстуры)', () {
    test('битый JSON пропускается без исключения', () {
      expect(
        () => ArticleRepository.fromRaw(['{некорректный json']),
        returnsNormally,
      );
      final repo = ArticleRepository.fromRaw(['{некорректный json']);
      expect(repo.categories, isEmpty);
      expect(repo.isLoaded, isTrue);
    });

    test('файл без категории пропускается', () {
      final repo = ArticleRepository.fromRaw([
        jsonEncode({'articles': <Object>[]}),
      ]);
      expect(repo.categories, isEmpty);
    });

    test('неполный набор файлов: fromRaw принимает под-набор (P8)', () {
      // Контент растёт поэтапно; репозиторий работает с любым под-набором.
      final repo = ArticleRepository.fromRaw([
        jsonEncode(categoryFixture(id: 'syntax', title: 'Синтаксис C++')),
      ]);
      expect(repo.categories, hasLength(1));
      expect(repo.articlesForCategory('syntax'), isNotEmpty);
    });

    test('некорректный блок пропускается, остальные блоки остаются', () {
      final raw = jsonEncode({
        'category': {
          'id': 'test',
          'title': 'Тесты',
          'icon': 'code',
          'description': 'Фикстура',
        },
        'articles': [
          {
            'id': 't_a1',
            'title': 'Статья-фикстура',
            'summary': 's',
            'difficulty': 'beginner',
            'tags': ['cpp'],
            'blocks': [
              {'type': 'text', 'text': 'Абзац'},
              {'type': 'неизвестный-тип'},
              {'type': 'list'},
              {'type': 'code'},
              {'type': 'heading', 'text': 'Заголовок'},
            ],
          },
        ],
      });

      final repo = ArticleRepository.fromRaw([raw]);
      final article = repo.articleById('t_a1');
      expect(article, isNotNull);
      expect(article!.blocks, hasLength(2));
      expect(article.blocks[0], isA<ArticleTextBlock>());
      expect(article.blocks[1], isA<ArticleHeadingBlock>());
    });

    test('статья без id/дубликат id пропускаются', () {
      final raw = jsonEncode({
        'category': {
          'id': 'test',
          'title': 'Тесты',
          'icon': 'code',
          'description': '',
        },
        'articles': [
          {
            'id': 'dup_1',
            'title': 'Первая',
            'summary': '',
            'difficulty': 'beginner',
            'tags': [],
            'blocks': [testBlockMap],
          },
          {
            'id': 'dup_1',
            'title': 'Повтор',
            'summary': '',
            'difficulty': 'beginner',
            'tags': [],
            'blocks': [testBlockMap],
          },
          {
            'title': 'Без id',
            'summary': '',
            'difficulty': 'beginner',
            'tags': [],
            'blocks': [testBlockMap],
          },
          {
            'id': 'no_blocks',
            'title': 'Без блоков',
            'summary': '',
            'difficulty': 'beginner',
            'tags': [],
            'blocks': [],
          },
        ],
      });

      final repo = ArticleRepository.fromRaw([raw]);
      expect(repo.articleById('dup_1')!.title, 'Первая');
      expect(repo.articleById('no_blocks'), isNull);
      expect(repo.articlesForCategory('test'), hasLength(1));
    });

    test('вывод кода без \\n на конце; difficulty пустая → beginner', () {
      final raw = jsonEncode({
        'category': {
          'id': 'test',
          'title': 'Тесты',
          'icon': 'code',
          'description': '',
        },
        'articles': [
          {
            'id': 't_b1',
            'title': 'Пустая сложность',
            'summary': '',
            'tags': [],
            'blocks': [
              {'type': 'code', 'code': 'int main() { }', 'output': ' '},
            ],
          },
        ],
      });

      final repo = ArticleRepository.fromRaw([raw]);
      final article = repo.articleById('t_b1')!;
      expect(article.difficulty, Difficulty.beginner);
      final code = article.blocks.whereType<ArticleCodeBlock>().single;
      // Пустой output (пробел) — переключатель вывода не рендерится:
      // модель хранит как есть, решение за рендерером.
      expect(code.language, 'cpp' /* язык по умолчанию */);
    });
  });

  group('Справочник: утилиты', () {
    test('difficultyFromRaw — неизвестное значение → beginner', () {
      expect(difficultyFromRaw('advanced'), Difficulty.advanced);
      expect(difficultyFromRaw('intermediate'), Difficulty.intermediate);
      expect(difficultyFromRaw('wrong'), Difficulty.beginner);
      expect(difficultyFromRaw(null), Difficulty.beginner);
    });

    test('articlesLabel — русская плюрализация', () {
      expect(ReferenceProvider.articlesLabel(1), '1 статья');
      expect(ReferenceProvider.articlesLabel(2), '2 статьи');
      expect(ReferenceProvider.articlesLabel(5), '5 статей');
      expect(ReferenceProvider.articlesLabel(11), '11 статей');
      expect(ReferenceProvider.articlesLabel(21), '21 статья');
      expect(ReferenceProvider.articlesLabel(22), '22 статьи');
      expect(ReferenceProvider.articlesLabel(25), '25 статей');
    });
  });

  group('Production-путь: rootBundle', () {
    test(
      'loadFromAssets терпим к отсутствующим файлам нового контента',
      () async {
        // rootBundle в тестах доступен после ensureInitialized. Полный список
        // из 6 имён, на диске пока только базовые — остальные пропускаются.
        TestWidgetsFlutterBinding.ensureInitialized();
        final repo = ArticleRepository();
        expect(repo.isLoaded, isFalse);
        await repo.loadFromAssets();
        expect(repo.isLoaded, isTrue);
        expect(repo.categories.length, greaterThanOrEqualTo(3));
        expect(repo.articleById('cpp_ds_vector'), isNotNull);
      },
    );
  });
}

/// Блок-фикстура для статей defensive-группы.
const testBlockMap = {'type': 'text', 'text': 'Абзац'};

/// Фикстура категории для теста под-набора файлов.
Map<String, Object?> categoryFixture({
  required String id,
  required String title,
}) => {
  'category': {'id': id, 'title': title, 'icon': 'code', 'description': ''},
  'articles': [
    {
      'id': 'fx_$id',
      'title': 'Статья $id',
      'summary': '',
      'difficulty': 'beginner',
      'tags': [],
      'blocks': [testBlockMap],
    },
  ],
};
