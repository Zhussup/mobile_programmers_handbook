import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/admin_user.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/date_format.dart';
import '../../core/widgets/app_snackbar.dart';
import '../auth/auth_provider.dart';
import 'user_form_dialog.dart';
import 'users_provider.dart';

/// Экран управления пользователями (`/users`).
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key, this.auth});

  /// Необязателен: нужен, чтобы обновить имя текущего админа после
  /// редактирования собственной учётной записи.
  final AuthProvider? auth;

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<UsersProvider>();
      _searchController.text = provider.query;
      provider.load();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openCreate() async {
    final provider = context.read<UsersProvider>();
    final created = await showDialog<AdminUser>(
      context: context,
      builder: (_) => UserFormDialog(provider: provider),
    );
    if (created != null && mounted) {
      showSuccessSnackBar(context, 'Пользователь «${created.username}» создан');
    }
  }

  Future<void> _openEdit(AdminUser user) async {
    final provider = context.read<UsersProvider>();
    final updated = await showDialog<AdminUser>(
      context: context,
      builder: (_) => UserFormDialog(provider: provider, user: user),
    );
    if (updated != null && mounted) {
      widget.auth?.updateCurrentUser(updated);
      showSuccessSnackBar(context, 'Данные пользователя сохранены');
    }
  }

  Future<void> _changeRole(AdminUser user, String role) async {
    if (user.role == role) return;
    final provider = context.read<UsersProvider>();
    try {
      final updated = await provider.setRole(user, role);
      widget.auth?.updateCurrentUser(updated);
      if (mounted) {
        showSuccessSnackBar(
          context,
          'Роль «${updated.username}»: ${updated.roleLabel}',
        );
      }
    } on ApiException catch (error) {
      if (mounted) showErrorSnackBar(context, apiErrorMessage(error));
    }
  }

  Future<void> _toggleBlock(AdminUser user) async {
    final provider = context.read<UsersProvider>();
    final block = !user.isBlocked;
    if (block) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Заблокировать пользователя?'),
          content: Text(
            'Пользователь «${user.username}» потеряет доступ к мобильному '
            'приложению, его сессии будут завершены.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Заблокировать'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    try {
      final updated = await provider.setBlocked(user, block);
      if (mounted) {
        showSuccessSnackBar(
          context,
          block
              ? 'Пользователь «${updated.username}» заблокирован'
              : 'Пользователь «${updated.username}» разблокирован',
        );
      }
    } on ApiException catch (error) {
      if (mounted) showErrorSnackBar(context, apiErrorMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<UsersProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Пользователи',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(
                    'Всего: ${provider.users.length}',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 320,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Поиск по логину или email',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Очистить',
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              provider.search('');
                              setState(() {});
                            },
                          ),
                  ),
                  onChanged: (value) {
                    provider.search(value);
                    setState(() {});
                  },
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Обновить',
                onPressed: provider.loading ? null : provider.load,
                icon: const Icon(Icons.refresh),
              ),
              FilledButton.icon(
                onPressed: _openCreate,
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Добавить пользователя'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (provider.loading) const LinearProgressIndicator(minHeight: 2),
          if (provider.errorMessage != null)
            _ErrorBanner(
              message: provider.errorMessage!,
              onRetry: provider.load,
            ),
          const SizedBox(height: 8),
          Expanded(
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: provider.users.isEmpty && !provider.loading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('Пользователи не найдены'),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minWidth: constraints.maxWidth,
                              ),
                              child: DataTable(
                                showCheckboxColumn: false,
                                columnSpacing: 24,
                                headingRowColor: WidgetStatePropertyAll(
                                  scheme.surfaceContainerHighest.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                                columns: const [
                                  DataColumn(label: Text('ID')),
                                  DataColumn(label: Text('Логин')),
                                  DataColumn(label: Text('Email')),
                                  DataColumn(label: Text('Роль')),
                                  DataColumn(label: Text('Статус')),
                                  DataColumn(label: Text('Создан')),
                                  DataColumn(label: Text('Действия')),
                                ],
                                rows: provider.users
                                    .map(
                                      (user) => DataRow(
                                        key: ValueKey('user_${user.id}'),
                                        cells: [
                                          DataCell(Text('${user.id}')),
                                          DataCell(Text(user.username)),
                                          DataCell(Text(user.email)),
                                          DataCell(
                                            _RoleChip(
                                              label: user.roleLabel,
                                              isAdmin: user.isAdmin,
                                            ),
                                          ),
                                          DataCell(
                                            _StatusChip(
                                              blocked: user.isBlocked,
                                            ),
                                          ),
                                          DataCell(
                                            Text(
                                              formatDateTime(user.createdAt),
                                            ),
                                          ),
                                          DataCell(
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  tooltip: 'Редактировать',
                                                  icon: const Icon(
                                                    Icons.edit_outlined,
                                                  ),
                                                  onPressed: () =>
                                                      _openEdit(user),
                                                ),
                                                PopupMenuButton<String>(
                                                  tooltip: 'Сменить роль',
                                                  enabled: !provider.isSelf(
                                                    user,
                                                  ),
                                                  icon: const Icon(
                                                    Icons
                                                        .manage_accounts_outlined,
                                                  ),
                                                  onSelected: (role) =>
                                                      _changeRole(user, role),
                                                  itemBuilder: (_) => const [
                                                    PopupMenuItem(
                                                      value: 'admin',
                                                      child: Text(
                                                        'Сделать администратором',
                                                      ),
                                                    ),
                                                    PopupMenuItem(
                                                      value: 'user',
                                                      child: Text(
                                                        'Сделать пользователем',
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                IconButton(
                                                  tooltip: user.isBlocked
                                                      ? 'Разблокировать'
                                                      : 'Заблокировать',
                                                  icon: Icon(
                                                    user.isBlocked
                                                        ? Icons.lock_open
                                                        : Icons.lock_outline,
                                                  ),
                                                  onPressed:
                                                      provider.isSelf(user)
                                                      ? null
                                                      : () =>
                                                            _toggleBlock(user),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.label, required this.isAdmin});

  final String label;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isAdmin
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: isAdmin ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.blocked});

  final bool blocked;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = blocked ? scheme.error : const Color(0xFF2E7D32);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        blocked ? 'Заблокирован' : 'Активен',
        style: TextStyle(fontSize: 12, color: color),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
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
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Повторить')),
        ],
      ),
    );
  }
}
