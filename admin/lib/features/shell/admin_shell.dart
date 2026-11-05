import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../auth/auth_provider.dart';

/// Общая оболочка панели: боковая навигация на широких экранах,
/// выдвижное меню — на узких.
class AdminShell extends StatelessWidget {
  const AdminShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  static const _destinations = <_Destination>[
    _Destination(
      path: '/dashboard',
      label: 'Панель управления',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
    ),
    _Destination(
      path: '/users',
      label: 'Пользователи',
      icon: Icons.people_outline,
      selectedIcon: Icons.people,
    ),
    _Destination(
      path: '/articles',
      label: 'Статьи',
      icon: Icons.article_outlined,
      selectedIcon: Icons.article,
    ),
  ];

  int get _selectedIndex {
    if (location.startsWith('/users')) return 1;
    if (location.startsWith('/articles')) return 2;
    return 0;
  }

  String get _title {
    if (location.startsWith('/users')) return 'Пользователи';
    if (location.startsWith('/articles/edit')) return 'Редактирование статьи';
    if (location.startsWith('/articles')) return 'Статьи';
    return 'Панель управления';
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Выйти из панели?'),
        content: const Text('Потребуется повторный вход по логину и паролю.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await auth.logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final extended = MediaQuery.sizeOf(context).width >= 1200;
    final username = auth.user?.username ?? '—';

    final userChip = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Chip(
        avatar: CircleAvatar(
          child: Text(username.isEmpty ? '?' : username[0].toUpperCase()),
        ),
        label: Text(username),
      ),
    );

    final logoutButton = IconButton(
      tooltip: 'Выйти',
      onPressed: () => _confirmLogout(context),
      icon: const Icon(Icons.logout),
    );

    if (wide) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_title),
          actions: [userChip, logoutButton, const SizedBox(width: 8)],
        ),
        body: Row(
          children: [
            NavigationRail(
              extended: extended,
              labelType: extended ? null : NavigationRailLabelType.all,
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) =>
                  context.go(_destinations[index].path),
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Icon(
                  Icons.admin_panel_settings,
                  size: 32,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              destinations: _destinations
                  .map(
                    (destination) => NavigationRailDestination(
                      icon: Icon(destination.icon),
                      selectedIcon: Icon(destination.selectedIcon),
                      label: Text(destination.label),
                    ),
                  )
                  .toList(),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: child),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [logoutButton, const SizedBox(width: 8)],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.admin_panel_settings,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Админ-панель',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),
              ..._destinations.map(
                (destination) => ListTile(
                  leading: Icon(destination.icon),
                  title: Text(destination.label),
                  selected:
                      _selectedIndex == _destinations.indexOf(destination),
                  onTap: () {
                    Navigator.of(context).pop();
                    context.go(destination.path);
                  },
                ),
              ),
              const Divider(),
              ListTile(
                leading: CircleAvatar(
                  child: Text(
                    username.isEmpty ? '?' : username[0].toUpperCase(),
                  ),
                ),
                title: Text(username),
                subtitle: const Text('Администратор'),
              ),
            ],
          ),
        ),
      ),
      body: child,
    );
  }
}

class _Destination {
  const _Destination({
    required this.path,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
