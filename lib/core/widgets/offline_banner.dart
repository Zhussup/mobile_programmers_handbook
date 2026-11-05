import 'package:flutter/material.dart';

/// Баннер офлайн-режима (КР_2_2, К11).
///
/// Показывается, когда данные отданы из кэша sqflite из-за сетевой ошибки.
/// [onRetry] добавляет кнопку повторной загрузки (для экранов с загрузкой).
class OfflineBanner extends StatelessWidget {
  /// Баннер с необязательным повтором.
  const OfflineBanner({super.key, this.onRetry});

  /// Единая формулировка из контракта.
  static const String message = 'Нет связи. Показаны сохранённые данные';

  /// Повторить запрос (null — кнопки нет).
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('offline-banner'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off, size: 20, color: scheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12.5,
                color: scheme.onSecondaryContainer,
              ),
            ),
          ),
          if (onRetry != null)
            TextButton(
              key: const Key('offline-retry'),
              onPressed: onRetry,
              child: const Text('Повторить'),
            ),
        ],
      ),
    );
  }
}
