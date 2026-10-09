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

  /// Поиск (P8) и избранное/история (P9) — НЕ в публичном allowlist,
  /// поэтому под auth-guard'ом автоматически (см. authRedirect).
  static const String routeSearch = '/search';
  static const String routeFavorites = '/favorites';
  static const String routeHistory = '/history';

  // --- Редактор сниппетов (P10) ---
  /// Редактор в режиме создания (подстраница ветки «Песочница»).
  static const String routeSnippetNew = '/playground/new';

  /// Редактор в режиме редактирования `/playground/edit/:id` (шаблон).
  static const String routeSnippetEdit = '/playground/edit/:id';

  /// Путь к редактору сниппета: данные достаются по id ИЗ ПРОВАЙДЕРА
  /// (подводный камень №8 — в маршруте только id).
  static String snippetEditPath(int snippetId) => '/playground/edit/$snippetId';

  // --- Профиль 2.0 (P11) ---
  /// Экран редактирования профиля (приватный для гостя — как все, кроме
  /// публичного allowlist).
  static const String routeProfileEdit = '/profile/edit';

  // --- Палитра аватара (P11, экран редактирования профиля) ---
  /// Фиксированные цвета аватара: hex-строки '#RRGGBB'. Первые два —
  /// фирменные (бирюзовый/синий), остальные — спокойные добавленные.
  /// AuthRepository выбирает начальный цвет детерминированно из неё же.
  static const List<String> avatarPalette = [
    '#2AA79B', // фирменный бирюзовый
    '#4D8BF5', // синий
    '#E0A83F', // янтарный
    '#D16A8A', // розовый
    '#8C6FF0', // фиолетовый
    '#5FA85D', // зелёный
    '#4BA6C7', // голубой
    '#C75B4A', // терракотовый
  ];

  /// Путь к списку статей категории: `/reference/<categoryId>`.
  static String categoryPath(String categoryId) => '/reference/$categoryId';

  /// Путь к статье: `/article/<articleId>`.
  static String articlePath(String articleId) => '/article/$articleId';

  /// Лимит истории просмотров (топ-N, план: индекс user_id + viewed_at).
  static const int historyLimit = 20;

  /// Сколько недавних статей показывать в секции «Продолжить» на главной.
  static const int homeRecentLimit = 5;

  /// Длительность показа сплэш-экрана.
  static const Duration splashDuration = Duration(milliseconds: 1500);
}
