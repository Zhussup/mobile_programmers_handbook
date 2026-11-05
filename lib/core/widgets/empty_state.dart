import 'package:flutter/material.dart';

/// Единая заглушка «ничего не найдено» (P6, пригодится P8/P9):
/// пустые списки, неизвестная категория/статья, маршрут не найден.
///
/// Использование: обернуть в Center на экране с ограниченной высотой; в
/// ListView — даёт компактную плашку (ширина — по ширине списка).
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
  });

  /// Заголовок заглушки.
  final String title;

  /// Пояснение (необязательно).
  final String? message;

  /// Иконка (по умолчанию — «пусто»).
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 26, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
