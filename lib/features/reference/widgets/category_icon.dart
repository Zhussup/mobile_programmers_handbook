import 'package:flutter/material.dart';

import '../article_model.dart';

/// Расшифровка имени иконки категории (Material Icons) в [IconData].
///
/// Разрешённый набор — README контента; неизвестное имя → запасная иконка.
extension ReferenceCategoryUi on ReferenceCategory {
  IconData get iconData => switch (icon) {
    'terminal' => Icons.terminal,
    'layers' => Icons.layers,
    'storage' => Icons.storage,
    'sort' => Icons.sort,
    'school' => Icons.school,
    'grid_view' => Icons.grid_view,
    'memory' => Icons.memory,
    'code' => Icons.code,
    _ => Icons.menu_book,
  };
}