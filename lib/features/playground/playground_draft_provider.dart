import 'package:flutter/foundation.dart';

import 'snippet_model.dart';

/// Черновик «Открыть в песочнице» из статьи (P10): код + язык.
///
/// Зачем провайдер, а не аргументы маршрута: переход выполняется
/// `context.go('/playground')` — на уровень ВКЛАДКИ (замена стека, подводный
/// камень №8 из плана: в extras/аргументах — только id; код статьи — контент,
/// а не id). Черновик живут ДО потребления редактором:
///
/// 1. кнопка в статье: `setDraft(code, language)` + `context.go('/playground')`;
/// 2. экран песочницы (список) замечает черновик и открывает редактор
///    в режиме создания (`/playground/new`);
/// 3. редактор в init-эффекте забирает черновик `consumeDraft()` →
///    открыт режим создания с подставленным кодом.
///
/// Черновик ОДНОРАЗОВЫЙ: `consumeDraft()` очищает его (повторный вызов —
/// null), копия из статьи редактируется независимо от исходной статьи.
class PlaygroundDraftProvider extends ChangeNotifier {
  String? _code;
  SnippetLanguage _language = SnippetLanguage.cpp;

  /// Есть ли неподобранный черновик (список сниппетов откроет редактор).
  bool get hasDraft => _code != null;

  /// Код черновика ('' — черновика нет; читайте после [hasDraft]).
  String get draftCode => _code ?? '';

  /// Язык черновика.
  SnippetLanguage get draftLanguage => _language;

  /// Записать черновик (код статьи + её язык).
  void setDraft({required String code, SnippetLanguage? language}) {
    if (code.trim().isEmpty) return; // пустой код статьи — не копировать
    _code = code;
    if (language != null) _language = language;
    notifyListeners();
  }

  /// Забрать черновик и очистить (повторный вызов — null, черновик ОДНОРАЗОВЫЙ).
  ///
  /// Уведомление слушателей при очистке НЕ посылается: подбор черновика —
  /// не событие для навигации (список реагирует только на ПОЯВЛЕНИЕ
  /// черновика), а лишние notify в момент потребления создают риск
  /// лишней перестройки во время открытого фреймбилда.
  PlaygroundDraft? consumeDraft() {
    final code = _code;
    if (code == null) return null;
    _code = null;
    return PlaygroundDraft(code: code, language: _language);
  }
}

/// Значение черновика (результат [PlaygroundDraftProvider.consumeDraft]).
class PlaygroundDraft {
  const PlaygroundDraft({required this.code, required this.language});

  /// Код из статьи.
  final String code;

  /// Язык из статьи (cpp | dart).
  final SnippetLanguage language;
}