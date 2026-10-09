import 'package:flutter/material.dart';

/// Раздел «Справочник» (вкладка) — минимальная заглушка (P0/P1).
/// Категории → список статей → статья (JSON-блоки, CodeBlock) — фаза P6.
class ReferenceScreen extends StatelessWidget {
  const ReferenceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Справочник')),
      body: const Center(child: Text('Раздел справочника появится в P6')),
    );
  }
}
