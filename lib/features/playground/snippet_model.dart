import 'package:flutter/foundation.dart' show immutable;

/// Язык сниппета песочницы (P10): столбец `language` таблицы user_snippets.
///
/// Значения совпадают с кодами языков контента статей — один и тот же код
/// и в JSON-контенте, и в сниппетах (README контента: `cpp | dart`).
enum SnippetLanguage { cpp, dart }

extension SnippetLanguageX on SnippetLanguage {
  /// Короткая подпись для чипов и карточек списка.
  String get label => switch (this) {
    SnippetLanguage.cpp => 'C++',
    SnippetLanguage.dart => 'Dart',
  };

  /// Значение столбца БД (совпадает с именем варианта).
  String get raw => name;
}

/// Разбор значения `language` из БД или из контента статьи.
///
/// Defensive: неизвестное значение / некорректный JSON → cpp
/// (текущий основной контент — C++), приложение не падает.
SnippetLanguage snippetLanguageFromRaw(Object? raw) {
  if (raw is String) {
    return SnippetLanguage.values.firstWhere(
      (language) => language.name == raw,
      orElse: () => SnippetLanguage.cpp,
    );
  }
  return SnippetLanguage.cpp;
}

/// Модель сниппета песочницы (строка таблицы `user_snippets`).
///
/// Сниппет всегда принадлежит пользователю ([userId]) — все запросы
/// репозитория идут с `WHERE user_id = ?` (изоляция мультиюзера).
@immutable
class Snippet {
  /// Создание модели по полям строки таблицы.
  const Snippet({
    required this.id,
    required this.userId,
    required this.title,
    required this.language,
    required this.code,
    required this.expectedOutput,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Id записи (PK, AUTOINCREMENT).
  final int id;

  /// Id владельца сниппета.
  final int userId;

  /// Название сниппета (обязательное, формулирует сам пользователь).
  final String title;

  /// Язык подсветки (cpp | dart).
  final SnippetLanguage language;

  /// Исходный код.
  final String code;

  /// Ожидаемый вывод (обязательное только для запускаемых программ —
  /// может быть пустым).
  final String? expectedOutput;

  /// Когда создан (ISO-8601 строкой в БД).
  final DateTime createdAt;

  /// Когда изменён последний раз (ISO-8601 строкой в БД); сортировка списка.
  final DateTime updatedAt;

  /// Первые [count] строк кода — превью на карточке списка.
  List<String> preview({int count = 5}) {
    final lines = code.split('\n');
    // Пустой код — без превью (карточка показывает прочерк).
    if (lines.length == 1 && lines[0].trim().isEmpty) return const [];
    return lines.take(count).toList();
  }

  /// Разбор строки запроса таблицы `user_snippets` в модель.
  factory Snippet.fromMap(Map<String, Object?> map) {
    return Snippet(
      id: map['id']! as int,
      userId: map['user_id']! as int,
      title: map['title']! as String,
      language: snippetLanguageFromRaw(map['language']),
      code: map['code']! as String,
      expectedOutput: map['expected_output'] as String?,
      createdAt: DateTime.parse(map['created_at']! as String),
      updatedAt: DateTime.parse(map['updated_at']! as String),
    );
  }

  /// Модель → карта полей для INSERT/UPDATE (id не входит — его задаёт
  /// AUTOINCREMENT при создании; user_id — владелец сниппета).
  Map<String, Object?> toMap() {
    return {
      'user_id': userId,
      'title': title,
      'language': language.raw,
      'code': code,
      'expected_output': expectedOutput,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Два сниппета равны по полям (для тестов и сравнения состояния).
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Snippet &&
        other.id == id &&
        other.userId == userId &&
        other.title == title &&
        other.language == language &&
        other.code == code &&
        other.expectedOutput == expectedOutput &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    title,
    language,
    code,
    expectedOutput,
    createdAt,
    updatedAt,
  );

  /// Копия с заменой полей (обновление без пересоздания записи).
  Snippet copyWith({
    String? title,
    SnippetLanguage? language,
    String? code,
    String? expectedOutput,
    DateTime? updatedAt,
  }) {
    return Snippet(
      id: id,
      userId: userId,
      title: title ?? this.title,
      language: language ?? this.language,
      code: code ?? this.code,
      expectedOutput: expectedOutput ?? this.expectedOutput,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
