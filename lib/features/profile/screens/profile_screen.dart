import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../auth/session_provider.dart';
import '../theme_provider.dart';

/// Раздел «Профиль» (вкладка) — версия 1 (P4).
///
/// Карточка пользователя (аватар-цвет, имя, email, дата регистрации),
/// переключатель темы (фаза P5 переоформит) и кнопка «Выйти» с
/// диалогом подтверждения: logout + context.go('/login').
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  /// Диалог подтверждения выхода.
  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Выйти из аккаунта?'),
        content: const Text(
          'Вы вернётесь на экран авторизации. Данные приложения на '
          'устройстве сохранятся.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            key: const Key('logout-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    // 1. Выход: очистка сессии (prefs), данные в БД не удаляются.
    await context.read<SessionProvider>().logout();

    // 2. Замена стека на /login — доступ к закрытым разделам снова
    //    требует авторизации (auth-guard).
    if (context.mounted) {
      context.go(AppConstants.routeLogin);
    }
  }

  /// Разбор hex-цвета аватара (#RRGGBB → Color).
  static Color _avatarColor(String hex) {
    final digits = hex.replaceFirst('#', '');
    return Color(int.parse(digits, radix: 16) | 0xFF000000);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final user = session.currentUser;

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Профиль')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // --- Карточка пользователя ---
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: _avatarColor(
                      user?.avatarColor ?? '#2AA79B',
                    ),
                    child: Text(
                      user?.avatarLetter ?? '?',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          user?.username ?? 'Гость',
                          style: theme.textTheme.titleLarge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          user?.email ?? '',
                          style: theme.textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (user != null)
                          Text(
                            'Дата регистрации: '
                            '${DateFormat('dd.MM.yyyy').format(user.createdAt)}',
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // --- Тема оформления (persist в prefs, P5 переоформит) ---
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Тема оформления', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 12),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text('Системная'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        label: Text('Светлая'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        label: Text('Тёмная'),
                      ),
                    ],
                    selected: {themeProvider.mode},
                    onSelectionChanged: (selection) {
                      themeProvider.setMode(selection.first);
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // --- Кнопка «Выйти» с диалогом подтверждения ---
          FilledButton.icon(
            key: const Key('logout-button'),
            onPressed: () => _confirmLogout(context),
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            icon: const Icon(Icons.logout),
            label: const Text('Выйти'),
          ),
        ],
      ),
    );
  }
}
