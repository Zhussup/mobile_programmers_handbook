# Backend курсового проекта

Отдельный Dart-пакет: REST API на `shelf`, база SQLite через
`sqflite_common_ffi`. Мобильное приложение и админ-панель работают с данными
только через этот API.

## Требования

- Dart SDK 3.13 или новее.
- Пакеты `shelf`, `sqflite_common_ffi`, `crypto`, `path` и `test`.

## Установка и запуск

```bash
cd backend
dart pub get --offline
dart run bin/server.dart
```

Сервер слушает `http://0.0.0.0:8080`, базовый префикс API — `/api`.
При первом запуске создаётся файл `backend/data/app.db`, применяется схема и
выполняется seed. Проверка:

```bash
curl http://localhost:8080/api/health
# {"data":{"status":"ok"}}
```

### Переменные окружения

| Переменная | По умолчанию | Назначение |
|---|---|---|
| `PORT` | `8080` | порт HTTP-сервера |
| `DB_PATH` | `backend/data/app.db` (из корня проекта) / `data/app.db` (из `backend/`) | путь к файлу SQLite |
| `SEED_DIR` | `../assets/content/reference` | каталог с JSON-контентом для seed |

Пример запуска на другом порту:

```bash
PORT=9090 DB_PATH=/tmp/kursach.db dart run bin/server.dart
```

Seed выполняется только для пустых таблиц: пользователи создаются, если таблица
`users` пуста; категории и статьи — если пусты `categories` и `articles`.
Опубликованные статьи из JSON получают `is_published = 1`.

## Учётные записи

| Логин | Почта | Пароль | Роль |
|---|---|---|---|
| `admin` | `admin@example.com` | `admin123` | `admin` |
| `user` | `user@example.com` | `user123` | `user` |

Пароль хранится как SHA-256 от `пароль + соль` (соль — 16 случайных байт).
Для учебного проекта этого достаточно; в продакшене применяют bcrypt/argon2.

## Формат ответов

Успех:

```json
{"data": {"id": 1, "username": "admin"}}
```

Ошибка:

```json
{"error": {"code": "validation_error", "message": "Почта обязательна", "fields": {"email": "..."}}}
```

Коды: `400 validation_error`, `401 unauthorized`, `403 forbidden` /
`user_blocked`, `404 not_found`, `409 conflict`, `500 internal_error`.
Защищённые запросы передают `Authorization: Bearer <token>`; токен — 32
случайных байта в hex, срок жизни — 30 дней.

## Эндпоинты

Публичные: `GET /api/health`, `POST /api/auth/register`,
`POST /api/auth/login`.

Пользователь (Bearer): `POST /api/auth/logout`, `GET /api/auth/me`,
`PUT /api/profile`, `PUT /api/profile/password`, `GET /api/categories`,
`GET /api/articles`, `GET /api/articles/{id}`, `GET/POST/DELETE`
`/api/favorites`, `GET/POST/DELETE /api/history`, CRUD `/api/snippets`.

Администратор (Bearer + `role=admin`): CRUD `/api/admin/users`
(включая `PATCH .../block` и `PATCH .../role`), CRUD `/api/admin/articles`
(включая `PATCH .../publish`) и CRUD `/api/admin/categories`.

## Примеры curl

Вход администратора и сохранение токена:

```bash
TOKEN=$(curl -s -X POST http://localhost:8080/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"login":"admin","password":"admin123"}' \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["token"])')
```

Список статей с фильтром:

```bash
curl -s "http://localhost:8080/api/articles?category=syntax&difficulty=beginner" \
  -H "Authorization: Bearer $TOKEN"
```

Создание статьи:

```bash
curl -s -X POST http://localhost:8080/api/admin/articles \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{
    "id": "my_article",
    "title": "Новая статья",
    "summary": "Краткое описание",
    "category_id": "syntax",
    "difficulty": "beginner",
    "tags": ["cpp", "пример"],
    "blocks": [{"type": "text", "text": "Текст статьи"}],
    "is_published": true
  }'
```

Блокировка пользователя (id 2 — seeded `user`):

```bash
curl -s -X PATCH http://localhost:8080/api/admin/users/2/block \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"blocked": true}'
```

При блокировке все сессии пользователя удаляются, поэтому ранее выданный
токен сразу получает `401`, а новый вход — `403 user_blocked`.
Заблокировать или понизить собственную учётную запись администратора нельзя.

## Проверка качества

```bash
cd backend
dart analyze
dart test
```

Тесты используют in-memory SQLite и вызывают shelf-обработчик напрямую:
проверяются health, регистрация/вход, блокировка, роли, CRUD пользователей,
статей и категорий, публикация, избранное, история, сниппеты, профиль и
валидация.

## Структура

```
backend/
├── bin/server.dart          # точка входа, порт, graceful shutdown
├── lib/
│   ├── api/router.dart      # ручная маршрутизация, CORS, логирование
│   ├── api/handlers/        # auth, content, favorites, history, snippets, admin
│   ├── core/db.dart         # SQLite, схема, миграции, seed
│   ├── core/auth.dart       # соль/хэш, токены, Bearer, роли
│   ├── core/errors.dart     # ApiError и JSON-ответы
│   ├── core/validation.dart # проверки полей
│   ├── core/http_utils.dart # чтение JSON-тела
│   └── models/              # user, article, category, snippet
├── test/api_test.dart
└── README.md
```
