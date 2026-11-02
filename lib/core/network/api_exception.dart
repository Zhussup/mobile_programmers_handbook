import 'package:flutter/foundation.dart' show immutable;

/// Тип сетевой/серверной ошибки (контракт КР_2_2, раздел 5.6).
enum ApiErrorType {
  /// Сервер недоступен, нет маршрута до него (SocketException/ClientException).
  network,

  /// Сервер не ответил за отведённый таймаут.
  timeout,

  /// 401 — токен отсутствует, просрочен или отозван.
  unauthorized,

  /// 403 — недостаточно прав либо пользователь заблокирован.
  forbidden,

  /// 404 — объект не найден (в т.ч. статья снята с публикации).
  notFound,

  /// 409 — занятые username/email или дубликат.
  conflict,

  /// 400 — ошибки валидации полей формы.
  validation,

  /// 5xx — внутренняя ошибка сервера.
  server,

  /// Ответ не является корректным JSON ожидаемой структуры.
  parse,
}

/// Единое исключение сетевого слоя.
///
/// Содержит машинный [code] (из `{"error":{"code":...}}`), русское
/// [message], HTTP-статус и карту ошибок полей для inline-вывода на формах.
@immutable
class ApiException implements Exception {
  /// Создание исключения с явными полями.
  const ApiException({
    required this.type,
    required this.code,
    required this.message,
    this.statusCode,
    this.fields = const {},
  });

  /// Нет соединения с сервером.
  factory ApiException.network() => const ApiException(
    type: ApiErrorType.network,
    code: 'network',
    message: 'Нет подключения к интернету. Проверьте сеть.',
  );

  /// Таймаут запроса.
  factory ApiException.timeout() => const ApiException(
    type: ApiErrorType.timeout,
    code: 'timeout',
    message: 'Сервер не отвечает. Попробуйте ещё раз.',
  );

  /// Некорректный ответ сервера.
  factory ApiException.parse() => const ApiException(
    type: ApiErrorType.parse,
    code: 'parse_error',
    message: 'Некорректный ответ сервера.',
  );

  /// Разбор ошибки `{"error": {"code":..., "message":..., "fields":...}}`.
  ///
  /// [error] — уже декодированное поле `error` (или весь JSON, если обёртки
  /// нет). Неизвестная структура не роняет клиент: остаётся тип по статусу.
  factory ApiException.fromResponse(int status, Object? error) {
    var code = _statusCode(status);
    var message = _defaultMessage(status);
    var fields = const <String, String>{};

    if (error is Map) {
      final rawCode = error['code'];
      if (rawCode is String && rawCode.isNotEmpty) code = rawCode;
      final rawMessage = error['message'];
      if (rawMessage is String && rawMessage.isNotEmpty) message = rawMessage;
      final rawFields = error['fields'];
      if (rawFields is Map) {
        fields = {
          for (final entry in rawFields.entries)
            if (entry.key is String && entry.value is String)
              entry.key as String: entry.value as String,
        };
      }
    }

    return ApiException(
      type: _typeOf(status, code),
      code: code,
      message: message,
      statusCode: status,
      fields: fields,
    );
  }

  /// Категория ошибки.
  final ApiErrorType type;

  /// Машинный код (`validation_error`, `user_blocked`, `network`, …).
  final String code;

  /// Русское сообщение для пользователя (или серверное, если пришло).
  final String message;

  /// HTTP-статус (null для сетевых сбоев без ответа).
  final int? statusCode;

  /// Ошибки конкретных полей формы (`email`, `password`, …).
  final Map<String, String> fields;

  /// Сбой связи/таймаут — можно показать кэш и предложить повтор.
  bool get isNetwork =>
      type == ApiErrorType.network || type == ApiErrorType.timeout;

  /// Пользователь заблокирован администратором (403 + `user_blocked`).
  bool get isUserBlocked => code == 'user_blocked';

  /// Сессия недействительна (нужен выход на `/login`).
  bool get isUnauthorized => type == ApiErrorType.unauthorized;

  /// Тип по HTTP-статусу и машинному коду ошибки.
  static ApiErrorType _typeOf(int status, String code) {
    if (code == 'user_blocked') return ApiErrorType.forbidden;
    switch (status) {
      case 400:
        return ApiErrorType.validation;
      case 401:
        return ApiErrorType.unauthorized;
      case 403:
        return ApiErrorType.forbidden;
      case 404:
        return ApiErrorType.notFound;
      case 409:
        return ApiErrorType.conflict;
    }
    if (status >= 500) return ApiErrorType.server;
    return ApiErrorType.server;
  }

  /// Код по умолчанию для HTTP-статуса (если сервер не прислал свой).
  static String _statusCode(int status) => switch (status) {
    400 => 'validation_error',
    401 => 'unauthorized',
    403 => 'forbidden',
    404 => 'not_found',
    409 => 'conflict',
    >= 500 => 'internal_error',
    _ => 'http_$status',
  };

  /// Русское сообщение по HTTP-статусу.
  static String _defaultMessage(int status) => switch (status) {
    400 => 'Проверьте правильность заполнения полей.',
    401 => 'Сессия истекла. Войдите снова.',
    403 => 'Недостаточно прав для этого действия.',
    404 => 'Запрашиваемые данные не найдены.',
    409 => 'Данные уже существуют.',
    >= 500 => 'Ошибка на сервере. Попробуйте позже.',
    _ => 'Не удалось выполнить запрос.',
  };

  @override
  String toString() => 'ApiException($code, status: $statusCode): $message';
}
