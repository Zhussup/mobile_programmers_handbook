import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../core/db/app_database.dart';

/// Снимок кэша справочника: исходные JSON-объекты категорий и статей.
class CachedReference {
  /// Создание снимка.
  const CachedReference({required this.categories, required this.articles});

  /// Категории (порядок сохранён в sort_order).
  final List<Map<String, dynamic>> categories;

  /// Статьи в исходном JSON-виде (разбор — на стороне репозитория).
  final List<Map<String, dynamic>> articles;

  /// Кэш пуст (нет ни категорий, ни статей).
  bool get isEmpty => categories.isEmpty && articles.isEmpty;
}

/// Кэш контента API в sqflite (КР_2_2, раздел 6 контракта).
///
/// Сохраняет ТОЛЬКО последний успешный ответ `/categories` и `/articles`.
/// При сетевой ошибке удалённый репозиторий читает этот снимок и отдаёт
/// сохранённые данные, показывая баннер «Нет связи».
class ReferenceCache {
  /// Кэш поверх уже открытой БД (той же, что user-данные).
  ReferenceCache({required this.db});

  /// Открытая база.
  final Database db;

  /// Сохранить снимок: полная замена таблиц кэша в одной транзакции.
  Future<void> save({
    required List<Map<String, dynamic>> categories,
    required List<Map<String, dynamic>> articles,
  }) async {
    final cachedAt = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await txn.delete(AppDbTables.cacheCategories);
      await txn.delete(AppDbTables.cacheArticles);
      final batch = txn.batch();
      for (var i = 0; i < categories.length; i++) {
        final category = categories[i];
        batch.insert(AppDbTables.cacheCategories, {
          'id': category['id']?.toString() ?? '$i',
          'payload': jsonEncode(category),
          'sort_order': i,
          'cached_at': cachedAt,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final article in articles) {
        final id = article['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        batch.insert(AppDbTables.cacheArticles, {
          'id': id,
          'category_id': _categoryIdOf(article),
          'payload': jsonEncode(article),
          'cached_at': cachedAt,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  /// Прочитать снимок (null — кэш ещё ни разу не заполнялся).
  Future<CachedReference?> read() async {
    final categoryRows = await db.query(
      AppDbTables.cacheCategories,
      orderBy: 'sort_order ASC',
    );
    final articleRows = await db.query(AppDbTables.cacheArticles);
    if (categoryRows.isEmpty && articleRows.isEmpty) return null;

    return CachedReference(
      categories: [
        for (final row in categoryRows)
          if (_decode(row['payload']) case final Map<String, dynamic> map) map,
      ],
      articles: [
        for (final row in articleRows)
          if (_decode(row['payload']) case final Map<String, dynamic> map) map,
      ],
    );
  }

  /// Очистить кэш (используется тестами/при смене режима).
  Future<void> clear() async {
    await db.delete(AppDbTables.cacheCategories);
    await db.delete(AppDbTables.cacheArticles);
  }

  /// id категории статьи из исходного JSON.
  static String _categoryIdOf(Map<String, dynamic> article) {
    final direct = article['category_id'] ?? article['categoryId'];
    if (direct is String && direct.isNotEmpty) return direct;
    final nested = article['category'];
    if (nested is Map) {
      final id = nested['id'];
      if (id is String) return id;
    }
    return '';
  }

  /// Декодирование payload; битая строка пропускается (defensive).
  static Object? _decode(Object? raw) {
    if (raw is! String) return null;
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }
}
