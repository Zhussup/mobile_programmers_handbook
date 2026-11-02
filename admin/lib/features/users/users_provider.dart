import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/models/admin_user.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/json_utils.dart';

/// Загрузка и изменение пользователей через `/api/admin/users`.
class UsersProvider extends ChangeNotifier {
  UsersProvider({required this.api, this.currentUserId});

  final ApiClient api;

  /// id текущего администратора: себя нельзя блокировать и понижать.
  final int? currentUserId;

  List<AdminUser> _users = <AdminUser>[];
  bool _loading = false;
  String? _errorMessage;
  String _query = '';
  Timer? _searchDebounce;
  int _requestId = 0;

  List<AdminUser> get users => List.unmodifiable(_users);
  bool get loading => _loading;
  String? get errorMessage => _errorMessage;
  String get query => _query;

  bool isSelf(AdminUser user) =>
      currentUserId != null && user.id == currentUserId;

  /// Загружает список. Вызывается при открытии экрана и по кнопке «Обновить».
  Future<void> load() async {
    final requestId = ++_requestId;
    _loading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final data = await api.get(
        '/admin/users',
        query: <String, dynamic>{'q': _query},
      );
      if (requestId != _requestId) return;
      _users = asJsonList(
        data,
        keys: const ['items', 'users'],
      ).map(AdminUser.fromJson).toList();
    } on ApiException catch (error) {
      if (requestId != _requestId) return;
      _errorMessage = error.message;
    } finally {
      if (requestId == _requestId) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  /// Поиск с небольшой задержкой, чтобы не дёргать API на каждый символ.
  void search(String value) {
    _query = value;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), load);
    notifyListeners();
  }

  Future<AdminUser> createUser({
    required String username,
    required String email,
    required String password,
    required String role,
  }) async {
    final data = await api.post(
      '/admin/users',
      body: <String, dynamic>{
        'username': username.trim(),
        'email': email.trim(),
        'password': password,
        'role': role,
      },
    );
    final created = AdminUser.fromJson(data);
    if (created.id != 0) {
      _users = <AdminUser>[..._users, created];
      notifyListeners();
      return created;
    }
    await load();
    return created;
  }

  Future<AdminUser> updateUser(
    AdminUser user, {
    required String username,
    required String email,
    required String role,
    String? avatarColor,
  }) async {
    final data = await api.put(
      '/admin/users/${user.id}',
      body: <String, dynamic>{
        'username': username.trim(),
        'email': email.trim(),
        'role': role,
        if (avatarColor != null && avatarColor.isNotEmpty)
          'avatar_color': avatarColor,
      },
    );
    final updated = _mergeResponse(
      user,
      data,
      fallback: user.copyWith(
        username: username.trim(),
        email: email.trim(),
        role: role,
        avatarColor: avatarColor,
      ),
    );
    _replace(updated);
    return updated;
  }

  /// Блокировка/разблокировка. Себя блокировать нельзя.
  Future<AdminUser> setBlocked(AdminUser user, bool blocked) async {
    if (isSelf(user) && blocked) {
      throw const ApiException(
        kind: ApiErrorKind.forbidden,
        statusCode: 403,
        message: 'Нельзя заблокировать самого себя.',
      );
    }
    final data = await api.patch(
      '/admin/users/${user.id}/block',
      body: <String, dynamic>{'blocked': blocked},
    );
    final updated = _mergeResponse(
      user,
      data,
      fallback: user.copyWith(isBlocked: blocked),
    );
    _replace(updated);
    return updated;
  }

  /// Смена роли. Свою роль понизить нельзя (проверка и на сервере).
  Future<AdminUser> setRole(AdminUser user, String role) async {
    if (isSelf(user) && role != 'admin') {
      throw const ApiException(
        kind: ApiErrorKind.forbidden,
        statusCode: 403,
        message: 'Нельзя понизить собственную роль.',
      );
    }
    final data = await api.patch(
      '/admin/users/${user.id}/role',
      body: <String, dynamic>{'role': role},
    );
    final updated = _mergeResponse(
      user,
      data,
      fallback: user.copyWith(role: role),
    );
    _replace(updated);
    return updated;
  }

  AdminUser _mergeResponse(
    AdminUser source,
    dynamic data, {
    required AdminUser fallback,
  }) {
    final map = asJsonMap(data);
    if (map.isEmpty) return fallback;
    final parsed = AdminUser.fromJson(map);
    return parsed.id == 0 ? fallback : parsed;
  }

  void _replace(AdminUser updated) {
    _users = _users
        .map((item) => item.id == updated.id ? updated : item)
        .toList();
    notifyListeners();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }
}
