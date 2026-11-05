import 'dart:io' show Directory, File;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mob_kurs/app.dart';
import 'package:mob_kurs/core/constants/app_constants.dart';
import 'package:mob_kurs/core/db/app_database.dart';
import 'package:mob_kurs/core/widgets/app_snackbar.dart'
    show AppSnackBarMessages;
import 'package:mob_kurs/features/auth/auth_repository.dart';
import 'package:mob_kurs/features/auth/session_provider.dart';
import 'package:mob_kurs/features/reference/history_provider.dart';
import 'package:mob_kurs/features/profile/screens/profile_edit_screen.dart';
import 'package:mob_kurs/features/profile/theme_provider.dart';
import 'package:mob_kurs/main.dart' as app;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart'
    show OpenDatabaseOptions, databaseFactory, getDatabasesPath;

/// P7: интеграционный прогон демонстрационного сценария на эмуляторе.
///
/// Запуск (демон снимков должен быть запущен на хосте):
///   flutter test integration_test/demo_scenario_test.dart -d emulator-5554
///
/// Сценарий соответствует «Верификации» плана и чек-листу §2.7:
/// сплэш → регистрация (валидация + корректные данные) → главная →
/// справочник (категория → список → статья с блоками кода, выводом и
/// копированием) → песочница (черновик из статьи, создать/изменить/удалить
/// сниппет с диалогом) → избранное (добавить/убрать/вернуть) → история →
/// главная с «Продолжить» → поиск с фильтром сложности → профиль
/// (данные, статистика, тема, цвет аватара, выход-диалог) → редактирование
/// профиля (занятое имя, неверный старый пароль) → ошибочный вход →
/// повторный вход → «новый запуск» (восстановление сессии — сразу
/// главная) → финальный выход.
///
/// Скриншоты: на контрольных точках тест пишет файл-запрос `<имя>.req` в
/// свою внутреннюю папку `files/shots`; хостовый демон снимает экран
/// эмулятора (adb exec-out screencap -p) и касается `<имя>.done`.
/// Реальный ввод-вывод (SQLite, prefs, буфер обмена) идёт в реальном
/// времени — интеграционная среда не fake-async, паузы честные.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'P7: полный демонстрационный сценарий + скриншоты для отчёта',
    (tester) async {
      final failedShots = <String>[];
      final captured = <String>[];

      // ---------------- Подготовка окружения ----------------
      // Путь к БД приложения на устройстве; папка files/shots — рядом.
      final dbPath = '${await getDatabasesPath()}/${AppDatabase.dbName}';
      final shotsPath = '${Directory(dbPath).parent.parent.path}/files/shots';
      debugPrint('ДИГНОСТИКА: dbPath=$dbPath shotsPath=$shotsPath');

      Future<void> shot(String name) async {
        final ok = await takeShot(tester, shotsPath, name);
        if (ok) {
          captured.add(name);
        } else {
          failedShots.add(name);
        }
      }

      // Идемпотентность повторных прогонов: чистые пользовательские данные.
      await databaseFactory.deleteDatabase(dbPath);
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      await prefs.setString(AppConstants.prefSessionTheme, 'light');

      // Предпосев второй учётной записи (для сценария «занятое имя»,
      // рисунок 2.14): регистрация через репозиторий БЕЗ сессии.
      final seedDb = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: AppDatabase.dbVersion,
          onCreate: AppDatabase.onCreate,
        ),
      );
      await AuthRepository(db: seedDb, prefs: prefs).register(
        username: 'student2',
        email: 'student2@example.com',
        password: 'student2pass',
      );
      await seedDb.close();
      debugPrint('ШАГ 0: окружение готово (БД снесена, student2 засеян)');

      // ---------------- 1. Сплэш ----------------
      // Инициализация как в production: main() делает всё до runApp.
      await app.main();
      await tester.pump();
      // Немедленный снимок: таймер сплэша (1,5 с) уже идёт в реальном
      // времени, нельзя терять ни секунды.
      await shot('2_01_flutter_splash');
      debugPrint('ШАГ 1: сплэш показан');
      await _waitForKey(
        tester,
        'login-field',
        what: 'экран входа после таймера сплэша',
        timeout: const Duration(seconds: 15),
      );

      // ---------------- 2. Регистрация ----------------
      await tester.tap(find.text('Нет аккаунта? Зарегистрироваться'));
      await _settle(tester);
      await _waitForKey(
        tester,
        'register-username',
        what: 'экран регистрации',
      );

      // 2a. Кривые данные → русские сообщения валидации (рисунок 2.2).
      await _enterTextKey(tester, 'register-username', 'ab');
      await _enterTextKey(tester, 'register-email', 'demo@');
      await _enterTextKey(tester, 'register-password', '123');
      await _enterTextKey(tester, 'register-confirm', '456');
      await _tapKey(tester, 'register-submit');
      await _settle(tester);
      expect(find.text('Имя пользователя: минимум 3 символа'), findsOneWidget);
      expect(find.text('Введите корректный email'), findsOneWidget);
      expect(find.text('Пароль: минимум 6 символов'), findsWidgets);
      expect(find.text('Пароли не совпадают'), findsWidgets);
      await shot('2_02_register_errors');
      debugPrint('ШАГ 2.1: валидация регистрации показана (рис. 2.2)');

      // 2b. Корректные данные → регистрация + автологин → главная.
      await _enterTextKey(tester, 'register-username', 'demo_student');
      await _enterTextKey(tester, 'register-email', 'demo@example.com');
      await _enterTextKey(tester, 'register-password', 'demo123');
      await _enterTextKey(tester, 'register-confirm', 'demo123');
      await _tapKey(tester, 'register-submit');
      await _waitForKey(
        tester,
        'home-greeting',
        what: 'главная после регистрации',
        timeout: const Duration(seconds: 20),
      );
      expect(find.text('Привет, demo_student!'), findsOneWidget);
      debugPrint('ШАГ 2.2: регистрация успешна → главная с приветствием');

      // ---------------- 3. Справочник: статья с блоками ----------------
      await _tapTab(tester, 1); // вкладка «Справочник»
      await _waitForKey(
        tester,
        'reference-category-syntax',
        what: 'категории справочника',
        timeout: const Duration(seconds: 15),
      );
      debugPrint('ШАГ 3: вкладка «Справочник» — категории показаны');

      await _tapKey(tester, 'reference-category-syntax');
      await _waitForKey(
        tester,
        'article-card-cpp_syn_hello_world',
        what: 'список статей категории «Синтаксис C++»',
      );
      debugPrint('ШАГ 3.1: список статей категории');

      await _tapKey(tester, 'article-card-cpp_syn_hello_world');
      await _waitForKey(tester, 'article-favorite', what: 'статья открыта');
      debugPrint('ШАГ 3.2: статья «Первая программа» открыта');

      await _scrollToKey(tester, 'code-copy');
      await _settle(tester);
      await shot('2_04_article_blocks');
      debugPrint('ШАГ 3.3: блок кода статьи виден (рис. 2.4)');

      // «Показать вывод» + «Копировать» → снекбар (рисунок 2.5).
      await _tapKey(tester, 'output-toggle');
      await _waitForKey(tester, 'output-text', what: 'вывод раскрыт');
      await _tapKey(tester, 'code-copy');
      await _settle(tester);
      expect(find.text('Скопировано'), findsOneWidget);
      await shot('2_05_output_copied');
      debugPrint('ШАГ 3.4: вывод раскрыт + «Скопировано» (рис. 2.5)');

      // ---------------- 4. Песочница: черновик + CRUD ----------------
      await _tapKey(tester, 'article-open-in-playground');
      await _waitForKey(
        tester,
        'snippet-title',
        what: 'редактор с черновиком из статьи',
        timeout: const Duration(seconds: 15),
      );
      await _settle(tester);
      await shot('2_11_editor_draft');
      debugPrint('ШАГ 4: редактор с черновиком из статьи (рис. 2.11)');

      // 4a. Сохранить черновик как сниппет №1 (create).
      await _enterTextKey(tester, 'snippet-title', 'HelloWorld из статьи');
      await _tapKey(tester, 'snippet-save');
      await _waitForKey(
        tester,
        'playground-fab',
        what: 'список песочницы после сохранения №1',
      );
      // Оседание pop-перехода: уходящий редактор всё ещё держит текст
      // названия — иначе Finder найдёт карточку И редактор (двойное).
      await _settle(tester);
      expect(find.text('HelloWorld из статьи'), findsOneWidget);
      debugPrint('ШАГ 4.1: сниппет №1 создан (CRUD create)');

      // 4b. Создать сниппет №2 вручную (Dart). Снекбар «Сохранено» после
      // сохранения №1 перекрывает FAB — дождаться исчезновения снекбара.
      await _waitGone(tester, find.text(AppSnackBarMessages.saved));
      await _tapKey(tester, 'playground-fab');
      await _waitForKey(tester, 'snippet-title', what: 'редактор нового сниппета');
      await _enterTextKey(tester, 'snippet-title', 'Мой первый Dart');
      await _tapKey(tester, 'snippet-lang-dart');
      await _enterTextKey(
        tester,
        'snippet-code-editor',
        'void main() {\n  print("Привет из Dart!");\n}',
      );
      await _enterTextKey(tester, 'snippet-output', 'Привет из Dart!');
      await _tapKey(tester, 'snippet-save');
      await _waitForKey(
        tester,
        'playground-fab',
        what: 'список со вторым сниппетом',
      );
      debugPrint('ШАГ 4.2: сниппет №2 (Dart) создан');

      // Список с двумя сниппетами (рисунок 2.10).
      expect(find.byKey(const Key('snippet-card-title')).evaluate().length, 2);
      await shot('2_10_playground_list');
      debugPrint('ШАГ 4.3: список песочницы с двумя сниппетами (рис. 2.10)');

      // 4c. ИЗМЕНИТЬ сниппет №1 (CRUD update).
      await _tapByText(tester, 'HelloWorld из статьи');
      await _waitForKey(tester, 'snippet-title', what: 'редактор сниппета №1');
      await _enterTextKey(tester, 'snippet-title', 'HelloWorld из статьи (v2)');
      await _tapKey(tester, 'snippet-save');
      await _waitForKey(
        tester,
        'playground-fab',
        what: 'возврат к списку после правки',
      );
      await _settle(tester); // оседание pop-перехода (дубль названия)
      expect(find.text('HelloWorld из статьи (v2)'), findsOneWidget);
      debugPrint('ШАГ 4.4: сниппет №1 изменён (CRUD update)');

      // 4d. УДАЛИТЬ сниппет №2 (CRUD delete) с диалогом (рисунок 2.12).
      await _tapByText(tester, 'Мой первый Dart');
      await _waitForKey(tester, 'snippet-delete', what: 'редактор сниппета №2');
      await _tapKey(tester, 'snippet-delete');
      await _waitForFinder(
        tester,
        find.text('Удалить сниппет?'),
        'диалог подтверждения удаления',
      );
      await shot('2_12_delete_dialog');
      debugPrint('ШАГ 4.5: диалог удаления показан (рис. 2.12)');

      await _tapKey(tester, 'snippet-delete-confirm');
      await _waitForKey(
        tester,
        'playground-fab',
        what: 'возврат к списку после удаления',
      );
      await _settle(tester); // оседание pop-перехода (дубль названия в поле)
      expect(find.text('Мой первый Dart'), findsNothing);
      debugPrint('ШАГ 4.6: сниппет №2 удалён (CRUD delete)');

      // ------------ 5. Избранное: добавить/убрать/вернуть ------------
      await _tapTab(tester, 1); // из ветки «Песочница» в «Справочник» (корень)
      await _waitForKey(tester, 'reference-category-stl', what: 'корень справочника');
      await _tapKey(tester, 'reference-category-stl');
      await _waitForKey(
        tester,
        'article-card-cpp_stl_vector_deep',
        what: 'список статей STL',
      );
      await _tapKey(tester, 'article-card-cpp_stl_vector_deep');
      await _waitForKey(tester, 'article-favorite', what: 'статья STL открыта');

      // Добавить в избранное (рисунок 2.8а: активное сердце).
      await _tapKey(tester, 'article-favorite');
      await _settle(tester);
      expect(find.text('Добавлено в избранное'), findsOneWidget);
      await shot('2_08_fav_heart');
      debugPrint('ШАГ 5: сердце активно (рис. 2.8а)');

      // Экран «Избранное» (рисунок 2.8б).
      await _tapTab(tester, 1); // из статьи — на корень ветки
      await _tapKey(tester, 'reference-open-favorites');
      await _waitForKey(
        tester,
        'favorites-entry-cpp_stl_vector_deep',
        what: 'экран «Избранное»',
      );
      await _settle(tester);
      await shot('2_08_fav_list');
      debugPrint('ШАГ 5.1: экран «Избранное» с записью (рис. 2.8б)');

      // Убрать из избранного (кнопка на карточке).
      await _tapKey(tester, 'favorite-remove-cpp_stl_vector_deep');
      await _waitForKey(tester, 'favorites-empty', what: 'пустое избранное');
      debugPrint('ШАГ 5.2: избранное убрано (toggle-off)');

      // Вернуть в избранное (для статистики профиля).
      await _tapTab(tester, 1);
      await _tapKey(tester, 'reference-category-stl');
      await _tapKey(tester, 'article-card-cpp_stl_vector_deep');
      await _waitForKey(
        tester,
        'article-favorite',
        what: 'статья STL повторно',
      );
      await _tapKey(tester, 'article-favorite');
      await _settle(tester);
      expect(find.text('Добавлено в избранное'), findsOneWidget);
      debugPrint('ШАГ 5.3: избранное возвращено (toggle-add)');

      // Третья статья в историю (запись при открытии).
      await _tapTab(tester, 1);
      await _tapKey(tester, 'reference-category-algorithms');
      await _tapKey(tester, 'article-card-cpp_alg_loops');
      await _waitForKey(
        tester,
        'article-favorite',
        what: 'статья «Циклы» открыта',
      );
      debugPrint('ШАГ 5.4: третья статья открыта (история: 3 записи)');

      // ---------------- 6. Главная: приветствие + «Продолжить» ----------------
      await _tapTab(tester, 0);
      await _waitForKey(tester, 'home-greeting', what: 'главная');
      await _settle(tester);
      await shot('2_06_home_top');
      debugPrint('ШАГ 6: главная — приветствие и категории (рис. 2.6а)');

      // ДИАГНОСТИКА: что реально в провайдере истории, БД и дереве.
      final homeCtx = tester.element(find.byKey(const Key('home-greeting')));
      final diagHp = homeCtx.read<HistoryProvider>();
      debugPrint(
        'ДИАГ: session id='
        '${homeCtx.read<SessionProvider>().currentUser?.id}',
      );
      debugPrint(
        'ДИАГ: history entries=${diagHp.entries.length} '
        '[${diagHp.entries.map((e) => e.article.id).join(",")}] '
        'loading=${diagHp.loading} byId='
        '${diagHp.articles.articleById('cpp_alg_loops')?.title}',
      );
      debugPrint(
        'ДИАГ: в дереве «Продолжить»: '
        '${tester.any(find.text('Продолжить'))}, ключей: '
        '${find.byKey(const Key('home-recent-cpp_alg_loops')).evaluate().length}',
      );
      debugPrint(
        'ДИАГ: db history='
        '${await AppDatabase.instance.db.query('history', orderBy: 'viewed_at')}',
      );

      // Секция «Продолжить» (используется в композитах 2.6 и 2.9).
      await _scrollToKey(tester, 'home-recent-cpp_alg_loops');
      await shot('2_06_home_continue');
      debugPrint('ШАГ 6.1: секция «Продолжить» (рис. 2.6б/2.9а)');

      // ---------------- 7. История ----------------
      await _tapKey(tester, 'home-open-history');
      await _waitForKey(
        tester,
        'history-entry-cpp_alg_loops',
        what: 'экран истории с записями',
      );
      await _settle(tester);
      await shot('2_09_history');
      debugPrint('ШАГ 7: экран истории (рис. 2.9б)');

      // ---------------- 8. Поиск с фильтром (рисунок 2.7) ----------------
      await _tapTab(tester, 1); // из истории — на корень справочника
      await _tapKey(tester, 'reference-open-search');
      await _waitForKey(tester, 'search-field', what: 'экран поиска');
      await _enterTextKey(tester, 'search-field', 'сортиров');
      await _settle(tester);
      await _tapKey(tester, 'diff-filter-intermediate');
      await _settle(tester);
      expect(find.byKey(const Key('search-results-count')), findsOneWidget);
      await shot('2_07_search_filter');
      debugPrint('ШАГ 8: поиск «сортиров» + фильтр «Средний» (рис. 2.7)');

      // ---------------- 9. Профиль (рисунок 2.13) ----------------
      await _tapTab(tester, 3);
      await _waitForKey(tester, 'profile-username', what: 'экран профиля');
      await _settle(tester);
      await shot('2_13_profile_top');
      debugPrint('ШАГ 9: профиль — данные и статистика (рис. 2.13а)');

      await _scrollToKey(tester, 'logout-button');
      await shot('2_13_profile_bottom');
      debugPrint('ШАГ 9.1: профиль — тема и выход (рис. 2.13б)');

      // ---------------- 10. Редактирование профиля ----------------
      await _scrollToKey(tester, 'profile-edit-open');
      await _tapKey(tester, 'profile-edit-open');
      await _waitForKey(
        tester,
        'profile-edit-username',
        what: 'экран редактирования профиля',
      );

      // 10a. Занятое имя (рисунок 2.14): ошибка приходит снекбаром.
      await _enterTextKey(tester, 'profile-edit-username', 'Student2');
      await _tapKey(tester, 'profile-edit-save');
      await _waitForFinder(
        tester,
        find.text('Имя пользователя уже занято'),
        'ошибка занятого имени',
        timeout: const Duration(seconds: 15),
      );
      // Снекбар внизу + поднять форму с занятым именем в кадр, пока
      // снекбар ещё жив (4 с).
      try {
        await tester.ensureVisible(find.byKey(const Key('profile-edit-username')).first);
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await tester.pump();
      } on Exception {
        // уже виден
      }
      await shot('2_14_profile_taken');
      await _enterTextKey(tester, 'profile-edit-username', 'demo_student');
      debugPrint('ШАГ 10.1: «Имя пользователя уже занято» (рис. 2.14)');

      // 10b. Неверный старый пароль (рисунок 2.15): inline на поле.
      await _scrollToKey(tester, 'profile-password-save');
      await _enterTextKey(tester, 'profile-password-old', 'wrong-old-pass');
      await _enterTextKey(tester, 'profile-password-new', 'new-pass77');
      await _enterTextKey(tester, 'profile-password-confirm', 'new-pass77');
      await _tapKey(tester, 'profile-password-save');
      await _waitForFinder(
        tester,
        find.text('Неверный старый пароль'),
        'ошибка старого пароля',
        timeout: const Duration(seconds: 15),
      );
      // Inline-ошибка живёт ПОД полем «Текущий пароль» — подтянуть её в кадр.
      try {
        await tester.ensureVisible(find.text('Неверный старый пароль').first);
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await tester.pump();
      } on Exception {
        // уже видна
      }
      await shot('2_15_old_password');
      debugPrint('ШАГ 10.2: «Неверный старый пароль» (рис. 2.15)');

      // ---------------- 11. Доп. кадр: смена цвета аватара ----------------
      // Имя уже возвращено к demo_student — сохранится только цвет.
      final editContext = tester.element(find.byType(ProfileEditScreen));
      final currentColor =
          editContext.read<SessionProvider>().currentUser?.avatarColor;
      final colorHex = currentColor == '#4D8BF5' ? '#2AA79B' : '#4D8BF5';
      await _tapKey(
        tester,
        'profile-color-${colorHex.substring(1).toLowerCase()}',
      );
      await _tapKey(tester, 'profile-edit-save');
      await _waitForKey(
        tester,
        'profile-username',
        what: 'возврат на профиль после сохранения',
      );
      expect(find.text('Сохранено'), findsOneWidget);
      await shot('extra_palette_saved');
      debugPrint('ШАГ 11: цвет аватара сохранён (доп. кадр)');

      // ---------------- 12. Выход №1 ----------------
      // Снекбар «Сохранено» после сохранения цвета аватара может всё ещё
      // перекрывать кнопку выхода внизу профиля — дождаться его пропажи.
      await _waitGone(tester, find.text(AppSnackBarMessages.saved));
      await _scrollToKey(tester, 'logout-button');
      await _tapKey(tester, 'logout-button');
      await _waitForKey(tester, 'logout-confirm', what: 'диалог выхода');
      await shot('extra_logout_dialog');
      await _tapKey(tester, 'logout-confirm');
      await _waitForKey(tester, 'login-field', what: 'экран входа после выхода');
      debugPrint('ШАГ 12: выход → экран входа');

      // ---------------- 13. Ошибочный вход (рисунок 2.3) ----------------
      await _enterTextKey(tester, 'login-field', 'demo_student');
      await _enterTextKey(tester, 'login-password', 'wrong-pass');
      await _tapKey(tester, 'login-submit');
      await _waitForFinder(
        tester,
        find.text('Неверный логин или пароль'),
        'ошибка неверного входа',
        timeout: const Duration(seconds: 15),
      );
      await _settle(tester);
      await shot('2_03_login_error');
      debugPrint('ШАГ 13: «Неверный логин или пароль» (рис. 2.3)');

      // ---------------- 14. Повторный вход ----------------
      await _enterTextKey(tester, 'login-password', 'demo123');
      await _tapKey(tester, 'login-submit');
      await _waitForKey(
        tester,
        'home-greeting',
        what: 'главная после повторного входа',
        timeout: const Duration(seconds: 20),
      );
      expect(find.text('Привет, demo_student!'), findsOneWidget);
      debugPrint('ШАГ 14: повторный вход → главная');

      // ---------------- 15. «Новый запуск»: восстановление сессии --------
      // Гасим дерево, создаем НОВУЮ сессию поверх реального хранилища
      // (prefs + БД) и монтируем свежий MobKursApp: сплэш отыгрывает
      // таймер и ведет сразу на главную (данные сохранились).
      await tester.pumpWidget(const SizedBox.shrink());
      final prefs2 = await SharedPreferences.getInstance();
      final session2 = SessionProvider(
        repository: AuthRepository(
          db: AppDatabase.instance.db,
          prefs: prefs2,
        ),
      );
      await session2.restoreSession();
      expect(
        session2.state.isAuthorized,
        isTrue,
        reason: 'id сессии в prefs, пользователь есть в БД',
      );
      expect(session2.currentUser?.username, 'demo_student');
      await tester.pumpWidget(
        MobKursApp(
          prefs: prefs2,
          initialThemeMode: ThemeProvider.modeFromString(
            prefs2.getString(AppConstants.prefSessionTheme),
          ),
          session: session2,
        ),
      );
      await tester.pump();
      await _waitForKey(
        tester,
        'home-greeting',
        what: 'главная сразу после «нового запуска»',
        timeout: const Duration(seconds: 25),
      );
      expect(find.text('Привет, demo_student!'), findsOneWidget);
      await shot('extra_restart_home');
      debugPrint('ШАГ 15: после «нового запуска» — сразу главная (persist)');

      // ---------------- 16. Финальный выход ----------------
      await _tapTab(tester, 3);
      await _waitForKey(
        tester,
        'logout-button',
        what: 'профиль после рестарта',
        timeout: const Duration(seconds: 15),
      );
      await _scrollToKey(tester, 'logout-button');
      await _tapKey(tester, 'logout-button');
      await _waitForKey(tester, 'logout-confirm', what: 'диалог выхода №2');
      await _tapKey(tester, 'logout-confirm');
      await _waitForKey(tester, 'login-field', what: 'финальный экран входа');
      debugPrint('ШАГ 16: финальный выход — сценарий завершён');

      // ---------------- Приёмка снимков ----------------
      expect(
        failedShots,
        isEmpty,
        reason: 'Не сняты контрольные кадры: ${failedShots.join(", ")}',
      );
      debugPrint('ПРОТОКОЛ снимков (${captured.length}): ${captured.join(", ")}');
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

// ===================== Помощники сценария =====================

/// Пауза на оседание (реальное время) + один свежий кадр. Хвостовые
/// переходы страниц (pop-анимации ~300 мс) оседают в реальном времени,
/// чтобы уходящие страницы не дублировали находки Finder'ов.
Future<void> _settle(WidgetTester tester) async {
  await Future<void>.delayed(const Duration(milliseconds: 600));
  await tester.pump();
}

/// Дождаться виджета по ключу (pump + реальные паузы до дедлайна).
Future<void> _waitForKey(
  WidgetTester tester,
  String keyName, {
  required String what,
  Duration timeout = const Duration(seconds: 12),
}) {
  return _waitForFinder(
    tester,
    find.byKey(Key(keyName)),
    what,
    timeout: timeout,
  );
}

/// Дождаться исчезновения Finder (снекбар может перекрывать нужную кнопку:
/// FAB песочницы, кнопку выхода внизу профиля). По дедлайну — тихо выходим.
Future<void> _waitGone(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (tester.any(finder)) {
    if (DateTime.now().isAfter(deadline)) {
      return; // снекбар дольше 8 с не живёт — не блокируем сценарий
    }
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  await tester.pump();
}

/// Дождаться виджета по произвольному Finder.
Future<void> _waitForFinder(
  WidgetTester tester,
  Finder finder,
  String what, {
  Duration timeout = const Duration(seconds: 12),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!tester.any(finder)) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Не дождались: $what');
    }
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
  await tester.pump();
}

/// Тап по виджету с ключом (с обеспечением прокручиваемой видимости).
Future<void> _tapKey(WidgetTester tester, String keyName) async {
  final finder = find.byKey(Key(keyName));
  if (!tester.any(finder)) {
    fail('Ключ $keyName не найден на текущем экране');
  }
  try {
    await tester.ensureVisible(finder.first);
    await tester.pump();
  } on Exception {
    // вне прокручиваемого предка — виджет и так виден
  }
  await tester.tap(finder.first);
  await tester.pump();
  await Future<void>.delayed(const Duration(milliseconds: 80));
}

/// Тап по виджету с известным текстом (карточки сниппетов и пр.).
Future<void> _tapByText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  if (!tester.any(finder)) {
    fail('Текст «$text» не найден на текущем экране');
  }
  try {
    await tester.ensureVisible(finder.first);
    await tester.pump();
  } on Exception {
    // без прокрутки
  }
  await tester.tap(finder.first);
  await tester.pump();
  await Future<void>.delayed(const Duration(milliseconds: 80));
}

/// Ввод текста в поле по ключу (через его EditableText).
Future<void> _enterTextKey(
  WidgetTester tester,
  String keyName,
  String text,
) async {
  final field = find.byKey(Key(keyName));
  if (!tester.any(field)) {
    fail('Поле $keyName не найдено на текущем экране');
  }
  final editable = find.descendant(
    of: field,
    matching: find.byType(EditableText),
  );
  if (!tester.any(editable)) {
    fail('Поле $keyName без EditableText');
  }
  try {
    await tester.ensureVisible(field.first);
    await tester.pump();
  } on Exception {
    // без прокрутки
  }
  await tester.enterText(editable.first, text);
  await tester.pump();
}

/// Прокрутка до виджета по ключу на экране.
///
/// Ленивый ListView строит только видимых детей: ключ может отсутствовать
/// в дереве ДО прокрутки. Контроллерные API (scrollUntilVisible) требуют
/// единственного элемента и падают «Bad state: No element», поэтому крутим
/// вручную жестами и после каждого цикла проверяем, не построился ли ключ.
Future<void> _scrollToKey(WidgetTester tester, String keyName) async {
  final finder = find.byKey(Key(keyName));
  for (var attempt = 0; attempt < 30; attempt++) {
    if (tester.any(finder)) {
      try {
        await tester.ensureVisible(finder.first);
      } on Exception {
        // нет прокручиваемого предка — виджет и так виден
      }
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pump();
      return;
    }
    // Жест «свайп вверх» от 55% высоты экрана: тянем содержимое вниз по
    // списку. Реальное асинхронное поведение LiveTestingBinding.
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    final start = Offset(size.width * 0.5, size.height * 0.55);
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(0, -250));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await gesture.moveBy(const Offset(0, -250));
    await gesture.up();
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await tester.pump();
  }
  fail('Не дождались ключа $keyName после 30 циклов прокрутки');
}

/// Перейти на вкладку [index] и оказаться на её КОРНЕ.
///
/// Тап по вкладке из другой ветки лишь ВОССТАНАВЛИВАЕТ её сохранённый стек
/// (могут быть pushed-страницы: статья, избранное, история, редактор), а
/// повторный тап по активной вкладке всегда откатывает ветку на корень
/// (goBranch(initialLocation: true)). Поэтому тапаем дважды — идемпотентно.
Future<void> _tapTab(WidgetTester tester, int index) async {
  final bar = find.byType(NavigationBar);
  if (!tester.any(bar)) {
    fail('Нижняя навигация не найдена — тап по вкладке невозможен');
  }
  Future<void> tapSegment() async {
    final rect = tester.getRect(bar.first);
    final x = rect.left + rect.width * (index + 0.5) / 4;
    await tester.tapAt(Offset(x, rect.center.dy));
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await tester.pump();
  }

  await tapSegment();
  await tapSegment(); // сброс ветки на корень, если там был pushed-стек
}

// ===================== Клиент снимков =====================

/// Один снимок: запрос `<name>.req` в файлах приложения → хостовый демон
/// снимает экран (`adb exec-out screencap`) и касается `<name>.done`.
Future<bool> takeShot(
  WidgetTester tester,
  String shotsPath,
  String name,
) async {
  debugPrint('СНИМОК: запрос $name');
  // Дать UI осесть (реальное время) и собрать свежий кадр.
  await Future<void>.delayed(const Duration(milliseconds: 350));
  await tester.pump();

  final dir = Directory(shotsPath);
  final req = File('${dir.path}/$name.req');
  final done = File('${dir.path}/$name.done');
  var ok = false;
  try {
    await dir.create(recursive: true);
    await req.writeAsString('');
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    while (!ok && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      // Основной сигнал — done от демона; резервный — пропажа req: демон
      // удаляет req сразу после касания done, так что пропажа req при
      // живом демоне тоже означает «снимок сделан».
      ok = done.existsSync() || !req.existsSync();
    }
  } on Exception catch (e) {
    debugPrint('СНИМОК: ошибка $name: $e');
  } finally {
    _deleteQuietly(req);
    _deleteQuietly(done);
  }
  if (!ok) {
    debugPrint(
      'СНИМОК: ТАЙМАУТ $name — dir=${dir.path} '
      'exists=${dir.existsSync()} содержимое: ${_listDir(dir)}',
    );
  }
  return ok;
}

/// Содержимое папки снимков для диагностики таймаутов.
String _listDir(Directory dir) {
  try {
    if (!dir.existsSync()) return '(нет папки)';
    return dir.listSync().map((e) => e.uri.pathSegments.last).join('; ');
  } on Exception {
    return '(не читается)';
  }
}

/// Удалить файл, не падая (уже удалён или недоступен — не важно).
void _deleteQuietly(File file) {
  try {
    if (file.existsSync()) file.deleteSync();
  } on Exception {
    // игнорируем
  }
}
