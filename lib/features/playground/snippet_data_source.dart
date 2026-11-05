import 'snippet_model.dart';

/// Контракт источника сниппетов песочницы (локально — sqflite, удалённо — API).
abstract class SnippetDataSource {
  /// Использован ли кэш из-за сетевой ошибки.
  bool get servedFromCache => false;

  /// Сниппеты пользователя (свежие изменения раньше).
  Future<List<Snippet>> listForUser(int userId);

  /// Создание сниппета.
  Future<Snippet> create({
    required int userId,
    required String title,
    required SnippetLanguage language,
    required String code,
    String? expectedOutput,
  });

  /// Сниппет пользователя по id (null — нет/чужой).
  Future<Snippet?> getById(int userId, int id);

  /// Изменение сниппета пользователя (null — нет/чужой).
  Future<Snippet?> update({
    required int userId,
    required int id,
    required String title,
    required SnippetLanguage language,
    required String code,
    String? expectedOutput,
  });

  /// Удаление сниппета пользователя (true — строка удалена).
  Future<bool> delete(int userId, int id);
}
