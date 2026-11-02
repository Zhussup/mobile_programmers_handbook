import 'package:flutter/foundation.dart' show debugPrint;

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../auth/user_model.dart';
import 'profile_data_source.dart';
import 'profile_repository.dart';

/// Удалённый репозиторий профиля (КР_2_2).
///
/// `PUT /profile` — данные и цвет аватара, `PUT /profile/password` — смена
/// пароля. Ошибки валидации/конфликты приводятся к [ProfileException] с
/// привязкой к полю формы (inline-подсветка на экране редактирования).
class RemoteProfileRepository implements ProfileDataSource {
  /// Репозиторий поверх API-клиента.
  RemoteProfileRepository({required this._apiClient});

  final ApiClient _apiClient;

  @override
  Future<UserModel> updateProfile(
    int userId, {
    String? username,
    String? email,
  }) async {
    final body = <String, Object?>{
      if (username != null) 'username': username.trim(),
      if (email != null) 'email': email.trim(),
    };
    if (body.isEmpty) {
      final current = await getUserRow(userId);
      if (current == null) {
        throw const ProfileException('Пользователь не найден');
      }
      return current;
    }
    try {
      final data = await _apiClient.put('/profile', body: body);
      return _parseUser(data);
    } on ApiException catch (e) {
      throw _mapProfileError(e);
    }
  }

  @override
  Future<UserModel> updateAvatarColor(int userId, String colorHex) async {
    try {
      final data = await _apiClient.put(
        '/profile',
        body: {'avatar_color': colorHex},
      );
      return _parseUser(data);
    } on ApiException catch (e) {
      throw _mapProfileError(e);
    }
  }

  @override
  Future<void> changePassword({
    required int userId,
    required String oldPassword,
    required String newPassword,
  }) async {
    try {
      await _apiClient.put(
        '/profile/password',
        body: {'old_password': oldPassword, 'new_password': newPassword},
      );
    } on ApiException catch (e) {
      throw _mapProfileError(e);
    }
  }

  @override
  Future<UserModel?> getUserRow(int userId) async {
    try {
      final data = await _apiClient.get('/auth/me');
      return _parseUser(data);
    } on ApiException catch (e) {
      debugPrint('Профиль: /auth/me недоступен (${e.code})');
      return null;
    }
  }

  /// Пользователь из ответа API (допускает обёртку `{user: {...}}`).
  static UserModel _parseUser(Object? data) {
    Object? raw = data;
    if (data is Map && data['user'] is Map) raw = data['user'];
    if (raw is! Map) throw const ProfileException('Некорректный ответ сервера');
    return UserModel.fromJson(Map<String, dynamic>.from(raw));
  }

  /// [ApiException] → русская [ProfileException] с полем формы.
  static ProfileException _mapProfileError(ApiException e) {
    if (e.type == ApiErrorType.validation) {
      final username = e.fields['username'];
      if (username != null && username.isNotEmpty) {
        return ProfileException(username, field: ProfileField.username);
      }
      final email = e.fields['email'];
      if (email != null && email.isNotEmpty) {
        return ProfileException(email, field: ProfileField.email);
      }
      final oldPassword = e.fields['old_password'] ?? e.fields['oldPassword'];
      if (oldPassword != null && oldPassword.isNotEmpty) {
        return ProfileException(oldPassword, field: ProfileField.oldPassword);
      }
      final lower = e.message.toLowerCase();
      if (lower.contains('стар') && lower.contains('парол')) {
        return ProfileException(e.message, field: ProfileField.oldPassword);
      }
    }

    if (e.type == ApiErrorType.conflict) {
      final lower = e.message.toLowerCase();
      if (lower.contains('email') || lower.contains('почт')) {
        return ProfileException(e.message, field: ProfileField.email);
      }
      if (lower.contains('имен') || lower.contains('username')) {
        return ProfileException(e.message, field: ProfileField.username);
      }
    }

    if (e.isUserBlocked) {
      return const ProfileException(
        'Учётная запись заблокирована администратором.',
      );
    }
    return ProfileException(e.message);
  }
}
