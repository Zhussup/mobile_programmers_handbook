/// Валидаторы полей форм (регистрация, авторизация, позже — профиль 2.0).
///
/// Каждая функция возвращает русское сообщение об ошибке либо null
/// (= значение корректно). Используются и формами, и юнит-тестами.
class Validators {
  Validators._();

  /// Допустимые символы имени пользователя: буквы (латиница/кириллица),
  /// цифры и подчёркивание.
  static final RegExp _usernameRegExp = RegExp(r'^[A-Za-zА-Яа-яЁё0-9_]+$');

  /// Упрощённая проверка email: что-то@что-то.домен (без спец-пограничных
  /// случаев RFC); для учебного приложения этого достаточно.
  static final RegExp _emailRegExp = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');

  /// Минимальная длина пароля.
  static const int minPasswordLength = 6;

  /// Границы длины имени пользователя.
  static const int minUsernameLength = 3;
  static const int maxUsernameLength = 20;

  /// Имя пользователя: 3–20 символов, буквы/цифры/«_».
  static String? validateUsername(String? value) {
    final username = value?.trim() ?? '';
    if (username.isEmpty) {
      return 'Введите имя пользователя';
    }
    if (username.length < minUsernameLength) {
      return 'Имя пользователя: минимум $minUsernameLength символа';
    }
    if (username.length > maxUsernameLength) {
      return 'Имя пользователя: максимум $maxUsernameLength символов';
    }
    if (!_usernameRegExp.hasMatch(username)) {
      return 'Имя пользователя может содержать только буквы, цифры и «_»';
    }
    return null;
  }

  /// Email: непустой и похож на адрес.
  static String? validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) {
      return 'Введите email';
    }
    if (!_emailRegExp.hasMatch(email)) {
      return 'Введите корректный email';
    }
    return null;
  }

  /// Пароль: непустой, от [minPasswordLength] символов.
  static String? validatePassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) {
      return 'Введите пароль';
    }
    if (password.length < minPasswordLength) {
      return 'Пароль: минимум $minPasswordLength символов';
    }
    return null;
  }

  /// Повтор пароля: непустой и совпадает с основным паролем.
  static String? validatePasswordConfirm(String? password, String? confirm) {
    final confirmText = confirm ?? '';
    if (confirmText.isEmpty) {
      return 'Повторите пароль';
    }
    if (password != confirmText) {
      return 'Пароли не совпадают';
    }
    return null;
  }

  /// Логин на экране авторизации: непустой (строгость формата не проверяем —
  /// вход возможен и по username, и по email).
  static String? validateLoginOrEmail(String? value) {
    if (value?.trim().isEmpty ?? true) {
      return 'Введите логин или Email';
    }
    return null;
  }
}
