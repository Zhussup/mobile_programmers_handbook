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
