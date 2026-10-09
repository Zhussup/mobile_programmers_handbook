import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/empty_state.dart';
import '../article_model.dart';
import '../reference_provider.dart';
import '../widgets/difficulty_badge.dart';

/// Список статей категории `/reference/:categoryId` (P6).
///
/// Категория достаётся по id ИЗ РЕПОЗИТОРИЯ (в маршруте — только id,
/// подводный камень №8 из плана); статьи отсортированы по сложности:
/// простые раньше. Неизвестная категория → экран-заглушка (EmptyState),
/// не падение.
class CategoryArticlesScreen extends StatelessWidget {
  const CategoryArticlesScreen({super.key, required this.categoryId});

  /// Строковый id категории из маршрута.
  final String categoryId;

  @override
  Widget build(BuildContext context) {
    final reference = context.watch<ReferenceProvider>();
    final theme = Theme.of(context);

    // --- Загрузка: спиннер ---
    if (reference.status == ReferenceStatus.loading) {
      return const Scaffold(
        appBar: AppBar(title: Text('Справочник')),
        body: Center(key: Key('reference-loading'), child: CircularProgressIndicator()),
      );
    }

    // --- Неизвестная категория: экран-заглушка (не падение) ---
    final category = reference.categoryById(categoryId);
    if (category == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Справочник')),
        body: EmptyState(
          key: const Key('category-not-found'),
          title: 'Категория не найдена',
          message: 'Проверьте ссылку или вернитесь назад.',
          icon: Icons.search_off,
        ),
      );
    }
