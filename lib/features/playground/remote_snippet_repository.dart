import 'package:flutter/foundation.dart' show debugPrint;

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import 'snippet_data_source.dart';
import 'snippet_model.dart';
import 'snippet_repository.dart';

/// Удалённый репозиторий сниппетов песочницы (КР_2_2).
///
/// CRUD через `/snippets`; успешные ответы сохраняются в локальный кэш
/// ([SnippetRepository]). При сетевой ошибке список/чтение отдаются из
/// кэша, а изменяющие операции завершаются ошибкой (без ложного «сохранено»).
class RemoteSnippetRepository implements SnippetDataSource {
  /// Репозиторий поверх API-клиента и локального кэша.
  RemoteSnippetRepository({required this._apiClient, required this._cache});

  final ApiClient _apiClient;
  final SnippetRepository _cache;
  bool _servedFromCache = false;

  @override
  bool get servedFromCache => _servedFromCache;

  @override
  Future<List<Snippet>> listForUser(int userId) async {
    _servedFromCache = false;
    try {
      final data = await _apiClient.get('/snippets');
      final snippets = [
        for (final item in _asList(data)) _parseSnippet(item, userId),
      ];
      try {
        await _cache.replaceForUser(userId, snippets);
      } catch (e) {
        debugPrint('Кэш сниппетов: не удалось сохранить ($e)');
      }
      return snippets;
    } on ApiException catch (e) {
      if (!e.isNetwork) rethrow;
      _servedFromCache = true;
      return _cache.listForUser(userId);
    }
  }

  @override
  Future<Snippet?> getById(int userId, int id) async {
    _servedFromCache = false;
    try {
      final data = await _apiClient.get('/snippets/$id');
      final snippet = _parseSnippet(data, userId);
      await _cache.upsert(snippet);
      return snippet;
    } on ApiException catch (e) {
      if (e.type == ApiErrorType.notFound) return null;
      if (e.isNetwork) {
        _servedFromCache = true;
        return _cache.getById(userId, id);
      }
      rethrow;
    }
  }

  @override
  Future<Snippet> create({
    required int userId,
    required String title,
    required SnippetLanguage language,
    required String code,
    String? expectedOutput,
  }) async {
    _servedFromCache = false;
    final data = await _apiClient.post(
      '/snippets',
      body: {
        'title': title.trim(),
        'language': language.raw,
        'code': code,
        'expected_output': expectedOutput ?? '',
      },
    );
    final snippet = _parseSnippet(data, userId);
    await _cache.upsert(snippet);
    return snippet;
  }

  @override
  Future<Snippet?> update({
    required int userId,
    required int id,
    required String title,
    required SnippetLanguage language,
    required String code,
    String? expectedOutput,
  }) async {
    _servedFromCache = false;
    try {
      final data = await _apiClient.put(
        '/snippets/$id',
        body: {
          'title': title.trim(),
          'language': language.raw,
          'code': code,
          'expected_output': expectedOutput ?? '',
        },
      );
      final snippet = _parseSnippet(data, userId);
      await _cache.upsert(snippet);
      return snippet;
    } on ApiException catch (e) {
      if (e.type == ApiErrorType.notFound) return null;
      rethrow;
    }
  }

  @override
  Future<bool> delete(int userId, int id) async {
    _servedFromCache = false;
    try {
      await _apiClient.delete('/snippets/$id');
    } on ApiException catch (e) {
      if (e.type == ApiErrorType.notFound) return false;
      rethrow;
    }
    await _cache.delete(userId, id);
    return true;
  }

  /// Ответ API → список элементов (массив или обёртка).
  static List<Object?> _asList(Object? data) {
    if (data is List) return data;
    if (data is Map) {
      for (final key in const ['items', 'snippets']) {
        final nested = data[key];
        if (nested is List) return nested;
      }
    }
    return const [];
  }

  /// Элемент ответа API → модель сниппета.
  static Snippet _parseSnippet(Object? data, int userId) {
    if (data is! Map) throw ApiException.parse();
    final map = Map<String, dynamic>.from(data);
    final now = DateTime.now().toIso8601String();

    return Snippet(
      id: _asInt(map['id']),
      userId: _asInt(map['user_id'] ?? map['userId'] ?? userId),
      title: (map['title'] as String?)?.trim() ?? '',
      language: snippetLanguageFromRaw(map['language']),
      code: (map['code'] as String?) ?? '',
      expectedOutput:
          (map['expected_output'] ?? map['expectedOutput']) as String?,
      createdAt: _asDate(map['created_at'] ?? map['createdAt'], now),
      updatedAt: _asDate(
        map['updated_at'] ?? map['updatedAt'] ?? map['created_at'],
        now,
      ),
    );
  }

  /// Число из JSON (int/num/строка); 0 — неизвестно.
  static int _asInt(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  /// Дата из JSON (ISO-строка); fallback — [fallback].
  static DateTime _asDate(Object? raw, String fallback) =>
      DateTime.tryParse(raw?.toString() ?? '') ?? DateTime.parse(fallback);
}
