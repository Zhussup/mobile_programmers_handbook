# Контент справочника (P6, семестр 1)

JSON-ассеты для раздела «Справочник»: рендерятся блоковым рендером из
`article_repository` (без markdown-зависимостей). Файлы в этой папке:
`cpp_syntax.json`, `cpp_data_structures.json`, `cpp_algorithms.json` —
15 статей (3 категории × 5).

## Схема файла (строго)

```json
{
  "category": {"id": "...", "title": "...", "icon": "...", "description": "..."},
  "articles": [{
    "id": "...", "title": "...", "summary": "...",
    "difficulty": "beginner", "tags": ["...", "..."],
    "blocks": [ ... ]
  }]
}
```

- `category.id` — строки-роуты `/reference/:categoryId`; `category.icon` — имя Material Icons.
- `difficulty` — только `"beginner" | "intermediate" | "advanced"`.
- `tags` — русские, строчными (допустимы латинские термины вроде `static_cast`), для поиска S2.

## Блоки (`blocks`)

| type | поля | назначение |
|---|---|---|
| `text` | `text` | абзац текста |
| `heading` | `text` | подзаголовок внутри статьи |
| `list` | `items: string[]` | маркированный список |
| `code` | `language`, `code`, `output`, `caption` | пример кода (рендер: подсветка, копирование, вывод) |
| `note` | `text` | врезка-замечание |

Другие типы блоков не разрешены, поля у каждого типа фиксированы. Для `code`
сейчас только `language: "cpp"` (позже появится `"dart"`).

Объём статьи: **3–5 текстовых блоков (text/heading/list/note суммарно) и минимум 1 code-блок**; чтение за пару минут. У каждого `code`: полный компилируемый файл (с `main`), `output` — ожидаемый вывод.

## Соглашения по содержанию

- **Вывод программ — только ASCII.** Кириллица в `text/heading/list/note/summary/tags/caption`; строки литералов в `code` тоже ASCII (правило: UTF-8 весь файл, но печатаемая консольная часть — ASCII).
- `output` — реальный вывод, без завершающего `\n`. Для примеров с `cin` ввод задокументирован в `caption` (см. `cpp_syn_io`, «Ввод»: ввод «Alex 19»).
- `code` — ASCII-содержимое: латинские идентификаторы, вывод на английском.

## Имена категорий и иконки

| Файл | category.id | title | icon |
|---|---|---|---|
| cpp_syntax.json | `syntax` | Синтаксис C++ | `code` |
| cpp_data_structures.json | `data_structures` | Структуры данных | `layers` |
| cpp_algorithms.json | `algorithms` | Алгоритмы | `sort` |

Набор иконок разрешён из: `terminal, layers, storage, sort, school, grid_view, memory, code`.

## id статей

Уникальны во всём справочнике, префиксы по файлу:
- `cpp_syn_*` — синтаксис (`cpp_syn_hello_world`, `cpp_syn_variables`, `cpp_syn_operators`, `cpp_syn_io`, `cpp_syn_type_conversions`),
- `cpp_ds_*` — структуры данных (`cpp_ds_array`, `cpp_ds_string`, `cpp_ds_vector`, `cpp_ds_struct`, `cpp_ds_pointers_references`),
- `cpp_alg_*` — алгоритмы (`cpp_alg_conditions`, `cpp_alg_loops`, `cpp_alg_bubble_sort`, `cpp_alg_binary_search`, `cpp_alg_recursion`).

Распределение сложности: 8 × beginner, 6 × intermediate, 1 × advanced.

## Проверка (примеры)

Каждый code-блок проверен компиляцией и прогоном (g++ -std=c++17 -Wall -Wextra,
вывод совпадает с `output`). Быстрая проверка схемы:

```bash
python3 -c "import json,glob; [json.load(open(p, encoding='utf-8')) for p in glob.glob('*.json')] && print('json ok')"
# компиляция отдельного примера:
g++ -std=c++17 -Wall -Wextra -o /tmp/a snippet.cpp && /tmp/a
```

Весь файл — строго UTF-8, без BOM.