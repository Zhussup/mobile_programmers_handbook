import 'package:flutter_test/flutter_test.dart';

import 'package:mob_kurs/core/constants/app_constants.dart';
import 'package:mob_kurs/features/auth/session_provider.dart';
import 'package:mob_kurs/router/app_router.dart';

/// Юнит-тесты чистой функции auth-guard: (location, AuthState) → redirect.
void main() {
  const home = AppConstants.routeHome;
  const login = AppConstants.routeLogin;
  const register = AppConstants.routeRegister;
  const splash = AppConstants.routeSplash;

  group('гость', () {
    test('не может открыть приватные маршруты → /login', () {
      const guest = AuthState.guest();
      expect(authRedirect(home, guest), login);
      expect(authRedirect('/reference', guest), login);
      expect(authRedirect('/article/cpp_stl_vector', guest), login);
      expect(authRedirect('/search', guest), login);
    });

    test('публичные маршруты открыты (сплэш не блокируется до таймера)', () {
      const guest = AuthState.guest();
      expect(authRedirect(splash, guest), isNull);
      expect(authRedirect(login, guest), isNull);
      expect(authRedirect(register, guest), isNull);
    });
  });

  group('вошедший пользователь', () {
    const authorized = AuthState(status: AuthStatus.authorized);
    test('не возвращается на логин/регистрацию → /home', () {
      expect(authRedirect(login, authorized), home);
      expect(authRedirect(register, authorized), home);
    });

    test('сплэш не блокируется до истечения таймера (уход по таймеру)', () {
      expect(authRedirect(splash, authorized), isNull);
    });

    test('приватные маршруты открыты', () {
      expect(authRedirect(home, authorized), isNull);
      expect(authRedirect('/reference', authorized), isNull);
    });
  });

  group('статус unknown (сессия не восстановлена)', () {
    const unknown = AuthState(status: AuthStatus.unknown);
    test('ведёт себя как гость: приватное → /login, публичное открыто', () {
      expect(authRedirect(home, unknown), login);
      expect(authRedirect(splash, unknown), isNull);
    });
  });
}
