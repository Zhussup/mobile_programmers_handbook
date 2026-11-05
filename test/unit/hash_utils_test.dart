import 'package:flutter_test/flutter_test.dart';

import 'package:mob_kurs/core/utils/hash_utils.dart';

/// Юнит-тесты хэширования паролей (солёный sha256).
void main() {
  group('generateSalt', () {
    test('соль имеет фиксированную длину (16 байт в hex = 32 символа)', () {
      final salt = HashUtils.generateSalt();
      expect(salt.length, 32);
      expect(salt, matches(RegExp(r'^[0-9a-f]+$')));
    });

    test('каждая соль новая (два вызова дают разные соли)', () {
      final salts = List.generate(8, (_) => HashUtils.generateSalt());
      expect(salts.toSet().length, 8);
    });
  });

  group('hashPassword + verifyPassword', () {
    test('одинаковые пароль и соль дают одинаковый хэш (детерминирован)', () {
      final hash1 = HashUtils.hashPassword('пароль123', 'salt');
      final hash2 = HashUtils.hashPassword('пароль123', 'salt');
      expect(hash1, hash2);
      expect(hash1, hasLength(64)); // sha256 = 64 hex-символа
    });

    test('разные соли дают разные хэши одного пароля', () {
      final hashA = HashUtils.hashPassword('пароль123', 'сол-а');
      final hashB = HashUtils.hashPassword('пароль123', 'сол-б');
      expect(hashA, isNot(hashB));
    });

    test('verify: верный пароль проходит, неверный — нет', () {
      final salt = HashUtils.generateSalt();
      final hash = HashUtils.hashPassword('правильныйПароль', salt);

      expect(HashUtils.verifyPassword('правильныйПароль', salt, hash), isTrue);
      expect(HashUtils.verifyPassword('правильныйПароль', salt, hash), isTrue);
    });

    test('разные пароли не проходят проверку', () {
      final salt = HashUtils.generateSalt();
      // Проверяем пары неверных паролей.
      final wrong = [
        'пароль124',
        'пароль12',
        'ПравильныйПароль',
        ' правильныйПароль',
        'правильныйПароль ',
        '',
      ];
      final hash = HashUtils.hashPassword('правильныйПароль', salt);
      for (final password in wrong) {
        expect(
          HashUtils.verifyPassword(password, salt, hash),
          isFalse,
          reason: 'Пароль "$password" не должен проходить',
        );
      }
    });
  });
}
