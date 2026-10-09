import 'package:flutter/material.dart';

import '../article_model.dart';

/// Бейдж сложности статьи (Базовый/Средний/Продвинутый) с цветами темы —
/// работает и в светлой, и в тёмной теме (Container-цвета ColorScheme).
class DifficultyBadge extends StatelessWidget {
  const DifficultyBadge({super.key, required this.difficulty});

  final Difficulty difficulty;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (container: background, text: foreground) = switch (difficulty) {
      Difficulty.beginner => (
        container: scheme.primaryContainer,
        text: scheme.onPrimaryContainer,
      ),
      Difficulty.intermediate => (
        container: scheme.secondaryContainer,
        text: scheme.onSecondaryContainer,
      ),
      Difficulty.advanced => (
        container: scheme.errorContainer,
        text: scheme.onErrorContainer,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        difficulty.label,
        style: TextStyle(fontSize: 11, color: foreground, height: 1.0),
      ),
    );
  }
}