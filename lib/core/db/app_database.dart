import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite/sqflite.dart';
// ffi-пакет — dev-зависимость по плану, но фабрика подменяется и в lib/
// (desktop-запуск); в тестах используется in-memory через эту же фабрику.
// ignore: depend_on_referenced_packages
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

/// Открытие локальной БД sqflite и схема данных.
///
/// Подводный камень №3 из плана: sqflite нативно работает только на
/// Android/iOS/macOS. На Linux/Windows (и в тестах) фабрику подменяем на
/// `sqflite_common_ffi`; в тестах используется in-memory БД. Подмена фабрики
/// выполняется в main() до любого обращения к БД.
///
/// Сессия пользователя в БД НЕ хранится (только shared_preferences),
/// поэтому таблицы сессии нет — см. схему в плане.
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  /// Имя файла БД на устройстве.
  static const String dbName = 'mob_kurs.db';

  /// Версия схемы БД (onCreate / onUpgrade миграции).
  ///
  /// v2 (КР_2_2): добавлены таблицы кэша контента API
  /// (`cache_categories`, `cache_articles`). Пользовательские таблицы не
  /// меняются — миграция только создаёт недостающие таблицы.
  static const int dbVersion = 2;

  Database? _db;

  /// Подмена фабрики sqflite на desktop-платформах.
  ///
  /// Вызывается из main() ДО первого обращения к БД (подводный камень №3).
  /// На Android/iOS оставляем фабрику по умолчанию.
  static void configureDatabaseFactory() {
    if (kIsWeb) return; // Web не является целевой платформой.
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      ffi.sqfliteFfiInit();
      databaseFactory = ffi.databaseFactoryFfi;
    }
  }

  /// Открытие БД (создаёт файл и схему при первом запуске).
  ///
  /// [path] — необязательный путь (используется в тестах: in-memory).
  /// Вызывается из main() ДО runApp; далее доступ через [db].
  Future<Database> open([String? path]) async {
    if (_db != null) return _db!;
    path ??= await _defaultPath();
    _db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: dbVersion,
        onCreate: onCreate,
        // v2: onCreate идемпотентен (CREATE TABLE IF NOT EXISTS), поэтому
        // onUpgrade создаёт недостающие таблицы кэша, не трогая данные.
        onUpgrade: (db, oldVersion, newVersion) async =>
            onCreate(db, newVersion),
      ),
    );
    return _db!;
  }

  /// Доступ к уже открытой БД (после [open]).
  Database get db {
    final database = _db;
    if (database == null) {
      throw StateError(
        'База данных не открыта: сначала AppDatabase.instance.open()',
      );
    }
    return database;
  }

  /// Закрыть БД (используется в тестах).
  Future<void> close() async {
    final database = _db;
    if (database != null) {
      await database.close();
      _db = null;
    }
  }

  /// Путь к файлу БД по умолчанию: getDatabasesPath + имя файла.
  Future<String> _defaultPath() async {
    final dir = await databaseFactory.getDatabasesPath();
    final separator = Platform.pathSeparator;
    return dir.endsWith(separator) ? '$dir$dbName' : '$dir$separator$dbName';
  }

  /// Создание схемы (вызывается из onCreate; доступно тестам для создания
  /// in-memory БД той же структурой).
  static Future<void> onCreate(Database db, int version) async {
    final batch = db.batch();
    createSchema(batch);
    await batch.commit(noResult: true);
  }

  /// Все CREATE-запросы схемы v2 (единым батчем).
  ///
  /// Все запросы идемпотентны (`IF NOT EXISTS`): повторный onCreate при
  /// миграции лишь добавляет недостающие таблицы и не удаляет данные.
  /// Имена/ключи — из AppConstants; запросы параметризованные, идентификаторы
  /// таблиц константные значения, не пользовательский ввод.
  static void createSchema(Batch batch) {
    // Пользователи: username и email уникальны БЕЗ учёта регистра.
    batch.execute('''
        CREATE TABLE IF NOT EXISTS ${AppDbTables.users} (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          username TEXT NOT NULL UNIQUE COLLATE NOCASE,
          email TEXT NOT NULL UNIQUE COLLATE NOCASE,
          password_hash TEXT NOT NULL,
          salt TEXT NOT NULL,
          avatar_color TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');

    // Избранное: статья задаётся строковым id из JSON-контента.
    batch.execute('''
        CREATE TABLE IF NOT EXISTS ${AppDbTables.favorites} (
          user_id INTEGER NOT NULL,
          article_id TEXT NOT NULL,
          created_at TEXT NOT NULL,
          PRIMARY KEY (user_id, article_id)
        )
      ''');

    // История просмотров: топ-20 по паре (user_id, viewed_at).
    batch.execute('''
        CREATE TABLE IF NOT EXISTS ${AppDbTables.history} (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id INTEGER NOT NULL,
          article_id TEXT NOT NULL,
          viewed_at TEXT NOT NULL
        )
      ''');
    batch.execute(
      'CREATE INDEX IF NOT EXISTS ${AppDbTables.idxHistoryUserViewed} '
      'ON ${AppDbTables.history} (user_id, viewed_at)',
    );

    // Сниппеты песочницы (CRUD — P10).
    batch.execute('''
        CREATE TABLE IF NOT EXISTS ${AppDbTables.userSnippets} (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id INTEGER NOT NULL,
          title TEXT NOT NULL,
          language TEXT NOT NULL,
          code TEXT NOT NULL,
          expected_output TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');

    // Кэш контента API (КР_2_2): последний успешный ответ /categories и
    // /articles. payload — исходный JSON объекта (для повторного разбора).
    batch.execute('''
        CREATE TABLE IF NOT EXISTS ${AppDbTables.cacheCategories} (
          id TEXT PRIMARY KEY,
          payload TEXT NOT NULL,
          sort_order INTEGER NOT NULL DEFAULT 0,
          cached_at TEXT NOT NULL
        )
      ''');
    batch.execute('''
        CREATE TABLE IF NOT EXISTS ${AppDbTables.cacheArticles} (
          id TEXT PRIMARY KEY,
          category_id TEXT NOT NULL DEFAULT '',
          payload TEXT NOT NULL,
          cached_at TEXT NOT NULL
        )
      ''');
    batch.execute(
      'CREATE INDEX IF NOT EXISTS ${AppDbTables.idxCacheArticlesCategory} '
      'ON ${AppDbTables.cacheArticles} (category_id)',
    );
  }
}

/// Имена таблиц и индексов схемы БД (используются и в таблицах, и в тестах).
///
/// Доступ к данным идёт через константные имена таблиц из [AppDbTables] —
/// значение всегда фиксировано, в SQL не подставляется пользовательский ввод.
class AppDbTables {
  AppDbTables._();

  static const String users = 'users';
  static const String favorites = 'favorites';
  static const String history = 'history';
  static const String userSnippets = 'user_snippets';
  static const String idxHistoryUserViewed = 'idx_history_user_viewed';

  /// Кэш контента API (только успешные ответы /categories и /articles).
  static const String cacheCategories = 'cache_categories';
  static const String cacheArticles = 'cache_articles';
  static const String idxCacheArticlesCategory = 'idx_cache_articles_category';
}
