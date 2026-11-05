import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../auth_repository.dart';
import '../session_provider.dart';

/// Экран регистрации (P3).
///
/// Форма: имя пользователя, email, пароль, повтор пароля; валидация на всех
/// полях (ru-сообщения), ошибки уникальности подсвечивают конкретное поле,
/// при успехе — автоматический вход и переход на /home.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  /// Inline-ошибки уникальности (не через validator — приходят после submit).
  String? _usernameError;
  String? _emailError;

  /// Идёт ли отправка формы (кнопка с индикатором).
  bool _submitting = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  /// Отправка формы: валидация → регистрация → автоматический вход.
  Future<void> _submit() async {
    setState(() {
      _usernameError = null;
      _emailError = null;
    });

    // Валидация всех полей через [Validators] (ru-сообщения).
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;

    setState(() => _submitting = true);
    try {
      await context.read<SessionProvider>().register(
        username: _usernameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      context.go(AppConstants.routeHome);
    } on AuthException catch (e) {
      // «Имя пользователя уже занято» / «Email уже зарегистрирован» →
      // подсветка конкретного поля; прочие ошибки — в SnackBar.
      if (!mounted) return;
      switch (e.field) {
        case AuthField.username:
          setState(() => _usernameError = e.message);
        case AuthField.email:
          setState(() => _emailError = e.message);
        case null:
          showAppSnackBar(context, e.message, isError: true);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Регистрация')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.disabled,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                TextFormField(
                  key: const Key('register-username'),
                  controller: _usernameController,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) {
                    if (_usernameError != null) {
                      setState(() => _usernameError = null);
                    }
                  },
                  decoration: InputDecoration(
                    labelText: 'Имя пользователя',
                    prefixIcon: const Icon(Icons.person_outline),
                    errorText: _usernameError,
                  ),
                  validator: Validators.validateUsername,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('register-email'),
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) {
                    if (_emailError != null) {
                      setState(() => _emailError = null);
                    }
                  },
                  decoration: InputDecoration(
                    labelText: 'Email',
                    prefixIcon: const Icon(Icons.alternate_email),
                    errorText: _emailError,
                  ),
                  validator: Validators.validateEmail,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('register-password'),
                  controller: _passwordController,
                  obscureText: true,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Пароль',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  validator: Validators.validatePassword,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('register-confirm'),
                  controller: _confirmController,
                  obscureText: true,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    labelText: 'Повторите пароль',
                    prefixIcon: Icon(Icons.lock_reset_outlined),
                  ),
                  validator: (value) => Validators.validatePasswordConfirm(
                    _passwordController.text,
                    value,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  key: const Key('register-submit'),
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Зарегистрироваться'),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => context.go(AppConstants.routeLogin),
                  child: const Text('Уже есть аккаунт? Войти'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
