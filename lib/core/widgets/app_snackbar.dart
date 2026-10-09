import 'package:flutter/material.dart';

/// Названия сообщений снекбаров (единые формулировки — подводный камень №6
/// из плана: фидбек всегда наблюдаем).
class AppSnackBarMessages {
  AppSnackBarMessages._();

  /// После копирования кода.
  static const String copied = 'Скопировано';

  /// После сохранения (сниппет, настройки и т.п. — P10/P11).
  static const String saved = 'Сохранено';

  /// После удаления (сниппет — P10).
  static const String deleted = 'Удалено';

  /// Избранное (P9): статья добавлена.
  static const String favoriteAdded = 'Добавлено в избранное';

  /// Избранное (P9): статья убрана.
  static const String favoriteRemoved = 'Удалено из избранного';

  /// История (P9): очищена кнопкой «Очистить».
  static const String historyCleared = 'История очищена';

  /// Профиль 2.0 (P11): пароль изменён.
  static const String passwordChanged = 'Пароль изменён';
}

/// Единый SnackBar приложения: базовая версия (message + isError) и
/// предметные хелперы [showCopiedSnackBar] / [showSavedSnackBar] /
/// [showErrorSnackBar].
void showAppSnackBar(
  BuildContext context,
  String message, {
  bool isError = false,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
}

/// Снекбар «Скопировано» (копирование кода — всегда наблюдаемо).
void showCopiedSnackBar(BuildContext context) =>
    showAppSnackBar(context, AppSnackBarMessages.copied);

/// Снекбар «Сохранено» (формы/сниппеты — P10, профиль — P11).
void showSavedSnackBar(BuildContext context) =>
    showAppSnackBar(context, AppSnackBarMessages.saved);

/// Красный снекбар с сообщением об ошибке.
void showErrorSnackBar(BuildContext context, String message) =>
    showAppSnackBar(context, message, isError: true);
