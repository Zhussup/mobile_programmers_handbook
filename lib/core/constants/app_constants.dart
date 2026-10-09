/// Глобальные константы приложения: имя, ключи prefs, имена таблиц БД.
class AppConstants {
  AppConstants._();

  /// Название приложения (сплэш, AppBar и т.д.).
  static const String appName = 'Справочник программиста';

  /// Версия/описание для «о приложении» (профиль, P11).
  static const String appSubtitle =
      'Справочник по C++ и Dart/Flutter '
      'с интерактивными примерами кода';

  // --- Ключи shared_preferences (сессия и настройки) ---
  /// Id вошедшего пользователя (сессия).
  static const String prefSessionUserId = 'session_user_id';

  /// Тема оформления: system | light | dark.
  static const String prefSessionTheme = 'session_theme';

  // --- Имена таблиц SQLite (создание — фаза P2) ---
  static const String tableUsers = 'users';
  static const String tableFavorites = 'favorites';
  static const String tableHistory = 'history';
  static const String tableUserSnippets = 'user_snippets';

  // --- Пути маршрутов go_router ---
  static const String routeSplash = '/splash';
  static const String routeLogin = '/login';
  static const String routeRegister = '/register';
  static const String routeHome = '/home';
  static const String routeReference = '/reference';
  static const String routePlayground = '/playground';
  static const String routeProfile = '/profile';

  /// Маршрут статьи `/article/:id` (шаблон роутера).
  ///
  /// Данные статьи/категории всегда достаются по id из репозитория —
  /// в маршруте передаётся только id (подводный камень №8 из плана).
  static const String routeArticle = '/article/:id';

  /// Путь к списку статей категории: `/reference/<categoryId>`.
  static String categoryPath(String categoryId) => '/reference/$categoryId';

  /// Путь к статье: `/article/<articleId>`.
  static String articlePath(String articleId) => '/article/$articleId';

  /// Длительность показа сплэш-экрана.
  static const Duration splashDuration = Duration(milliseconds: 1500);
}
