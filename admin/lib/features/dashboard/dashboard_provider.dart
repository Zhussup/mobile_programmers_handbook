import 'package:flutter/foundation.dart';

import '../../core/models/admin_user.dart';
import '../../core/models/article.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/json_utils.dart';

/// Сводные показатели для `/dashboard`.
class DashboardStats {
  const DashboardStats({
    this.users = 0,
    this.admins = 0,
    this.articles = 0,
    this.published = 0,
  });

  final int users;
  final int admins;
  final int articles;
  final int published;

  int get drafts => articles - published;
}

/// Загружает сводку двумя запросами к административным спискам.
class DashboardProvider extends ChangeNotifier {
  DashboardProvider({required this.api});

  final ApiClient api;

  DashboardStats _stats = const DashboardStats();
  bool _loading = false;
  String? _errorMessage;

  DashboardStats get stats => _stats;
  bool get loading => _loading;
  String? get errorMessage => _errorMessage;

  Future<void> load() async {
    _loading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final results = await Future.wait<dynamic>([
        api.get('/admin/users'),
        api.get('/admin/articles'),
      ]);

      final users = asJsonList(
        results[0],
        keys: const ['items', 'users'],
      ).map(AdminUser.fromJson).toList();
      final articles = asJsonList(
        results[1],
        keys: const ['items', 'articles'],
      ).map(Article.fromJson).toList();

      _stats = DashboardStats(
        users: users.length,
        admins: users.where((user) => user.isAdmin).length,
        articles: articles.length,
        published: articles.where((article) => article.isPublished).length,
      );
    } on ApiException catch (error) {
      _errorMessage = error.message;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
