import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/constants/app_constants.dart';
import '../core/widgets/empty_state.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/register_screen.dart';
import '../features/auth/screens/splash_screen.dart';
import '../features/auth/session_provider.dart';
import '../features/home/screens/home_screen.dart';
import '../features/playground/screens/playground_screen.dart';
import '../features/profile/screens/profile_screen.dart';
import '../features/reference/screens/favorites_screen.dart';
import '../features/reference/screens/history_screen.dart';
import '../features/reference/screens/reference_screen.dart';
import '../features/reference/screens/category_articles_screen.dart';
import '../features/reference/screens/article_screen.dart';
import '../features/search/screens/search_screen.dart';

/// Чистая функция auth-guard: только (location, AuthState) → маршрут
/// перехода либо null (продолжить навигацию).
///
/// Правила:
/// - authorized → прочь с /login, /register (иначе петля); сплэш не
///   блокируется даже для вошедшего — он гарантированно отыгрывает таймер,
///   затем сам ведёт на /home (context.go в SplashScreen);
/// - guest → прочь с непубличных маршрутов на /login. Новые приватные
///   маршруты (/reference/:categoryId, /article/:id) закрыты автоматически:
///   публичный набор фиксирован.
String? authRedirect(String location, AuthState auth) {
  const public = {
    AppConstants.routeSplash,
    AppConstants.routeLogin,
    AppConstants.routeRegister,
  };

  if (auth.isAuthorized) {
    // Вошедшего не пускаем на логин/регистрацию (иначе петля). Сплэш не
    // блокируем: он гарантированно отыгрывает таймер, затем сам ведёт на
    // /home (см. SplashScreen._goNext).
    const authScreens = {AppConstants.routeLogin, AppConstants.routeRegister};
    return authScreens.contains(location) ? AppConstants.routeHome : null;
  }

  // Гость (или unknown — до восстановления сессии; в приложении сессия
  // восстановлена ещё до runApp): непубличное — на /login, публичное
  // (включая сплэш до истечения таймера) открыто.
  return public.contains(location) ? null : AppConstants.routeLogin;
}

/// Экран 404 (unmatched-маршруты): та же заглушка EmptyState — навигация
/// на заведомо несуществующий адрес не роняет и не путает пользователя.
class _RouteNotFoundScreen extends StatelessWidget {
  const _RouteNotFoundScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Страница не найдена')),
      body: const EmptyState(
        key: Key('route-not-found'),
        title: 'Страница не найдена',
        message: 'Проверьте ссылку или вернитесь на вкладку «Главная».',
        icon: Icons.search_off,
      ),
    );
  }
}

/// Сборка GoRouter: сплэш, логин, регистрация + StatefulShellRoute с 4
/// постоянными вкладками; приватные маршруты — внутри ветка «Справочник».
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
    errorBuilder: (context, state) => const _RouteNotFoundScreen(),
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
          // Ветка «Справочник» + приватные маршруты внутри неё: категории →
          // список статей → статья. Нижняя навигация остаётся видимой.
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppConstants.routeReference,
                builder: (context, state) => const ReferenceScreen(),
                routes: [
                  GoRoute(
                    path: ':categoryId',
                    builder: (context, state) => CategoryArticlesScreen(
                      categoryId: state.pathParameters['categoryId']!,
                    ),
                  ),
                ],
              ),
              // Статья — на уровне ветки, чтобы открываться с любой вкладки
              // (P9 — переход «Продолжить» с главной). Данные — по id.
              GoRoute(
                path: AppConstants.routeArticle,
                builder: (context, state) =>
                    ArticleScreen(articleId: state.pathParameters['id']!),
              ),
              // P8/P9: поиск, избранное и история — тоже на уровне ветки
              // («вкладка-независимые», нижняя навигация остаётся). Все три
              // НЕ в публичном allowlist → закрыты guard'ом автоматически.
              GoRoute(
                path: AppConstants.routeSearch,
                builder: (context, state) => const SearchScreen(),
              ),
              GoRoute(
                path: AppConstants.routeFavorites,
                builder: (context, state) => const FavoritesScreen(),
              ),
              GoRoute(
                path: AppConstants.routeHistory,
                builder: (context, state) => const HistoryScreen(),
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

/// Оболочка вкладок (P5): NavigationBar, русские подписи, иконки для
/// активного/неактивного состояния; goBranch(initialLocation: ...) —
/// повторный тап по активной вкладке возвращает на её корень.
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
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Главная',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: 'Справочник',
          ),
          NavigationDestination(
            icon: Icon(Icons.code_outlined),
            selectedIcon: Icon(Icons.code),
            label: 'Песочница',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Профиль',
          ),
        ],
      ),
    );
  }
}
