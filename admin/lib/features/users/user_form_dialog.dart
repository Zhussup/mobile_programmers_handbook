import 'package:flutter/material.dart';

import '../../core/models/admin_user.dart';
import '../../core/network/api_exception.dart';
import 'users_provider.dart';

/// Диалог создания/редактирования пользователя.
///
/// Возвращает `AdminUser` при успешном сохранении, иначе `null`.
class UserFormDialog extends StatefulWidget {
  const UserFormDialog({super.key, required this.provider, this.user});

  final UsersProvider provider;

  /// `null` — создание нового пользователя.
  final AdminUser? user;

  @override
  State<UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<UserFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _usernameController;
  late final TextEditingController _emailController;
  final _passwordController = TextEditingController();
  late String _role;
  bool _saving = false;
  String? _serverError;
  Map<String, String> _fieldErrors = const <String, String>{};

  bool get _isEdit => widget.user != null;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: widget.user?.username);
    _emailController = TextEditingController(text: widget.user?.email);
    _role = widget.user?.role ?? 'user';
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _serverError = null;
      _fieldErrors = const <String, String>{};
    });
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    try {
      final AdminUser result;
      if (_isEdit) {
        result = await widget.provider.updateUser(
          widget.user!,
          username: _usernameController.text,
          email: _emailController.text,
          role: _role,
        );
      } else {
        result = await widget.provider.createUser(
          username: _usernameController.text,
          email: _emailController.text,
          password: _passwordController.text,
          role: _role,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _serverError = error.message;
        _fieldErrors = error.fields;
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _isEdit ? 'Редактирование пользователя' : 'Новый пользователь',
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_serverError != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_serverError!),
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _usernameController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Логин',
                    errorText: _fieldErrors['username'],
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) return 'Введите логин';
                    if (text.length < 3) return 'Минимум 3 символа';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    errorText: _fieldErrors['email'],
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) return 'Введите email';
                    final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                    if (!emailPattern.hasMatch(text)) {
                      return 'Некорректный email';
                    }
                    return null;
                  },
                ),
                if (!_isEdit) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Пароль',
                      errorText: _fieldErrors['password'],
                    ),
                    validator: (value) {
                      if ((value ?? '').length < 6) return 'Минимум 6 символов';
                      return null;
                    },
                  ),
                ],
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: 'Роль'),
                  items: const [
                    DropdownMenuItem(
                      value: 'user',
                      child: Text('Пользователь'),
                    ),
                    DropdownMenuItem(
                      value: 'admin',
                      child: Text('Администратор'),
                    ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value != null) setState(() => _role = value);
                        },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Сохранить'),
        ),
      ],
    );
  }
}
