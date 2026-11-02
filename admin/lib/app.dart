import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/network/api_client.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/auth_provider.dart';
import 'router/app_router.dart';

/// Корневое приложение админ-панели.
class AdminApp extends StatefulWidget {
  const AdminApp({
    super.key,
    required this.api,
    required this.auth,
    this.initialLocation = '/login',
  });

  final ApiClient api;
  final AuthProvider auth;
  final String initialLocation;

  @override
  State<AdminApp> createState() => _AdminAppState();
}

class _AdminAppState extends State<AdminApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = createAdminRouter(
      api: widget.api,
      auth: widget.auth,
      initialLocation: widget.initialLocation,
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: widget.api),
        ChangeNotifierProvider<AuthProvider>.value(value: widget.auth),
      ],
      child: MaterialApp.router(
        title: 'Админ-панель — ПМ07',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        routerConfig: _router,
      ),
    );
  }
}
