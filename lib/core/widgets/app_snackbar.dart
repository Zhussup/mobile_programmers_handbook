import 'package:flutter/material.dart';

/// Единый SnackBar приложения (скопировано / ошибка / прочий фидбек).
///
/// [isError] — красный вариант для ошибок (логин, регистрация).
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
