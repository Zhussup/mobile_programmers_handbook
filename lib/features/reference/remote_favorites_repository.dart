import 'package:flutter/foundation.dart' show debugPrint;

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import 'favorites_data_source.dart';
import 'favorites_repository.dart';

/// Удалённый репозиторий избранного (КР_2_2).
///
/// Источник истины — `GET/POST/DELETE /favorites`. Успешный список
/// сохраняется в sqflite ([FavoritesRepository.replaceForUser]); при
/// сетевой ошибке список отдаётся из кэша и [servedFromCache] = true.
class RemoteFavoritesRepository implements FavoritesDataSource {
  /// Репозиторий поверх API-клиента и локального кэша.
  RemoteFavoritesRepository({required this._apiClient, required this._cache});

  final ApiClient _apiClient;
  final FavoritesRepository _cache;

  /// Известные id избранного (последний успешный список) — чтобы toggle
  /// не запрашивал список перед каждым переключением.
  Set<String>? _knownIds;
  bool _servedFromCache = false;

  @override
  bool get servedFromCache => _servedFromCache;

  @override
  Future<bool> isFavorite(int userId, String articleId) async {
    final known = _knownIds;
    if (known != null) return known.contains(articleId);
    return _cache.isFavorite(userId, articleId);
  }

  @override
  Future<List<FavoriteRecord>> listForUser(int userId) async {
    _servedFromCache = false;
    try {
      final data = await _apiClient.get('/favorites');
      final records = [for (final item in _asList(data)) _parseFavorite(item)];
      _knownIds = {for (final record in records) record.articleId};
      try {
        await _cache.replaceForUser(userId, records);
      } catch (e) {
        debugPrint('Кэш избранного: не удалось сохранить ($e)');
      }
      return records;
    } on ApiException catch (e) {
      if (!e.isNetwork) rethrow;
      _servedFromCache = true;
      final cached = await _cache.listForUser(userId);
      _knownIds = {for (final record in cached) record.articleId};
      return cached;
    }
  }

  @override
  Future<bool> toggle(int userId, String articleId) async {
    _servedFromCache = false;
    final wasFavorite = await isFavorite(userId, articleId);
    if (wasFavorite) {
      await _apiClient.delete('/favorites/$articleId');
      await _cache.toggle(userId, articleId);
      _knownIds?.remove(articleId);
      return false;
    }
    // POST идемпотентен: повторное добавление не дублирует запись.
    await _apiClient.post('/favorites/$articleId');
    await _cache.toggle(userId, articleId);
    (_knownIds ??= <String>{}).add(articleId);
    return true;
  }

  /// Ответ API → список элементов (понимает и массив, и обёртку).
  static List<Object?> _asList(Object? data) {
    if (data is List) return data;
    if (data is Map) {
      for (final key in const ['items', 'favorites']) {
        final nested = data[key];
        if (nested is List) return nested;
      }
    }
    return const [];
  }

  /// Элемент ответа → запись избранного.
  static FavoriteRecord _parseFavorite(Object? item) {
    if (item is String) {
      return FavoriteRecord(articleId: item, createdAt: DateTime.now());
    }
    if (item is Map) {
      final map = Map<String, dynamic>.from(item);
      Object? rawId = map['article_id'] ?? map['articleId'] ?? map['id'];
      final article = map['article'];
      if (rawId == null && article is Map) rawId = article['id'];
      final rawAt = map['created_at'] ?? map['createdAt'];
      return FavoriteRecord(
        articleId: rawId?.toString() ?? '',
        createdAt: DateTime.tryParse(rawAt?.toString() ?? '') ?? DateTime.now(),
      );
    }
    return FavoriteRecord(articleId: '', createdAt: DateTime.now());
  }
}
