import 'dart:convert';

import 'errors.dart';

/// Накопитель ошибок полей формы.
///
/// Обработчики добавляют сообщения и в конце выбрасывают единую
/// [ApiError.validation] с картой `fields`.
class FormValidator {
  final Map<String, String> _fields = {};

  /// Ошибки по полям (только чтение).
  Map<String, String> get fields => Map.unmodifiable(_fields);

  /// Есть ли хотя бы одна ошибка.
  bool get hasErrors => _fields.isNotEmpty;

  /// Добавить ошибку к полю (первое сообщение для поля сохраняется).
  void add(String field, String message) {
    _fields.putIfAbsent(field, () => message);
  }

  /// Добавить ошибку, если [error] не null.
  void check(String? error, String field) {
    if (error != null) add(field, error);
  }

  /// Выбросить ошибку валидации, если есть накопленные сообщения.
  Never fail([String message = 'Проверьте заполнение полей']) {
    throw ApiError.validation(
      message,
      fields: _fields.isEmpty ? null : Map.unmodifiable(_fields),
    );
  }
}

/// Проверка имени пользователя: 3–32 символа после обрезки пробелов.
String? validateUsername(Object? raw) {
  if (raw is! String) return 'Имя пользователя обязательно';
  final value = raw.trim();
  if (value.length < 3 || value.length > 32) {
    return 'Имя пользователя должно содержать от 3 до 32 символов';
  }
  return null;
}

/// Проверка адреса почты (простая, достаточная для учебного проекта).
String? validateEmail(Object? raw) {
  if (raw is! String) return 'Почта обязательна';
  final value = raw.trim();
  if (value.isEmpty) return 'Почта обязательна';
  final pattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  if (!pattern.hasMatch(value)) return 'Некорректный адрес почты';
  if (value.length > 254) return 'Адрес почты слишком длинный';
  return null;
}

/// Проверка пароля: не короче 6 символов.
String? validatePassword(Object? raw) {
  if (raw is! String) return 'Пароль обязателен';
  if (raw.length < 6) return 'Пароль должен содержать не менее 6 символов';
  if (raw.length > 128) return 'Пароль слишком длинный';
  return null;
}

/// Проверка цвета аватара в формате `#RRGGBB`.
String? validateAvatarColor(Object? raw) {
  if (raw is! String) return 'Цвет аватара должен быть строкой';
  if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(raw.trim())) {
    return 'Цвет аватара должен быть в формате #RRGGBB';
  }
  return null;
}

/// Проверка роли.
String? validateRole(Object? raw) {
  if (raw is! String || (raw != 'admin' && raw != 'user')) {
    return 'Роль должна быть admin или user';
  }
  return null;
}

/// Проверка уровня сложности статьи.
String? validateDifficulty(Object? raw) {
  if (raw is! String ||
      !const {'beginner', 'intermediate', 'advanced'}.contains(raw)) {
    return 'Сложность должна быть beginner, intermediate или advanced';
  }
  return null;
}

/// Проверка языка сниппета.
String? validateLanguage(Object? raw) {
  if (raw is! String || (raw != 'cpp' && raw != 'dart')) {
    return 'Язык должен быть cpp или dart';
  }
  return null;
}

/// Проверка заголовка статьи/сниппета.
String? validateTitle(Object? raw, {int maxLength = 200}) {
  if (raw is! String || raw.trim().isEmpty) return 'Заголовок обязателен';
  final value = raw.trim();
  if (value.length > maxLength) {
    return 'Заголовок не должен превышать $maxLength символов';
  }
  return null;
}

/// Разбор массива строк (принимает и JSON-строку, и готовый массив).
/// Возвращает `null`, если значение некорректно.
List<String>? parseStringList(Object? raw) {
  Object? value = raw;
  if (raw is String) {
    try {
      value = jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }
  if (value is! List) return null;
  final result = <String>[];
  for (final item in value) {
    if (item is! String) return null;
    result.add(item);
  }
  return result;
}

/// Разбор массива блоков статьи (каждый элемент — JSON-объект).
/// Возвращает `null`, если значение некорректно.
List<Map<String, Object?>>? parseBlocks(Object? raw) {
  Object? value = raw;
  if (raw is String) {
    try {
      value = jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }
  if (value is! List) return null;
  final result = <Map<String, Object?>>[];
  for (final item in value) {
    if (item is! Map) return null;
    result.add(Map<String, Object?>.from(item));
  }
  return result;
}

/// Разбор булева значения из JSON (`true/false`, `1/0`, строки).
bool? parseBool(Object? raw) {
  if (raw is bool) return raw;
  if (raw is num) return raw != 0;
  if (raw is String) {
    switch (raw.trim().toLowerCase()) {
      case 'true':
      case '1':
        return true;
      case 'false':
      case '0':
        return false;
    }
  }
  return null;
}

/// Разбор положительного целого из query-параметра с ограничением.
int parseLimit(String? raw, {int fallback = 20, int min = 1, int max = 100}) {
  final value = int.tryParse(raw ?? '');
  if (value == null) return fallback;
  return value.clamp(min, max);
}
