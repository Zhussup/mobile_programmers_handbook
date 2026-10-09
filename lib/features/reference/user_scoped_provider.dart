import 'package:flutter/foundation.dart';

import '../auth/session_provider.dart';

/// База провайдеров, привязанных к вошедшему пользователю (P9): подписка
/// на [SessionProvider]; смена пользователя (вход/выход/регистрация) →
/// перезагрузка/выгрузка данных.
///
/// Как работает user-scoping:
/// - все запросы репозиториев — с `WHERE user_id = ?` (изоляция в БД);
/// - провайдер держит `currentUserId` и при любом notify сессии сравнивает
///   его с уже загруженным: другой id — полная перезагрузка; гость —
///   очистка состояния, «чужие» данные никогда не попадают на экран;
/// - устаревшие ответы БД (пользователь сменился во время запроса)
///   отбрасываются по счётчику операций ([beginLoad]/[isActual]).
abstract class UserScopedProvider extends ChangeNotifier {
  /// Провайдер поверх репозитория + подписка на [SessionProvider].
  UserScopedProvider(this._session) {
    _session.addListener(_onSessionChanged);
  }

  /// Сессия (пользователь — источник user-scoping'а).
  final SessionProvider _session;

  /// Счётчик операций загрузки (устаревшие ответы отбрасываются).
  int _generation = 0;

  /// Id вошедшего пользователя (null — гость).
  int? get currentUserId => _session.currentUser?.id;

  /// Актуальна ли операция с меткой [token] (пользователь не сменился).
  bool isActual(int token) => token == _generation;

  /// Присвоить метку новой операции загрузки.
  int beginLoad() => ++_generation;

  /// (Re)загрузка данных текущего пользователя (null → пустое состояние).
  ///
  /// Вызывается автоматически при смене пользователя; можно вызвать и
  /// вручную (например, для принудительного обновления списка).
  Future<void> reload() async {
    final token = beginLoad();
    await loadForUser(currentUserId, token);
    // За время запроса пользователь сменился — данные уже перезагрузит
    // актуальная операция; не перетираем их устаревшими.
    if (!isActual(token)) return;
    notifyListeners();
  }

  /// Перегрузка данных пользователя (реализация в наследнике).
  ///
  /// [token] — метка актуальности; ответ со старой меткой применять нельзя.
  /// Ошибки БД гасятся внутри (не ронять приложение — состояние остаётся
  /// прежним/пустым, детали в debug-логе).
  @protected
  Future<void> loadForUser(int? userId, int token);

  /// Реакция на смену пользователя.
  void _onSessionChanged() => reload();

  @override
  void dispose() {
    _session.removeListener(_onSessionChanged);
    super.dispose();
  }
}
