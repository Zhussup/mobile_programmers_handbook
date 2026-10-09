import 'package:flutter/material.dart';

/// Раздел «Песочница» (вкладка) — минимальная заглушка (P0/P1).
/// Список/редактор сниппетов с CRUD — фаза P10.
class PlaygroundScreen extends StatelessWidget {
  const PlaygroundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Песочница')),
      body: const Center(child: Text('Песочница кода появится в P10')),
    );
  }
}
