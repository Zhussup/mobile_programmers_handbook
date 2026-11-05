/// Типы ошибок API, единые для всех экранов админ-панели.
enum ApiErrorKind {
  network,
  timeout,
  unauthorized,
  forbidden,
  notFound,
  conflict,
  validation,
  server,
  parse,
}

/// Исключение API: код, понятное пользователю сообщение и ошибки полей.
class ApiException implements Exception {
  const ApiException({
    required this.kind,
    required this.message,
    this.statusCode,
    this.code,
    this.fields = const <String, String>{},
  });

  final ApiErrorKind kind;
  final String message;
  final int? statusCode;

  /// Код из `{"error":{"code":...}}`, например `validation_error`.
  final String? code;

  /// Ошибки конкретных полей из `{"error":{"fields":{...}}}`.
  final Map<String, String> fields;

  /// Первое сообщение по полю — для подсказки в форме.
  String? get firstFieldError => fields.isEmpty ? null : fields.values.first;

  factory ApiException.network() => const ApiException(
    kind: ApiErrorKind.network,
    message: 'Нет связи с сервером. Проверьте, что backend запущен, и повторите попытку.',
  );

  factory ApiException.timeout() => const ApiException(
    kind: ApiErrorKind.timeout,
    message: 'Сервер не отвечает. Повторите попытку позже.',
  );

  factory ApiException.parse() => const ApiException(
    kind: ApiErrorKind.parse,
    message: 'Некорректный ответ сервера.',
  );

  /// Собирает исключение из HTTP-ответа с телом `{"error": {...}}`.
  factory ApiException.fromResponse(int statusCode, dynamic body) {
    final bodyMap = body is Map ? body : const <String, dynamic>{};
    final rawError = bodyMap['error'];

    String? code;
    String? message;
    final fields = <String, String>{};

    if (rawError is Map) {
      code = rawError['code']?.toString();
      message = rawError['message']?.toString();
      final rawFields = rawError['fields'];
      if (rawFields is Map) {
        for (final entry in rawFields.entries) {
          final value = entry.value;
          if (value != null && value.toString().isNotEmpty) {
            fields[entry.key.toString()] = value.toString();
          }
        }
      }
    } else if (rawError is String && rawError.isNotEmpty) {
      message = rawError;
    }

    final kind = switch (statusCode) {
      400 => ApiErrorKind.validation,
      401 => ApiErrorKind.unauthorized,
      403 => ApiErrorKind.forbidden,
      404 => ApiErrorKind.notFound,
      409 => ApiErrorKind.conflict,
      >= 500 => ApiErrorKind.server,
      _ => ApiErrorKind.server,
    };

    return ApiException(
      kind: kind,
      message: (message != null && message.isNotEmpty)
          ? message
          : _defaultMessage(kind),
      statusCode: statusCode,
      code: code,
      fields: fields,
    );
  }

  static String _defaultMessage(ApiErrorKind kind) => switch (kind) {
    ApiErrorKind.network => ApiException.network().message,
    ApiErrorKind.timeout => ApiException.timeout().message,
    ApiErrorKind.unauthorized => 'Сессия истекла. Войдите снова.',
    ApiErrorKind.forbidden => 'Недостаточно прав для этого действия.',
    ApiErrorKind.notFound => 'Объект не найден.',
    ApiErrorKind.conflict =>
      'Конфликт данных. Возможно, запись уже существует.',
    ApiErrorKind.validation => 'Проверьте заполнение полей.',
    ApiErrorKind.server => 'Ошибка сервера. Повторите попытку позже.',
    ApiErrorKind.parse => ApiException.parse().message,
  };

  @override
  String toString() => 'ApiException($kind, $statusCode, $message)';
}
