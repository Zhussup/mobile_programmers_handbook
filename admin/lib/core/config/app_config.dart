/// Конфигурация админ-панели.
///
/// Базовый URL API задаётся при сборке/запуске:
/// `flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080/api`.
class AppConfig {
  AppConfig._();

  /// Адрес backend по умолчанию — локальный сервер из контракта.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080/api',
  );

  /// Таймаут одного запроса.
  static const Duration requestTimeout = Duration(seconds: 10);

  /// Ключ токена в shared_preferences.
  static const String tokenKey = 'admin_auth_token';
}
