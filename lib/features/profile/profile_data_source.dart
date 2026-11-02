import '../auth/user_model.dart';

/// Контракт репозитория профиля (локально — sqflite, удалённо — API).
abstract class ProfileDataSource {
  /// Изменение профиля (username и/или email).
  Future<UserModel> updateProfile(
    int userId, {
    String? username,
    String? email,
  });

  /// Изменение цвета аватара.
  Future<UserModel> updateAvatarColor(int userId, String colorHex);

  /// Смена пароля (проверка старого пароля).
  Future<void> changePassword({
    required int userId,
    required String oldPassword,
    required String newPassword,
  });

  /// Строка пользователя по id (null — записи нет).
  Future<UserModel?> getUserRow(int userId);
}
