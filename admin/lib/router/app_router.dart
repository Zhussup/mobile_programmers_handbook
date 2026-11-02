import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/network/api_client.dart';
import '../features/articles/article_edit_screen.dart';
import '../features/articles/articles_provider.dart';
import '../features/articles/articles_screen.dart';
import '../features/auth/auth_provider.dart';
import '../features/auth/login_screen.dart';
import '../features/dashboard/dashboard_provider.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/shell/admin_shell.dart';
import '../features/users/users_provider.dart';
import '../features/users/users_screen.dart';

/// Маршрутизация панели.
///
/// Закрытые маршруты доступны только после входа; при 401 провайдер
/// авторизации уведомляет роутер, и происходит переход на `/login`.
GoRouter createAdminRouter({
  required ApiClient api,
  required AuthProvider auth,
  String initialLocation = '/login',
}) {
  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: auth,
    redirect: (context, state) {
      final loggedIn = auth.isAuthenticated;
      final onLogin = state.matchedLocation == '/login';
      if (!loggedIn && !onLogin) return '/login';
      if (loggedIn && onLogin) return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            AdminShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            name: 'dashboard',
            builder: (context, state) => ChangeNotifierProvider(
              create: (context) =>
                  DashboardProvider(api: context.read<ApiClient>()),
              child: const DashboardScreen(),
            ),
          ),
          GoRoute(
            path: '/users',
            name: 'users',
            builder: (context, state) => ChangeNotifierProvider(
              create: (context) => UsersProvider(
                api: context.read<ApiClient>(),
                currentUserId: context.read<AuthProvider>().user?.id,
              ),
              child: UsersScreen(auth: context.read<AuthProvider>()),
            ),
          ),
          GoRoute(
            path: '/articles',
            name: 'articles',
            builder: (context, state) => ChangeNotifierProvider(
              create: (context) =>
                  ArticlesProvider(api: context.read<ApiClient>()),
              child: const ArticlesScreen(),
            ),
          ),
          GoRoute(
            path: '/articles/edit/:id',
            name: 'articleEdit',
            builder: (context, state) => ChangeNotifierProvider(
              create: (context) =>
                  ArticlesProvider(api: context.read<ApiClient>()),
              child: ArticleEditScreen(
                articleId: state.pathParameters['id'] ?? 'new',
              ),
            ),
          ),
        ],
      ),
    ],
  );
}
