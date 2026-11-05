/// Конфигурация мобильного приложения (КР_2_2).
///
/// Адрес backend задаётся константой сборки `API_BASE_URL`:
/// `flutter run --dart-define=API_BASE_URL=http://192.168.0.10:8080/api`.
/// Значение по умолчанию `http://10.0.2.2:8080/api` — это localhost
/// компьютера из эмулятора Android.
class AppConfig {
  AppConfig._();

  /// Базовый URL API вместе с префиксом `/api`.
  ///
  /// Для физического устройства передайте IP компьютера через
  /// `--dart-define=API_BASE_URL=...` (эмулятор видит хост как 10.0.2.2).
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8080/api',
  );

  /// Использовать удалённые репозитории (API) вместо локальных.
  ///
  /// В `main()` включён (backend — источник истины), в тестах и
  /// офлайн-демонстрации может быть выключен явно: тогда приложение
  /// работает на локальных репозиториях и JSON-ассетах, как раньше.
  static bool useApi = true;

  /// Таймаут одного HTTP-запроса (по контракту — 10 секунд).
  static const Duration apiTimeout = Duration(seconds: 10);
}
