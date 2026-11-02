import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import 'dashboard_provider.dart';

/// Главный экран со сводкой (`/dashboard`).
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<DashboardProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();
    final stats = provider.stats;
    final scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Панель управления',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              IconButton.filledTonal(
                tooltip: 'Обновить',
                onPressed: provider.loading ? null : provider.load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Сводка по данным backend: ${AppConfig.apiBaseUrl}',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          if (provider.loading) const LinearProgressIndicator(minHeight: 2),
          if (provider.errorMessage != null)
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: scheme.onErrorContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      provider.errorMessage!,
                      style: TextStyle(color: scheme.onErrorContainer),
                    ),
                  ),
                  TextButton(
                    onPressed: provider.load,
                    child: const Text('Повторить'),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _StatCard(
                icon: Icons.people_outline,
                label: 'Пользователи',
                value: '${stats.users}',
                hint: 'Администраторов: ${stats.admins}',
              ),
              _StatCard(
                icon: Icons.article_outlined,
                label: 'Статьи',
                value: '${stats.articles}',
                hint: 'Черновиков: ${stats.drafts}',
              ),
              _StatCard(
                icon: Icons.public,
                label: 'Опубликовано',
                value: '${stats.published}',
                hint: 'Доступно в мобильном приложении',
              ),
            ],
          ),
          const SizedBox(height: 28),
          Text(
            'Быстрые действия',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton.icon(
                onPressed: () => context.go('/users'),
                icon: const Icon(Icons.people_outline),
                label: const Text('Управление пользователями'),
              ),
              OutlinedButton.icon(
                onPressed: () => context.go('/articles'),
                icon: const Icon(Icons.article_outlined),
                label: const Text('Управление статьями'),
              ),
              OutlinedButton.icon(
                onPressed: () => context.go('/articles/edit/new'),
                icon: const Icon(Icons.add),
                label: const Text('Создать статью'),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Как это работает',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Админ-панель работает через REST API backend (Bearer-токен). '
                    'Изменения контента и пользователей сразу отражаются в '
                    'мобильном приложении после обновления данных.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.hint,
  });

  final IconData icon;
  final String label;
  final String value;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 260,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                hint,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
