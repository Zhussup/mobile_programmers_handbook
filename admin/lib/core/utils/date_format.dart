import 'package:intl/intl.dart';

/// Форматирование дат из API (ISO 8601) для таблиц админ-панели.
String formatDateTime(String value) {
  if (value.isEmpty) return '—';
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value;
  return DateFormat('dd.MM.yyyy HH:mm').format(parsed.toLocal());
}
