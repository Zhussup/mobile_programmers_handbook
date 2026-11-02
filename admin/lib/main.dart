import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/network/api_client.dart';
import 'features/auth/auth_provider.dart';

/// Точка входа админ-панели.
///
/// Базовый URL задаётся `--dart-define=API_BASE_URL=...`,
/// по умолчанию — `http://localhost:8080/api`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final api = HttpApiClient();
  final auth = AuthProvider(api, prefs);
  await auth.restoreSession();

  runApp(AdminApp(api: api, auth: auth));
}
