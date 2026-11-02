import 'package:flutter/foundation.dart' show immutable;

/// Модель пользователя (дата-класс данных таблицы `users`).
@immutable
class UserModel {
  /// Создание модели пользователя из данных таблицы `users`.
  const UserModel({
    required this.id,
    required this.username,
    required this.email,
    required this.avatarColor,
    required this.createdAt,
  });

  /// Id записи (PK таблицы users).
  final int id;

  /// Имя пользователя (уникально без учёта регистра).
  final String username;

  /// Email (уникален без учёта регистра).
  final String email;

  /// Цвет аватара: hex-строка вида '#RRGGBB'.
  final String avatarColor;

  /// Дата регистрации (в БД хранится ISO-8601 строкой).
  final DateTime createdAt;

  /// Первая буква имени — текст аватара.
  String get avatarLetter => username.isEmpty ? '?' : username[0].toUpperCase();

  /// Разбор пользователя из JSON API (`{"id":3,"username":...}`).
  ///
  /// Терпим к необязательным/альтернативным именам полей: backend отдаёт
  /// `avatar_color`/`created_at`, но клиент не должен падать на вариантах
  /// camelCase или отсутствующей дате.
  factory UserModel.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final id = rawId is int
        ? rawId
        : int.tryParse(rawId?.toString() ?? '') ?? 0;
    final createdAtRaw = json['created_at'] ?? json['createdAt'];
    return UserModel(
      id: id,
      username: (json['username'] as String?)?.trim() ?? '',
      email: (json['email'] as String?)?.trim() ?? '',
      avatarColor:
          (json['avatar_color'] ?? json['avatarColor']) as String? ??
          '#3949AB',
      createdAt:
          DateTime.tryParse(createdAtRaw?.toString() ?? '') ?? DateTime.now(),
    );
  }

  /// Разбор строки запроса таблицы `users` в модель.
  factory UserModel.fromMap(Map<String, Object?> map) {
    return UserModel(
      id: map['id']! as int,
      username: map['username']! as String,
      email: map['email']! as String,
      avatarColor: map['avatar_color'] as String? ?? '#2AA79B',
      createdAt: DateTime.parse(map['created_at']! as String),
    );
  }

  /// Модель → строка таблицы (id — автоинкремент, при INSERT не передаётся).
  Map<String, Object?> toMap() {
    return {
      'username': username,
      'email': email,
      'avatar_color': avatarColor,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Модель → JSON для кэша профиля (восстановление сессии офлайн).
  Map<String, Object?> toJson() => {
    'id': id,
    'username': username,
    'email': email,
    'avatar_color': avatarColor,
    'created_at': createdAt.toIso8601String(),
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserModel &&
        other.id == id &&
        other.username == username &&
        other.email == email &&
        other.avatarColor == avatarColor &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode => Object.hash(id, username, email, avatarColor, createdAt);
}
