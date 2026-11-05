# Админ-панель ПМ07 (Flutter Web)

Веб-приложение для администрирования мобильного приложения: пользователи, роли,
контент (статьи), публикация и снятие с публикации. Работает с backend по REST
API (`/api`), авторизация — Bearer-токен администратора.

## Стек

- Flutter Web (Material 3), Dart 3;
- `provider` — состояние;
- `go_router` — маршрутизация и защита маршрутов;
- `http` — сетевой клиент (таймаут 10 с);
- `shared_preferences` — хранение токена между перезагрузками страницы;
- `intl` — форматирование дат.

Структура feature-first:

```
lib/
├── main.dart                 # точка входа, восстановление сессии
├── app.dart                  # MaterialApp.router + провайдеры
├── router/app_router.dart    # маршруты и redirect по авторизации
├── core/
│   ├── config/app_config.dart
│   ├── network/api_client.dart, api_exception.dart
│   ├── models/               # AdminUser, Article, Category
│   ├── theme/app_theme.dart
│   ├── utils/                # JSON/даты
│   └── widgets/app_snackbar.dart
└── features/
    ├── auth/                 # вход администратора
    ├── users/                # таблица, поиск, CRUD, блокировка, роли
    ├── articles/             # таблица, фильтры, CRUD, публикация
    ├── dashboard/            # сводка
    └── shell/                # навигация (Rail/меню)
```

## Требования

- Flutter 3.47+ (Dart 3.13+).
- Запущенный backend из `../backend` на порту 8080.
- Пакеты из локального кэша pub (`flutter pub get --offline`).

## Запуск backend

Из корня репозитория:

```bash
cd backend
dart pub get
dart run bin/server.dart
```

Сервер слушает `http://localhost:8080`, API — `http://localhost:8080/api`.
При первом запуске создаётся `backend/data/app.db` и выполняет seed.

Проверка:

```bash
curl http://localhost:8080/api/health
# {"data":{"status":"ok"}}
```

## Запуск админ-панели

```bash
cd admin
flutter pub get --offline
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080/api
```

`API_BASE_URL` можно не указывать — значение по умолчанию совпадает.
Адрес по умолчанию задан в `lib/core/config/app_config.dart`.

### Учётные данные (seed backend)

| Роль | Логин | Пароль |
|---|---|---|
| Администратор | `admin` | `admin123` |
| Пользователь | `user` | `user123` |

Вход пользователя с ролью `user` в панель запрещён: выводится сообщение
«Доступ только для администратора», выданный токен аннулируется.

## Сборка

```bash
cd admin
flutter build web --release
# результат: admin/build/web
```

Раздача статики локально:

```bash
python3 -m http.server 8090 --directory build/web
```

Backend может отдавать `admin/build/web` статикой (опционально, по контракту).

## Проверки

```bash
cd admin
flutter analyze     # без ошибок
flutter test        # widget-тесты на fake API, без сети
flutter build web --release
```

Тесты:

- `test/login_screen_test.dart` — успешный вход, неверные данные, запрет
  не-администратору;
- `test/users_screen_test.dart` — список пользователей, запрет блокировки себя,
  блокировка другого пользователя;
- `test/articles_screen_test.dart` — список статей и публикация.
- `test/fakes/fake_api_client.dart` — фейковый API-клиент, запросы не уходят в
  сеть.

## Маршруты

| URL | Назначение |
|---|---|
| `/login` | вход администратора |
| `/dashboard` | сводка: пользователи, статьи, опубликованные |
| `/users` | пользователи: поиск, создание, редактирование, блокировка, роль |
| `/articles` | статьи: фильтры по категории/статусу, публикация, удаление |
| `/articles/edit/new` | создание статьи |
| `/articles/edit/:id` | редактирование статьи |

## Работа с API

- Заголовок: `Authorization: Bearer <token>`.
- Ответы: `{"data": ...}`; ошибки: `{"error":{"code","message","fields"}}`.
- 401 — выход на `/login`; 403 и 400 — сообщение (snackbar или ошибка поля);
  сеть/таймаут — сообщение с возможностью повторить.
- Создание/изменение статьи отправляет `category_id`, `title`, `summary`,
  `difficulty`, `tags` (массив строк), `blocks_json` (строка JSON-массива) и
  `blocks` (тот же массив); публикация меняется отдельным
  `PATCH /api/admin/articles/{id}/publish`.
- Пользователи: `POST/PUT /api/admin/users`, блокировка —
  `PATCH .../{id}/block`, роль — `PATCH .../{id}/role`.
- Себя нельзя заблокировать и понизить — проверяется и в UI, и на сервере.

## Ограничения

- Токен хранится в `localStorage` браузера через `shared_preferences`; для
  учебного проекта это допустимо.
- Для работы из браузера backend должен отдавать CORS-заголовки (см. контракт
  архитектуры).
- Скриншоты панели для пояснительной записки делаются вручную после запуска
  backend (каталог `docs/screenshots`).
