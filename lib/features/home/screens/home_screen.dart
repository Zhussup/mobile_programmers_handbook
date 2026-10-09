import 'package:flutter/material.dart';

/// Главный экран (вкладка «Главная») — минимальная заглушка (P0/P1).
/// Приветствие, категории, «недавно смотрели» — фаза P5.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Главная')),
      body: const Center(child: Text('Главная страница появится в P5')),
    );
  }
}
