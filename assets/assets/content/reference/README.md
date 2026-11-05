# Контент справочника (P6 + P8)

JSON-ассеты для раздела «Справочник»: рендерятся блоковым рендером из
`article_repository` (без markdown-зависимостей). Файлы в этой папке:
`cpp_syntax.json`, `cpp_data_structures.json`, `cpp_algorithms.json`,
`cpp_stl.json`, `cpp_oop.json`, `dart_flutter.json` —
46 статей (C++ 5 категорий × 8 + Dart/Flutter 6).

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
сейчас `language: "cpp"` или `"dart"` (для Dart/Flutter-ветки).

Объём статьи: **3–5 текстовых блоков (text/heading/list/note суммарно) и 1–2 code-блока**; чтение за пару минут. У каждого `code`: полный компилируемый файл (с `main`), `output` — ожидаемый вывод. Исключение — чисто UI-примеры Flutter (статьи виджетов): там поле `output` опускается, у рендера такой блок просто не показывает «Показать вывод».

## Соглашения по содержанию

- **Вывод программ — только ASCII.** Кириллица в `text/heading/list/note/summary/tags/caption`; строки литералов в `code` тоже ASCII (правило: UTF-8 весь файл, но печатаемая консольная часть — ASCII; комментарии в `code` — тоже ASCII).
- `output` — реальный вывод, без завершающего `\n`. Для примеров с `cin` ввод задокументирован в `caption` (см. `cpp_syn_io`, «Ввод»: ввод «Alex 19»).
- Dart-примеры: `language: "dart"`, запускаются через `dart run` — вывод тоже реальный. UI-примеры Flutter (виджеты со `runApp`) не запускаются — `output` нет.

## Имена категорий и иконки

| Файл | category.id | title | icon |
|---|---|---|---|
| cpp_syntax.json | `syntax` | Синтаксис C++ | `code` |
| cpp_data_structures.json | `data_structures` | Структуры данных | `layers` |
| cpp_algorithms.json | `algorithms` | Алгоритмы | `sort` |
| cpp_stl.json | `stl` | STL | `storage` |
| cpp_oop.json | `oop` | ООП | `memory` |
| dart_flutter.json | `dart_flutter` | Dart/Flutter | `school` |

Набор иконок разрешён из: `terminal, layers, storage, sort, school, grid_view, memory, code`.

## id статей

Уникальны во всём справочнике, префиксы по файлу:
- `cpp_syn_*` — синтаксис (`cpp_syn_hello_world`, `cpp_syn_variables`, `cpp_syn_operators`, `cpp_syn_io`, `cpp_syn_type_conversions`, `cpp_syn_comments_style`, `cpp_syn_functions`, `cpp_syn_namespaces_scope`),
- `cpp_ds_*` — структуры данных (`cpp_ds_array`, `cpp_ds_string`, `cpp_ds_vector`, `cpp_ds_struct`, `cpp_ds_pointers_references`, `cpp_ds_pair_tuple`, `cpp_ds_matrix`, `cpp_ds_stack_queue`),
- `cpp_alg_*` — алгоритмы (`cpp_alg_conditions`, `cpp_alg_loops`, `cpp_alg_bubble_sort`, `cpp_alg_binary_search`, `cpp_alg_recursion`, `cpp_alg_min_max`, `cpp_alg_std_sort`, `cpp_alg_accumulate`),
- `cpp_stl_*` — STL (`cpp_stl_containers`, `cpp_stl_vector_deep`, `cpp_stl_string_algo`, `cpp_stl_map_set`, `cpp_stl_iterators`, `cpp_stl_algorithms`, `cpp_stl_lambdas`, `cpp_stl_priority_queue`),
- `cpp_oop_*` — ООП (`cpp_oop_class`, `cpp_oop_encapsulation`, `cpp_oop_ctor_dtor`, `cpp_oop_inheritance`, `cpp_oop_polymorphism`, `cpp_oop_abstract`, `cpp_oop_operators`, `cpp_oop_static_this`),
- `dart_*` — Dart/Flutter (`dart_basics`, `dart_null_safety`, `dart_functions`, `dart_async`, `dart_stateful_widget`, `dart_layout_widgets`).

Распределение сложности: 15 × beginner, 25 × intermediate, 6 × advanced.

Тематика категорий не пересекается: у STL углублённые «библиотечные» статьи
(итераторы, ёмкость, алгоритмы, лямбды), у «Структур данных» — контейнеры
«с нуля» и их семантика.

## Проверка (примеры)

Каждый code-блок проверен компиляцией и прогоном (g++ -std=c++17 -Wall -Wextra,
вывод совпадает с `output`; Dart-примеры — через `dart run`, Flutter-примеры —
`flutter analyze`). Быстрая проверка схемы:

```bash
python3 -c "import json,glob; [json.load(open(p, encoding='utf-8')) for p in glob.glob('*.json')] && print('json ok')"
# компиляция отдельного примера:
g++ -std=c++17 -Wall -Wextra -o /tmp/a snippet.cpp && /tmp/a
```

Весь файл — строго UTF-8, без BOM.