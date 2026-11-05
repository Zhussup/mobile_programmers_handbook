import 'dart:math';
import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Генерация соли и хэширование пароля (солёный sha256), проверка пароля.
///
/// Подводный камень №7 из плана: пароль хранится только как солёный sha256;
/// честная формулировка для защиты: «для продакшена bcrypt/argon2».
class HashUtils {
  HashUtils._();

  /// Длина соли в байтах (16 байт = 128 бит энтропии).
  static const int _saltLengthBytes = 16;

  /// Случайная соль, закодированная в hex (32 символа).
  /// Каждый вызов даёт новую соль — поэтому два пользователя с одинаковым
  /// паролем имеют разные хэши.
  static String generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(
      _saltLengthBytes,
      (_) => random.nextInt(256),
    );
    return _bytesToHex(bytes);
  }

  /// Солёный sha256: sha256(пароль + соль) в hex.
  ///
  /// Соль дописывается в конец пароля — способ конкатенации фиксируется
  /// здесь и переиспользуется [verifyPassword].
  static String hashPassword(String password, String salt) {
    final bytes = utf8.encode('$password$salt');
    return sha256.convert(bytes).toString();
  }

  /// Проверка пароля: хэшируем введённый пароль с той же солью и сравниваем
  /// с сохранённым хэшем.
  static bool verifyPassword(
    String password,
    String salt,
    String expectedHash,
  ) {
    return hashPassword(password, salt) == expectedHash;
  }

  /// Массив байт → hex-строка в нижнем регистре.
  static String _bytesToHex(List<int> bytes) {
    const digits = '0123456789abcdef';
    final builder = StringBuffer();
    for (final byte in bytes) {
      builder.write(digits[(byte >> 4) & 0xF]);
      builder.write(digits[byte & 0xF]);
    }
    return builder.toString();
  }
}
