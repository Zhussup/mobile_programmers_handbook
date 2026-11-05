import '../utils/json_utils.dart';

/// Пользователь системы (роли `admin` / `user`).
class AdminUser {
  const AdminUser({
    required this.id,
    required this.username,
    required this.email,
    required this.role,
    required this.isBlocked,
    this.avatarColor = '#3949AB',
    this.createdAt = '',
  });

  final int id;
  final String username;
  final String email;
  final String role;
  final bool isBlocked;
  final String avatarColor;
  final String createdAt;

  bool get isAdmin => role == 'admin';

  String get roleLabel => isAdmin ? 'Администратор' : 'Пользователь';

  factory AdminUser.fromJson(dynamic json) {
    final map = asJsonMap(json);
    return AdminUser(
      id: asInt(map['id']),
      username: asString(map['username'], fallback: '—'),
      email: asString(map['email'], fallback: '—'),
      role: asString(map['role'], fallback: 'user'),
      isBlocked: asBool(map['is_blocked'] ?? map['isBlocked']),
      avatarColor: asString(
        map['avatar_color'] ?? map['avatarColor'],
        fallback: '#3949AB',
      ),
      createdAt: asString(map['created_at'] ?? map['createdAt']),
    );
  }

  AdminUser copyWith({
    String? username,
    String? email,
    String? role,
    bool? isBlocked,
    String? avatarColor,
  }) {
    return AdminUser(
      id: id,
      username: username ?? this.username,
      email: email ?? this.email,
      role: role ?? this.role,
      isBlocked: isBlocked ?? this.isBlocked,
      avatarColor: avatarColor ?? this.avatarColor,
      createdAt: createdAt,
    );
  }
}
