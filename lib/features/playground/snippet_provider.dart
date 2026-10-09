import '../auth/session_provider.dart' show SessionProvider;
import '../reference/user_scoped_provider.dart';
import 'snippet_model.dart';
import 'snippet_repository.dart';

/// Провайдер сниппетов песочницы (P10): список своих сниппетов + CRUD с
/// уведомлением слушателей (список и счётчик статистики перерисовываются
/// сразу, без перечитывания БД).
///
/// user-scoped: подписан на [SessionProvider] — сменился пользователь →
/// полная перезагрузка, гость → пустое состояние (UserScopedProvider). В БД
/// данные лежат под своим user_id — чужие сниппеты ни читаются, ни пишутся,
/// даже при попытке открыть `/playground/edit/:id` по чужому id.
class SnippetProvider extends UserScopedProvider {
  /// Провайдер поверх репозитория + подписка на [SessionProvider].
  SnippetProvider({
    required this.repository,
    required SessionProvider session,
  }) : super(session);

  /// Репозиторий сниппетов (SQLite).
  final SnippetRepository repository;

  List<Snippet> _entries = const [];
  bool _loading = true;

  /// Загружается ли сейчас список (первая загрузка).
  bool get loading => _loading;

  /// Сниппеты пользователя (свежие изменения раньше — сортировка репозитория).
  List<Snippet> get entries => List.unmodifiable(_entries);

  /// Сниппет пользователя по id (null — не найден у текущего пользователя).
  Snippet? snippetById(int id) {
    for (final snippet in _entries) {
      if (snippet.id == id) return snippet;
    }
    return null;
  }

  @override
  Future<void> loadForUser(int? userId, int token) async {
    if (userId == null) {
      // Гость: состояние пустое (данные прошлого пользователя не видны).
      _entries = const [];
      _loading = false;
      return;
    }
    _loading = true;
    try {
      final records = await repository.listForUser(userId);
      if (!isActual(token)) return; // пользователь сменился за время запроса
      _entries = records;
    } on Exception {
      if (!isActual(token)) return;
      // Сбой БД не роняет приложение: пустое состояние (актуальную
      // перезагрузку, запущенную позже, никто не перетирает).
      _entries = const [];
    } finally {
      _loading = false;
    }
  }

  /// Создание сниппета текущего пользователя.
  ///
  /// Возвращает созданную модель или null (гость — приватные маршруты под
  /// guard'ом, поэтому null возможен только в гонке logout'а). Ошибка БД
  /// пробрасывается — экран показывает снекбар ошибки и не закрывается.
  Future<Snippet?> create({
    required String title,
    required SnippetLanguage language,
    required String code,
    String? expectedOutput,
  }) async {
    final userId = currentUserId;
    if (userId == null) return null; // гость: ничего не создаём
    final token = beginLoad();
    try {
      final created = await repository.create(
        userId: userId,
        title: title,
        language: language,
        code: code,
        expectedOutput: expectedOutput,
      );
      if (isActual(token)) {
        // Свежий сниппет — первый в списке (updated_at у него максимален).
        _entries = [created, ..._entries];
        notifyDataChanged();
      }
      return created;
    } on Exception {
      if (!isActual(token)) return null;
      rethrow; // UI гасит в снекбар ошибки
    }
  }

  /// Обновление сниппета текущего пользователя (updated_at трогает
  /// репозиторий). Возвращает обновлённую модель или null — сниппет не
  /// найден у текущего пользователя (ошибка «удалён/чужой» для UI).
  Future<Snippet?> update(
    Snippet snippet, {
    required String title,
    required SnippetLanguage language,
    required String code,
    String? expectedOutput,
  }) async {
    final userId = currentUserId;
    if (userId == null) return null;
    final token = beginLoad();
    try {
      final updated = await repository.update(
        userId: userId,
        id: snippet.id,
        title: title,
        language: language,
        code: code,
        expectedOutput: expectedOutput,
      );
      if (updated == null) return null; // нет БД-строки у этого пользователя
      if (isActual(token) && snippetById(snippet.id) != null) {
        _replaceLocal(updated);
        notifyDataChanged();
      }
      return updated;
    } on Exception {
      if (!isActual(token)) return null;
      rethrow;
    }
  }

  /// Удаление сниппета текущего пользователя. Возвращает true, если
  /// репозиторий реально удалил строку.
  Future<bool> delete(int id) async {
    final userId = currentUserId;
    if (userId == null) return false;
    final token = beginLoad();
    final deleted = await repository.delete(userId, id);
    if (!isActual(token)) return deleted;
    if (deleted) {
      final next = [..._entries]..removeWhere((s) => s.id == id);
      _entries = next;
      notifyDataChanged();
    }
    return deleted;
  }

  /// Локальная замена записи без перечитывания БД (сохраняет позицию —
  /// список сортируется по updated_at, у обновлённого она максимальна... по
  /// правилам репозитория обновлённый поднимается наверх; для простоты
  /// применяем модель репозитория и переставляем её первой).
  void _replaceLocal(Snippet updated) {
    final others = _entries
        .where((snippet) => snippet.id != updated.id)
        .toList();
    _entries = [updated, ...others];
  }
}