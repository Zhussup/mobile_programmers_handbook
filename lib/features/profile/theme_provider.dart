import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';

/// Провайдер темы: смена ThemeMode + persist в shared_preferences
/// (ключ `session_theme`). Начальное значение загружается в main() ДО runApp.
class ThemeProvider extends ChangeNotifier {
  ThemeProvider({required this.prefs, required ThemeMode initialMode})
    : _mode = initialMode;

  final SharedPreferences prefs;

  ThemeMode _mode;

  /// Текущий режим темы.
  ThemeMode get mode => _mode;

  /// Переключить тему и сохранить выбор.
  void setMode(ThemeMode mode) {
    if (mode == _mode) return;
    _mode = mode;
    // 'system' | 'light' | 'dark'
    prefs.setString(AppConstants.prefSessionTheme, mode.name);
    notifyListeners();
  }

  /// Разбор сохранённого значения ключа `session_theme`.
  static ThemeMode modeFromString(String? value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}
