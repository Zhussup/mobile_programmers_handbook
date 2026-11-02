import 'dart:async';
import 'dart:io';

import 'package:mob_kurs_backend/api/router.dart';
import 'package:mob_kurs_backend/core/db.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Точка входа backend-сервера.
///
/// Переменные окружения:
/// - `PORT` — порт (по умолчанию 8080);
/// - `DB_PATH` — путь к файлу SQLite (по умолчанию `data/app.db`);
/// - `SEED_DIR` — каталог JSON-контента для seed.
Future<void> main() async {
  final rawPort = Platform.environment['PORT'];
  final port = rawPort == null ? 8080 : int.tryParse(rawPort);
  if (port == null || port < 1 || port > 65535) {
    stderr.writeln('Некорректный PORT: $rawPort');
    exitCode = 2;
    return;
  }

  final db = await openAppDatabase();
  final handler = createHandler(db);

  final users = await _count(db, 'users');
  final categories = await _count(db, 'categories');
  final articles = await _count(db, 'articles');

  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  stdout.writeln(
    'Backend запущен: http://localhost:$port/api '
    '(пользователей: $users, категорий: $categories, статей: $articles)',
  );

  final done = Completer<void>();
  Future<void> shutdown(String signal) async {
    stdout.writeln('Получен $signal, остановка сервера...');
    await server.close(force: true);
    await db.close();
    if (!done.isCompleted) done.complete();
  }

  final sigint = ProcessSignal.sigint.watch().listen((_) => shutdown('SIGINT'));
  StreamSubscription<ProcessSignal>? sigterm;
  try {
    sigterm = ProcessSignal.sigterm.watch().listen((_) => shutdown('SIGTERM'));
  } on UnsupportedError {
    // Windows не поддерживает SIGTERM — достаточно SIGINT.
  }

  await done.future;
  await sigint.cancel();
  await sigterm?.cancel();
  stdout.writeln('Сервер остановлен, соединение с БД закрыто');
}

Future<int> _count(Database db, String table) async {
  final rows = await db.rawQuery('SELECT COUNT(*) AS count FROM $table');
  return rows.first['count'] as int;
}
