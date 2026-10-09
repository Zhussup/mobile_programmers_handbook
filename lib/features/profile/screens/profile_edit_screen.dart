import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../auth/session_provider.dart';
import '../profile_repository.dart';

/// Экран редактирования профиля `/profile/edit` (P11): данные аккаунта
/// (username/email — валидация [Validators], ошибки уникальности inline),
/// цвет аватара (8 фиксированных цветов) и смена пароля.
///
/// После успешного сохранения — [SessionProvider.refreshUser]: экраны,
/// читающие currentUser (профиль, приветствие на главной), показывают
/// свежие данные.
class ProfileEditScreen extends StatefulWidget {
  /// Экран редактирования профиля (данные из [SessionProvider.currentUser]).
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _profileFormKey = GlobalKey<FormState>();

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();

  /// Inline-ошибки уникальности (после submit, как в регистрации).
  String? _usernameError;
  String? _emailError;

  /// Выбранный цвет аватара ('#RRGGBB').
  String? _avatarColor;

  /// Идёт ли сохранение профиля/пароля.
  bool _submitting = false;

  // --- Смена пароля (подсекция того же экрана) ---
  final _passwordFormKey = GlobalKey<FormState>();
  final TextEditingController _oldController = TextEditingController();
  final TextEditingController _newController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  String? _oldPasswordError;
  bool _passwordSubmitting = false;

  @override
  void initState() {
    super.initState();
    // currentUser восстановлен ДО runApp — значения доступны синхронно.
    final user = context.read<SessionProvider>().currentUser;
    _usernameController.text = user?.username ?? '';
    _emailController.text = user?.email ?? '';
    _avatarColor = user?.avatarColor;
  }

  void _clearEmailError() {
    if (_emailError != null) setState(() => _emailError = null);
  }

  void _clearUsernameError() {
    if (_usernameError != null) setState(() => _usernameError = null);
  }

  // --- Сохранение профиля (username/email/цвет) ---
  Future<void> _saveProfile() async {
    setState(() {
      _usernameError = null;
      _emailError = null;
    });

    // Валидация формата полей; ошибки уникальности приходят после submit.
    final valid = _profileFormKey.currentState?.validate() ?? false;
    if (!valid) return;

    final user = context.read<SessionProvider>().currentUser;
    if (user == null) return; // гость (приватный маршрут под guard'ом)

    final username = _usernameController.text.trim();
    final email = _emailController.text.trim();
    final dataChanged = username != user.username || email != user.email;
    final colorChanged =
        _avatarColor != null && _avatarColor != user.avatarColor;

    // Нечего сохранять — просто вернуться (без запросов и снекбара).
    if (!dataChanged && !colorChanged) {
      context.pop();
      return;
    }

    setState(() => _submitting = true);
    try {
      final repository = context.read<ProfileRepository>();
      if (dataChanged) {
        // Неизменённые поля передаются null — в запрос не попадают
        // (репозиторий сохраняет их прежними).
        await repository.updateProfile(
          user.id,
          username: username == user.username ? null : username,
          email: email == user.email ? null : email,
        );
      }
      if (colorChanged) {
        await repository.updateAvatarColor(user.id, _avatarColor!);
      }
      if (!mounted) return;

      // P11: сессия хранит currentUser — обновить её, иначе карточка
      // профиля и приветствие на home показывали бы старые данные.
      await context.read<SessionProvider>().refreshUser();
      if (!mounted) return;
      showSavedSnackBar(context);
      context.pop();
    } on ProfileException catch (e) {
      if (!mounted) return;
      switch (e.field) {
        case ProfileField.username:
          setState(() => _usernameError = e.message);
        case ProfileField.email:
          setState(() => _emailError = e.message);
        case ProfileField.oldPassword:
          // В смене профиля поле старого пароля не участвует.
          showAppSnackBar(context, e.message, isError: true);
        case null:
          showAppSnackBar(context, e.message, isError: true);
      }
      return;
    } on Exception {
      if (!mounted) return;
      showErrorSnackBar(context, 'Не удалось сохранить профиль');
      return;
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // --- Смена пароля (подсекция экрана) ---
  Future<void> _savePassword() async {
    setState(() {
      _oldPasswordError = null;
      _passwordSubmitting = true;
    });

    // Валидация формата нового пароля и повтора — [Validators].
    final valid = _passwordFormKey.currentState?.validate() ?? false;
    if (!valid) {
      setState(() => _passwordSubmitting = false);
      return;
    }

    final user = context.read<SessionProvider>().currentUser;
    if (user == null) return;

    try {
      await context.read<ProfileRepository>().changePassword(
        userId: user.id,
        oldPassword: _oldController.text,
        newPassword: _newController.text,
      );
      if (!mounted) return;
      showAppSnackBar(context, AppSnackBarMessages.passwordChanged);
      // Поля очищаются: пароль «израсходован», повторный submit — с новыми.
      _oldController.clear();
      _newController.clear();
      _confirmController.clear();
      return;
    } on ProfileException catch (e) {
      if (!mounted) return;
      if (e.field == ProfileField.oldPassword) {
        // «Неверный старый пароль» — inline на поле.
        setState(() => _oldPasswordError = e.message);
        return;
      }
      showAppSnackBar(context, e.message, isError: true);
      return;
    } on Exception {
      if (!mounted) return;
      showErrorSnackBar(context, 'Не удалось изменить пароль');
      return;
    } finally {
      if (mounted) setState(() => _passwordSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Редактирование профиля')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- Карточка «Данные аккаунта» ---
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _profileFormKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Данные аккаунта',
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          key: const Key('profile-edit-username'),
                          controller: _usernameController,
                          textInputAction: TextInputAction.next,
                          onChanged: (_) => _clearUsernameError(),
                          decoration: InputDecoration(
                            labelText: 'Имя пользователя',
                            prefixIcon: const Icon(Icons.person_outline),
                            errorText: _usernameError,
                          ),
                          validator: Validators.validateUsername,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: const Key('profile-edit-email'),
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.done,
                          onChanged: (_) => _clearEmailError(),
                          decoration: InputDecoration(
                            labelText: 'Email',
                            prefixIcon: const Icon(Icons.alternate_email),
                            errorText: _emailError,
                          ),
                          validator: Validators.validateEmail,
                        ),

                        const SizedBox(height: 16),

                        // --- Цвет аватара: 8 фиксированных цветов ---
                        Text('Цвет аватара', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (
                              var i = 0;
                              i < AppConstants.avatarPalette.length;
                              i++
                            )
                              _AvatarSwatch(
                                colorHex: AppConstants.avatarPalette[i],
                                selected:
                                    _avatarColor ==
                                    AppConstants.avatarPalette[i],
                                onTap: () => setState(
                                  () => _avatarColor =
                                      AppConstants.avatarPalette[i],
                                ),
                              ),
                          ],
                        ),

                        const SizedBox(height: 18),

                        // --- «Сохранить» (данные + цвет одним запросом UI) ---
                        FilledButton(
                          key: const Key('profile-edit-save'),
                          onPressed: _submitting ? null : _saveProfile,
                          child: _submitting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Сохранить'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // --- Карточка «Смена пароля» (отдельная форма) ---
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _passwordFormKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Смена пароля', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 14),
                        TextFormField(
                          key: const Key('profile-password-old'),
                          controller: _oldController,
                          obscureText: true,
                          textInputAction: TextInputAction.next,
                          onChanged: (_) {
                            if (_oldPasswordError != null) {
                              setState(() => _oldPasswordError = null);
                            }
                          },
                          decoration: InputDecoration(
                            labelText: 'Старый пароль',
                            prefixIcon: const Icon(Icons.lock_outline),
                            errorText: _oldPasswordError,
                          ),
                          validator: (value) =>
                              (value == null || value.trim().isEmpty)
                              ? 'Введите старый пароль'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: const Key('profile-password-new'),
                          controller: _newController,
                          obscureText: true,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Новый пароль',
                            prefixIcon: Icon(Icons.lock_reset_outlined),
                          ),
                          validator: Validators.validatePassword,
                        ),
                        const SizedBox(height: 12),

                        TextFormField(
                          key: const Key('profile-password-confirm'),
                          controller: _confirmController,
                          obscureText: true,
                          onFieldSubmitted: (_) => _savePassword(),
                          decoration: const InputDecoration(
                            labelText: 'Повторите новый пароль',
                            prefixIcon: Icon(Icons.lock_reset_outlined),
                          ),
                          validator: (value) =>
                              Validators.validatePasswordConfirm(
                                _newController.text,
                                value,
                              ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          key: const Key('profile-password-save'),
                          onPressed: _passwordSubmitting ? null : _savePassword,
                          child: _passwordSubmitting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Изменить пароль'),
                        ),
                        const SizedBox(height: 4),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Кружок-образец цвета аватара: 40 px, у выбранного — обводка и галочка.
class _AvatarSwatch extends StatelessWidget {
  const _AvatarSwatch({
    required this.colorHex,
    required this.selected,
    required this.onTap,
  });

  /// Цвет свотча — '#RRGGBB'.
  final String colorHex;
  final bool selected;
  final VoidCallback onTap;

  /// Ключ 'profile-color-HEX-BEZ-RESHETKI' в нижнем регистре; палитра
  /// фиксирована, тесты тапают по конкретному цвету.
  Key get swatchKey {
    final hex = colorHex.replaceFirst('#', '').toLowerCase();
    return Key('profile-color-$hex');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      key: swatchKey,
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: _hexToColor(colorHex),
          shape: BoxShape.circle,
          border: Border.all(
            width: selected ? 3 : 1,
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        child: selected
            ? const Icon(Icons.check, size: 18, color: Colors.white)
            : null,
      ),
    );
  }
}

/// Разбор hex-цвета '#RRGGBB' в Color — общая для профиля и свотчей.
Color _hexToColor(String hex) {
  final digits = hex.replaceFirst('#', '');
  return Color(int.parse(digits, radix: 16) | 0xFF000000);
}
