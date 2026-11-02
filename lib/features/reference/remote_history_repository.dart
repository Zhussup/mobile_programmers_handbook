import 'package:flutter/foundation.dart' show debugPrint;

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import 'history_data_source.dart';
import 'history_repository.dart';

/// Удалённый репозиторий истории (КР_2_2).
///
/// `GET /history?limit=20`, `POST /history/{articleId}`,
/// `DELETE /history`. Успешный список кэшируется в sqflite; при сетевой
/// ошибке отдаётся кэш и [servedFromCache] = true.
class RemoteHistoryRepository implements HistoryDataSource {
  /// Репозиторий поверх API-клиента и локального кэша.
  RemoteHistoryRepository({required this._apiClient, required this._cache});

  final ApiClient _apiClient;
  final HistoryRepository _cache;
  bool _servedFromCache = false;

  @override
  bool get servedFromCache => _servedFromCache;

  @override
  Future<List<HistoryRecordRaw>> listTop(int userId) async {
    _servedFromCache = false;
    try {
      final data = await _apiClient.get('/history', query: {'limit': '20'});
      final records = [for (final item in _asList(data)) _parseRecord(item)];
      try {
        await _cache.replaceForUser(userId, records);
      } catch (e) {
        debugPrint('Кэш истории: не удалось сохранить ($e)');
      }
      return records;
    } on ApiException catch (e) {
      if (!e.isNetwork) rethrow;
      _servedFromCache = true;
      return _cache.listTop(userId);
    }
  }

  @override
  Future<void> record(int userId, String articleId) async {
    _servedFromCache = false;
    await _apiClient.post('/history/$articleId');
    try {
      await _cache.record(userId, articleId);
    } catch (e) {
      debugPrint('Кэш истории: не удалось записать ($e)');
    }
  }

  @override
  Future<void> clear(int userId) async {
    _servedFromCache = false;
    await _apiClient.delete('/history');
    await _cache.clear(userId);
  }

  /// Ответ API → список элементов (массив или обёртка).
  static List<Object?> _asList(Object? data) {
    if (data is List) return data;
    if (data is Map) {
      for (final key in const ['items', 'history']) {
        final nested = data[key];
        if (nested is List) return nested;
      }
    }
    return const [];
  }

  /// Элемент ответа → запись истории.
  static HistoryRecordRaw _parseRecord(Object? item) {
    if (item is Map) {
      final map = Map<String, dynamic>.from(item);
      Object? rawId = map['article_id'] ?? map['articleId'] ?? map['id'];
      final article = map['article'];
      if (rawId == null && article is Map) rawId = article['id'];
      final rawAt = map['viewed_at'] ?? map['viewedAt'] ?? map['created_at'];
      return HistoryRecordRaw(
        articleId: rawId?.toString() ?? '',
        viewedAt: DateTime.tryParse(rawAt?.toString() ?? '') ?? DateTime.now(),
      );
    }
    return HistoryRecordRaw(articleId: '', viewedAt: DateTime.now());
  }
}
