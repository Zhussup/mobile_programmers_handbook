import 'package:flutter_test/flutter_test.dart';

import 'package:mob_kurs/core/utils/validators.dart';

/// Юнит-тесты валидаторов форм: пустые/кривые поля, пароли не совпадают.
void main() {
  group('validateUsername', () {
    test('пустое значение → сообщение', () {
      expect(Validators.validateUsername(null), 'Введите имя пользователя');
      expect(Validators.validateUsername(''), 'Введите имя пользователя');
      expect(Validators.validateUsername('   '), 'Введите имя пользователя');
    });

    test('слишком короткое/длинное имя', () {
      expect(Validators.validateUsername('ab'), isNotNull);
      expect(Validators.validateUsername('a' * 21), isNotNull);
    });

    test('недопустимые символы', () {
      expect(Validators.validateUsername('user.name'), isNotNull);
      expect(Validators.validateUsername('user name'), isNotNull);
      expect(Validators.validateUsername('user!'), isNotNull);
    });

    test('корректные имена (латиница, кириллица, цифры, _)', () {
      expect(Validators.validateUsername('user1'), isNull);
      expect(Validators.validateUsername('Иван_Петров'), isNull);
      expect(Validators.validateUsername('dev_42'), isNull);
    });
  });

  group('validateEmail', () {
    test('пустое значение → сообщение', () {
      expect(Validators.validateEmail(null), 'Введите email');
      expect(Validators.validateEmail(''), 'Введите email');
    });

    test('кривые email' , () {
      expect(Validators.validateEmail('нет-собаки'), isNotNull);
      expect(Validators.validateEmail('две@собаки@ру'), isNotNull);
      expect(Validators.validateEmail('без@домена'), isNotNull);
      expect(Validators.validateEmail('@example.com'), isNotNull);
    });

    test('корректные email', () {
      expect(Validators.validateEmail('user@example.com'), isNull);
      expect(Validators.validateEmail('иван@почта.ру'), isNull);
    });
  });

  group('validatePassword', () {
    test('пустое значение → сообщение', () {
      expect(Validators.validatePassword(null), 'Введите пароль');
      expect(Validators.validatePassword(''), 'Введите пароль');
    });

    test('слишком короткий пароль', () {
      expect(Validators.validatePassword('12345'), isNotNull);
    });

    test('корректный пароль', () {
      expect(Validators.validatePassword('123456'), isNull);
      expect(Validators.validatePassword('Пароль!123'), isNull);
    });
  });

  group('validatePasswordConfirm', () {
    test('пустой повтор → сообщение', () {
      expect(
        Validators.validatePasswordConfirm('123456', null),
        'Повторите пароль',
      );
      expect(
        Validators.validatePasswordConfirm('123456', ''),
        'Повторите пароль',
      );
    });

    test('пароли не совпадают', () {
      expect(
        Validators.validatePasswordConfirm('123456', '1234567'),
        'Пароли не совпадают',
      );
      expect(
        Validators.validatePasswordConfirm('П@роль1', 'п@роль1'),
        'Пароли не совпадают',
      );
    });

    test('совпадающие пароли валидны', () {
      expect(Validators.validatePasswordConfirm('123456', '123456'), isNull);
    });
  });

  group('validateLoginOrEmail', () {
    test('пустое значение → сообщение', () {
      expect(Validators.validateLoginOrEmail(null), 'Введите логин или Email');
      expect(Validators.validateLoginOrEmail(''), 'Введите логин или Email');
      expect(Validators.validateLoginOrEmail('  '), 'Введите логин или Email');
    });

    test('любой непустой логин принимается (email И username)', () {
      expect(Validators.validateLoginOrEmail('user'), isNull);
      expect(Validators.validateLoginOrEmail('user@example.com'), isNull);
    });
  });
}
