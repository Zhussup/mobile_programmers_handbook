import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../session_provider.dart';

/// Сплэш-экран (P1/P4): лого + название, таймер, переход.
///
/// Если сессия восстановлена (пользователь уже входил) — таймер ведёт на
/// /home, иначе — на /login. Auth-guard не блокирует сам сплэш, поэтому
/// экран гарантированно показывается [AppConstants.splashDuration].
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Задержка показа сплэша, затем переход по состоянию сессии.
    _timer = Timer(AppConstants.splashDuration, _goNext);
  }

  void _goNext() {
    if (!mounted) return;
    final session = context.read<SessionProvider>();
    context.go(
      session.state.isAuthorized
          ? AppConstants.routeHome
          : AppConstants.routeLogin,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Фон жёстко совпадает с фоном нативного сплэша — переход «нативный →
    // Flutter-экран» происходит без мигания.
    return Scaffold(
      backgroundColor: BrandColors.background,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.asset(
                  'assets/icons/logo.png',
                  width: 128,
                  height: 128,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                AppConstants.appName,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'C++ и Dart/Flutter с примерами кода',
                style: TextStyle(fontSize: 14, color: Colors.white70),
              ),
              const SizedBox(height: 48),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: BrandColors.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
