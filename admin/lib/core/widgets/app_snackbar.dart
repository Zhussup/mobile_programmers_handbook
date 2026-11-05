import 'package:flutter/material.dart';

import '../network/api_exception.dart';

/// Показывает снекбар с сообщением об ошибке.
void showErrorSnackBar(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
}

/// Показывает снекбар об успешном действии.
void showSuccessSnackBar(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Сообщение для исключения API: сначала ошибка поля, затем общий текст.
String apiErrorMessage(Object error) {
  if (error is ApiException) {
    return error.firstFieldError ?? error.message;
  }
  return 'Неожиданная ошибка. Повторите попытку.';
}
