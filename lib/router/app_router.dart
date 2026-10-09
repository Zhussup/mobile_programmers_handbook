import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/constants/app_constants.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/register_screen.dart';
import '../features/auth/screens/splash_screen.dart';
import '../features/auth/session_provider.dart';
import '../features/home/screens/home_screen.dart';
import '../features/playground/screens/playground_screen.dart';
import '../features/profile/screens/profile_screen.dart';
import '../features/reference/screens/reference_screen.dart';

/// Чистая функция auth-guard: только (location, AuthState) → маршрут
/// перехода либо null (продолжить навигацию).
///
/// Правила:
/// - authorized → прочь с /login, /register (иначе петля);
///   сплэш не блокируется даже для вошедшего — он гарантированно отыгрывает
///   таймер, затем сам ведёт на /home (context.go в SplashScreen);
/// - guest → прочь с непубличных маршрутов на /login.
String? authRedirect(String location, AuthState auth) {
  const public = {
    AppConstants.routeSplash,
    AppConstants.routeLogin,
    AppConstants.routeRegister,
  };

  if (auth.isAuthorized) {
    // Вошедшего не пускаем на логин/регистрацию (иначе петля). Сплэш не
    // блокируем: он гарантрованно отыгрывает таймер, затем сам ведёт на
    // /home (см. SplashScreen._goNext).
    const authScreens = {AppConstants.routeLogin, AppConstants.routeRegister};
    return authScreens.contains(location) ? AppConstants.routeHome : null;
  }

  // Гость (или unknown — до восстановления сессии; в приложении сессия
  // восстановлена ещё до runApp): непубличное — на /login, публичное
  // (включая сплэш до истечения таймера) открыто.
  return public.contains(location) ? null : AppConstants.routeLogin;
}

/// Сборка GoRouter: сплэш, логин, регистрация + StatefulShellRoute с 4
/// постоянными вкладками.
///
/// [session] — сессия для auth-guard; [initialLocation] — параметр для
/// виджет-тестов (в приложении — /splash). refreshListenable не нужен:
/// сессия инициализируется до runApp, а переходы auth-экранов выполняются
/// явным context.go() после register/login/logout.
GoRouter buildAppRouter(SessionProvider session, {String? initialLocation}) {
  return GoRouter(
    initialLocation: initialLocation ?? AppConstants.routeSplash,
    redirect: (context, state) =>
        authRedirect(state.matchedLocation, session.state),
    routes: [
      GoRoute(
        path: AppConstants.routeSplash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppConstants.routeLogin,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppConstants.routeRegister,
        builder: (context, state) => const RegisterScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => _ShellScaffold(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppConstants.routeHome,
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppConstants.routeReference,
                builder: (context, state) => const ReferenceScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppConstants.routePlayground,
                builder: (context, state) => const PlaygroundScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppConstants.routeProfile,
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

/// Оболочка вкладок: NavigationBar (нижняя навигация).
/// Оформление и поведение вкладок будет доведено до финала в P5.
class _ShellScaffold extends StatelessWidget {
  const _ShellScaffold({required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (index) =>
            shell.goBranch(index, initialLocation: index == shell.currentIndex),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Главная',
          ),
          const NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: 'Справочник',
          ),
          const NavigationDestination(
            icon: Icon(Icons.code_outlined),
            selectedIcon: Icon(Icons.code),
            label: 'Песочница',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Профиль',
          ),
        ],
      ),
    );
  }
}
