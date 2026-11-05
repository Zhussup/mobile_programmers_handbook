import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/user.dart';
import 'auth.dart';

/// Версия схемы БД. При изменении схемы увеличьте и добавьте миграцию.
const int schemaVersion = 1;

/// Путь к БД по умолчанию (`backend/data/app.db` при запуске из backend/).
///
/// Переопределяется переменной окружения `DB_PATH`.
String defaultDatabasePath() {
  final fromEnv = Platform.environment['DB_PATH'];
  if (fromEnv != null && fromEnv.trim().isNotEmpty) return fromEnv.trim();
  // Запуск из корня проекта: backend/data/app.db. Из backend/: data/app.db.
  if (File(p.join('backend', 'pubspec.yaml')).existsSync()) {
    return p.join('backend', 'data', 'app.db');
  }
  return p.join('data', 'app.db');
}

/// Каталог с JSON-контентом для seed.
///
/// Приоритет: явный аргумент → `SEED_DIR` → `../assets/content/reference`
/// (запуск из `backend/`) → `assets/content/reference` (запуск из корня).
String resolveSeedDir([String? seedDir]) {
  if (seedDir != null && seedDir.trim().isNotEmpty) return seedDir.trim();
  final fromEnv = Platform.environment['SEED_DIR'];
  if (fromEnv != null && fromEnv.trim().isNotEmpty) return fromEnv.trim();
  for (final candidate in const [
    '../assets/content/reference',
    'assets/content/reference',
  ]) {
    if (Directory(candidate).existsSync()) return candidate;
  }
  return p.join('..', 'assets', 'content', 'reference');
}

/// Открытие БД, создание схемы и seed.
///
/// Для тестов передайте `path: inMemoryDatabasePath` и `seed: false`
/// (или `true`, если нужны учётные записи и контент).
Future<Database> openAppDatabase({
  String? path,
  String? seedDir,
  bool seed = true,
}) async {
  sqfliteFfiInit();
  final dbPath = path ?? defaultDatabasePath();
  if (dbPath != inMemoryDatabasePath) {
    final directory = Directory(p.dirname(dbPath));
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
  }

  final db = await databaseFactoryFfi.openDatabase(
    dbPath,
    options: OpenDatabaseOptions(
      version: schemaVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createSchema(db);
      },
      onUpgrade: _upgradeSchema,
    ),
  );

  if (seed) {
    await seedDatabase(db, seedDir: seedDir);
  }
  return db;
}

/// Создание всех таблиц и индексов (раздел 4 контракта).
Future<void> _createSchema(Database db) async {
  await db.execute('''
    CREATE TABLE users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      username TEXT NOT NULL UNIQUE COLLATE NOCASE,
      email TEXT NOT NULL UNIQUE COLLATE NOCASE,
      password_hash TEXT NOT NULL,
      salt TEXT NOT NULL,
      role TEXT NOT NULL DEFAULT 'user' CHECK (role IN ('admin','user')),
      is_blocked INTEGER NOT NULL DEFAULT 0,
      avatar_color TEXT NOT NULL DEFAULT '#3949AB',
      created_at TEXT NOT NULL
    )
  ''');

  await db.execute('''
    CREATE TABLE sessions (
      token TEXT PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      created_at TEXT NOT NULL,
      expires_at TEXT NOT NULL
    )
  ''');

  await db.execute('''
    CREATE TABLE categories (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      description TEXT NOT NULL DEFAULT '',
      icon TEXT NOT NULL DEFAULT 'book',
      sort_order INTEGER NOT NULL DEFAULT 0
    )
  ''');

  await db.execute('''
    CREATE TABLE articles (
      id TEXT PRIMARY KEY,
      category_id TEXT NOT NULL REFERENCES categories(id) ON DELETE RESTRICT,
      title TEXT NOT NULL,
      summary TEXT NOT NULL DEFAULT '',
      difficulty TEXT NOT NULL DEFAULT 'beginner'
        CHECK (difficulty IN ('beginner','intermediate','advanced')),
      tags TEXT NOT NULL DEFAULT '[]',
      blocks_json TEXT NOT NULL DEFAULT '[]',
      is_published INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');

  await db.execute('''
    CREATE TABLE favorites (
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      article_id TEXT NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
      created_at TEXT NOT NULL,
      PRIMARY KEY (user_id, article_id)
    )
  ''');

  await db.execute('''
    CREATE TABLE history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      article_id TEXT NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
      viewed_at TEXT NOT NULL
    )
  ''');

  await db.execute('''
    CREATE TABLE snippets (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      title TEXT NOT NULL,
      language TEXT NOT NULL CHECK (language IN ('cpp','dart')),
      code TEXT NOT NULL DEFAULT '',
      expected_output TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');

  await db.execute(
    'CREATE INDEX idx_history_user_viewed ON history(user_id, viewed_at DESC)',
  );
  await db.execute(
    'CREATE INDEX idx_articles_category ON articles(category_id)',
  );
  await db.execute('CREATE INDEX idx_sessions_user ON sessions(user_id)');
}

/// Миграции схемы. Версия 1 — базовая; будущие изменения добавляются здесь.
Future<void> _upgradeSchema(Database db, int oldVersion, int newVersion) async {
  // Пока обновлений схемы нет: при добавлении версии 2+ выполните
  // соответствующие ALTER/CREATE в блоке switch (oldVersion).
}

/// Seed: две учётные записи и контент из JSON-файлов.
///
/// Повторный запуск безопасен: пользователи не перезаписываются, а
/// категории/статьи вставляются через `INSERT OR IGNORE`.
Future<void> seedDatabase(Database db, {String? seedDir}) async {
  await _seedUsers(db);
  await _seedContent(db, seedDir);
}

Future<void> _seedUsers(Database db) async {
  final existing = await db.query('users', limit: 1);
  if (existing.isNotEmpty) return;

  final now = DateTime.now().toUtc().toIso8601String();
  final adminSalt = AuthService.generateSalt();
  final userSalt = AuthService.generateSalt();

  await db.transaction((txn) async {
    await txn.insert('users', {
      'username': 'admin',
      'email': 'admin@example.com',
      'password_hash': AuthService.hashPassword('admin123', adminSalt),
      'salt': adminSalt,
      'role': 'admin',
      'is_blocked': 0,
      'avatar_color': pickAvatarColor('admin'),
      'created_at': now,
    });
    await txn.insert('users', {
      'username': 'user',
      'email': 'user@example.com',
      'password_hash': AuthService.hashPassword('user123', userSalt),
      'salt': userSalt,
      'role': 'user',
      'is_blocked': 0,
      'avatar_color': pickAvatarColor('user'),
      'created_at': now,
    });
  });
}

Future<void> _seedContent(Database db, String? seedDir) async {
  // Контент добавляется только в пустые таблицы: повторный запуск не
  // возвращает удалённые администратором статьи и не перезаписывает правки.
  final categoryCount = await _count(db, 'categories');
  final articleCount = await _count(db, 'articles');
  if (categoryCount > 0 || articleCount > 0) return;

  final directory = Directory(resolveSeedDir(seedDir));
  if (!directory.existsSync()) {
    stderr.writeln('Seed: каталог контента не найден: ${directory.path}');
    return;
  }

  final files =
      directory
          .listSync()
          .whereType<File>()
          .where((file) => file.path.toLowerCase().endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  if (files.isEmpty) {
    stderr.writeln('Seed: в ${directory.path} нет JSON-файлов');
    return;
  }

  for (var index = 0; index < files.length; index++) {
    final file = files[index];
    Object? decoded;
    try {
      decoded = jsonDecode(await file.readAsString());
    } on FormatException catch (error) {
      stderr.writeln('Seed: пропущен ${file.path}: $error');
      continue;
    }
    if (decoded is! Map) continue;

    final rawCategory = decoded['category'];
    if (rawCategory is! Map) continue;
    final category = Map<String, dynamic>.from(rawCategory);
    final categoryId = category['id'];
    final categoryTitle = category['title'];
    if (categoryId is! String ||
        categoryId.isEmpty ||
        categoryTitle is! String ||
        categoryTitle.isEmpty) {
      continue;
    }

    final rawArticles = decoded['articles'];
    final now = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      await txn.insert('categories', {
        'id': categoryId,
        'title': categoryTitle,
        'description': category['description'] is String
            ? category['description']
            : '',
        'icon': category['icon'] is String ? category['icon'] : 'book',
        'sort_order': index,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);

      if (rawArticles is! List) return;
      for (final rawArticle in rawArticles) {
        if (rawArticle is! Map) continue;
        final article = Map<String, dynamic>.from(rawArticle);
        final articleId = article['id'];
        final articleTitle = article['title'];
        if (articleId is! String ||
            articleId.isEmpty ||
            articleTitle is! String ||
            articleTitle.isEmpty) {
          continue;
        }
        await txn.insert('articles', {
          'id': articleId,
          'category_id': categoryId,
          'title': articleTitle,
          'summary': article['summary'] is String ? article['summary'] : '',
          'difficulty': _seedDifficulty(article['difficulty']),
          'tags': jsonEncode(
            article['tags'] is List ? article['tags'] : const <Object?>[],
          ),
          'blocks_json': jsonEncode(
            article['blocks'] is List ? article['blocks'] : const <Object?>[],
          ),
          'is_published': 1,
          'created_at': now,
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }
}

String _seedDifficulty(Object? raw) {
  if (raw == 'beginner' || raw == 'intermediate' || raw == 'advanced') {
    return raw as String;
  }
  return 'beginner';
}

Future<int> _count(Database db, String table) async {
  final rows = await db.rawQuery('SELECT COUNT(*) AS count FROM $table');
  return rows.first['count'] as int;
}
