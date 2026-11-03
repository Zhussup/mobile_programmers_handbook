#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Автоисправление подписей рисунков и таблиц в курсовой работе (python-docx).

Что делает:
  * приводит подписи рисунков к виду «Рисунок 2.1. Название»:
    по центру, Times New Roman 14, без курсива и полужирного;
  * приводит названия таблиц к виду «Таблица 2.1. Название»:
    над таблицей, абзацный отступ 1,25 см, Times New Roman 14;
  * перенумеровывает рисунки и таблицы в пределах главы (по порядку);
  * обновляет ссылки в тексте («рисунок 2.1», «таблица 2.1») по карте
    перенумерации;
  * ставит Times New Roman 12 для всего текста внутри таблиц;
  * при наличии LibreOffice определяет таблицы, разрывающиеся между
    страницами, и добавляет надпись «Продолжение таблицы N.M»;
  * не трогает приложения (после заголовка «ПРИЛОЖЕНИЕ …»).

Использование:
    python3 tools/fix_captions.py input.docx output.docx
    python3 tools/fix_captions.py input.docx output.docx --safe
    python3 tools/fix_captions.py input.docx output.docx --no-continuation

Режим --safe: только форматирование уже существующих подписей и шрифтов
таблиц; перенумерация, вставка названий и «Продолжений» не выполняются,
необходимые ручные действия выводятся в отчёте.

Скрипт идемпотентен: повторный запуск на его же результате не меняет
нумерацию и не добавляет дублирующиеся подписи/«Продолжения».
"""

import argparse
import copy
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import docx
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Pt
from docx.table import Table
from docx.text.paragraph import Paragraph

FONT = "Times New Roman"
CAPTION_SIZE = Pt(14)
TABLE_SIZE = Pt(12)
TABLE_INDENT = Cm(1.25)

CAPTION_RE = re.compile(
    r"^\s*(?P<kind>Рисунок|Таблица)\s+(?P<ch>\d+)\.(?P<num>\d+)"
    r"\.?\s*(?:[—–-]\s*)?(?P<title>.*)$",
    re.I,
)
CONT_RE = re.compile(
    r"^\s*Продолжение\s+таблицы\s+(?P<ch>\d+)\.(?P<num>\d+)\b", re.I
)
REF_RE = re.compile(
    r"(?P<kind>рисун\w*|таблиц\w*)(?P<space>\s+)(?P<ch>\d+)\.(?P<num>\d+)",
    re.I,
)
APPENDIX_RE = re.compile(r"^\s*(ПРИЛОЖЕНИЕ|APPENDIX)\b", re.I)
CHAPTER_RE = re.compile(r"^\s*ГЛАВА\s+(\d+)\b", re.I)
NUMBERED_RE = re.compile(r"^\s*(\d+)(?:\.|\s)")
TESTING_RE = re.compile(r"^\s*(ТЕСТИРОВАНИЕ|TESTING)\b", re.I)
NUM_PREFIX_RE = re.compile(r"^\s*\d+(?:\.\d+)*\.?\s*")


# --------------------------------------------------------------------------
# Вспомогательные функции
# --------------------------------------------------------------------------
def iter_blocks(doc):
    """Параграфы и таблицы в порядке следования в теле документа."""
    body = doc.element.body
    for child in body.iterchildren():
        if child.tag == qn("w:p"):
            yield Paragraph(child, doc)
        elif child.tag == qn("w:tbl"):
            yield Table(child, doc)


def style_name(p):
    try:
        return p.style.name or ""
    except Exception:
        return ""


def is_heading1(p):
    return style_name(p).lower() in ("heading 1", "заголовок 1")


def is_heading(p):
    return style_name(p).lower().startswith(("heading", "заголовок"))


def heading_chapter(text, last_chapter):
    """Номер главы для заголовка Heading 1 или None."""
    m = CHAPTER_RE.match(text)
    if m:
        return int(m.group(1))
    m = NUMBERED_RE.match(text)
    if m:
        return int(m.group(1))
    if TESTING_RE.match(text):
        return (last_chapter or 0) + 1
    return None


def parse_caption(text):
    m = CAPTION_RE.match(text or "")
    if not m:
        return None
    kind = "fig" if m.group("kind").lower().startswith("рисун") else "tab"
    title = (m.group("title") or "").strip()
    title = title.rstrip(".").strip()
    # «Таблица 2.5 — Таблица users» → «Таблица 2.5. users», чтобы слово
    # «Таблица» не дублировалось в подписи.
    title = re.sub(r"^Таблица\s+", "", title, flags=re.I).strip()
    return {
        "kind": kind,
        "ch": int(m.group("ch")),
        "num": int(m.group("num")),
        "full": f"{int(m.group('ch'))}.{int(m.group('num'))}",
        "title": title,
    }


def is_continuation(text):
    return bool(CONT_RE.match(text or ""))


def set_run_font(run, size, bold=None, italic=None):
    run.font.name = FONT
    run.font.size = size
    if bold is not None:
        run.font.bold = bold
    if italic is not None:
        run.font.italic = italic
    rPr = run._element.get_or_add_rPr()
    rFonts = rPr.find(qn("w:rFonts"))
    if rFonts is None:
        rFonts = OxmlElement("w:rFonts")
        rPr.insert(0, rFonts)
    for attr in ("w:ascii", "w:hAnsi", "w:eastAsia", "w:cs"):
        rFonts.set(qn(attr), FONT)


def clear_paragraph(p):
    for child in list(p._p):
        if child.tag != qn("w:pPr"):
            p._p.remove(child)


def write_caption(p, text, kind):
    """Переписать подпись одним прогоном и оформить по требованиям."""
    clear_paragraph(p)
    run = p.add_run(text)
    set_run_font(run, CAPTION_SIZE, bold=False, italic=False)
    pf = p.paragraph_format
    if kind == "fig":
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        pf.first_line_indent = Cm(0)
    else:
        p.alignment = WD_ALIGN_PARAGRAPH.LEFT
        pf.first_line_indent = TABLE_INDENT
        # Название не должно отрываться от таблицы на предыдущей странице.
        pf.keep_with_next = True
    pf.space_before = Pt(6)
    pf.space_after = Pt(6)
    pf.line_spacing = 1.0


def write_continuation(p, text):
    clear_paragraph(p)
    run = p.add_run(text)
    set_run_font(run, CAPTION_SIZE, bold=False, italic=False)
    pf = p.paragraph_format
    p.alignment = WD_ALIGN_PARAGRAPH.LEFT
    pf.first_line_indent = TABLE_INDENT
    pf.space_before = Pt(6)
    pf.space_after = Pt(6)
    pf.line_spacing = 1.0
    pf.keep_with_next = True


def table_rows_unique(table):
    """Строки таблицы без дублей объединённых ячеек."""
    rows = []
    for row in table.rows:
        seen = set()
        cells = []
        for cell in row.cells:
            if id(cell._tc) in seen:
                continue
            seen.add(id(cell._tc))
            cells.append(cell)
        rows.append(cells)
    return rows


def set_table_fonts(table):
    """Times New Roman 12 для всего текста таблицы (полужирный сохраняем)."""
    changed = 0
    for row in table.rows:
        for cell in row.cells:
            for p in cell.paragraphs:
                for run in p.runs:
                    if not run.text:
                        continue
                    set_run_font(
                        run,
                        TABLE_SIZE,
                        bold=True if run.font.bold else None,
                        italic=False,
                    )
                    changed += 1
    return changed


def table_font_stats(table):
    stats = {}
    for row in table.rows:
        for cell in row.cells:
            for p in cell.paragraphs:
                for run in p.runs:
                    if not run.text:
                        continue
                    key = (
                        run.font.name,
                        run.font.size.pt if run.font.size else None,
                    )
                    stats[key] = stats.get(key, 0) + 1
    return stats


def replace_references(paragraphs, table_map, figure_map):
    """Обновить ссылки в тексте. Возвращает список изменений."""
    changes = []

    def repl(m):
        kind = "fig" if m.group("kind").lower().startswith("рисун") else "tab"
        mapping = figure_map if kind == "fig" else table_map
        old = f"{int(m.group('ch'))}.{int(m.group('num'))}"
        new = mapping.get(old)
        if not new or new == old:
            return m.group(0)
        return f"{m.group('kind')}{m.group('space')}{new}"

    for p in paragraphs:
        text_before = p.text
        if not text_before.strip():
            continue
        # Сначала пытаемся заменить внутри отдельных прогонов, сохраняя
        # форматирование (в документе ссылки обычно лежат одним прогоном).
        for run in p.runs:
            new_text = REF_RE.sub(repl, run.text)
            if new_text != run.text:
                run.text = new_text
        if p.text != text_before:
            changes.append({"before": text_before, "after": p.text})
            continue
        # Если ссылка была разорвана между прогонами — переписываем абзац,
        # сохраняя оформление первого прогона.
        if REF_RE.search(text_before):
            new_plain = REF_RE.sub(repl, text_before)
            if new_plain != text_before:
                first = p.runs[0] if p.runs else None
                clear_paragraph(p)
                run = p.add_run(new_plain)
                if first is not None:
                    # Копируем основные свойства шрифта первого прогона.
                    if first.font.name:
                        run.font.name = first.font.name
                    if first.font.size:
                        run.font.size = first.font.size
                    if first.font.bold is not None:
                        run.font.bold = first.font.bold
                    if first.font.italic is not None:
                        run.font.italic = first.font.italic
                else:
                    set_run_font(run, CAPTION_SIZE)
                changes.append({"before": text_before, "after": new_plain})
    return changes


def normalize_words(text):
    return re.findall(r"[A-Za-zА-Яа-яЁё0-9_]+", (text or "").casefold())


def convert_to_pdf(docx_path, outdir):
    soffice = shutil.which("soffice") or shutil.which("libreoffice")
    if not soffice:
        return None, "LibreOffice не найден"
    try:
        subprocess.run(
            [
                soffice,
                "--headless",
                "--convert-to",
                "pdf",
                "--outdir",
                str(outdir),
                str(docx_path),
            ],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=300,
        )
    except Exception as exc:  # noqa: BLE001
        return None, f"ошибка конвертации: {exc}"
    pdf = Path(outdir) / (Path(docx_path).stem + ".pdf")
    if not pdf.exists():
        return None, "PDF не создан"
    return pdf, None


def pdf_pages_text(pdf_path):
    pdftotext = shutil.which("pdftotext")
    if not pdftotext:
        return None, "pdftotext не найден"
    try:
        out = subprocess.check_output(
            [pdftotext, "-layout", str(pdf_path), "-"], timeout=120
        )
    except Exception as exc:  # noqa: BLE001
        return None, f"ошибка pdftotext: {exc}"
    return out.decode("utf-8", errors="replace").split("\f"), None


def find_caption_page(pages, full, prefix="Таблица"):
    pat = re.compile(prefix + r"\s+" + re.escape(full) + r"\b")
    for i, page in enumerate(pages):
        if pat.search(page):
            return i + 1
    return None


def norm_text(s):
    return re.sub(r"\s+", " ", (s or "")).strip().casefold()


def longest_word(text, min_len=4):
    words = re.findall(r"[a-zа-яё0-9_/]{%d,}" % min_len, norm_text(text))
    return max(words, key=len) if words else ""


def row_key_groups(cells):
    """Наборы ключей строки: все ключи набора должны быть на странице.

    Для строк с номером в первой ячейке («28») ключом становится номер плюс
    редкое слово из второй ячейки: одно слово вроде «история» встречается в
    заголовке и даёт ложное совпадение.
    """
    if not cells:
        return []
    first = norm_text(cells[0].text)
    second = norm_text(cells[1].text) if len(cells) > 1 else ""
    groups = []
    if re.fullmatch(r"\d+", first or "x"):
        w = longest_word(second, 5)
        groups.append([first] + ([w] if w else []))
        groups.append([w] if w else [])
        return [g for g in groups if g]
    if len(first) >= 8:
        groups.append([first])
        w = longest_word(first)
        if w and w != first:
            groups.append([w])
    elif len(first) >= 3:
        w = longest_word(second, 5)
        groups.append([first] + ([w] if w else []))
    else:
        w = longest_word(second, 5)
        if w:
            groups.append([w])
    return [g for g in groups if g]


def row_pages(table, pages, caption_page):
    """Страницы, на которых начинаются строки таблицы.

    Поиск монотонный: строка ищется начиная со страницы предыдущей строки,
    поэтому одинаковые имена полей в соседних таблицах не дают ложных
    совпадений на более ранних страницах.
    """
    rows = table_rows_unique(table)
    page_texts = [norm_text(p) for p in pages]
    result = [caption_page] + [None] * (len(rows) - 1)
    last_page = caption_page or 1
    for i in range(1, len(rows)):
        groups = row_key_groups(rows[i])
        if not groups:
            result[i] = last_page
            continue
        start = max(0, last_page - 1)
        end = min(len(pages), start + 6)
        found = None
        for group in groups:
            for pi in range(start, end):
                if all(k in page_texts[pi] for k in group):
                    found = pi + 1
                    break
            if found:
                break
        result[i] = found
        if found:
            last_page = found
    return result


def detect_breaks(pages_list, caption_page):
    """Индексы строк, начинающих новую страницу (начало «Продолжения»)."""
    breaks = []
    last_page = caption_page
    for i, page in enumerate(pages_list):
        if i == 0 or page is None:
            continue
        if page > last_page:
            # Разрыв имеет смысл, если до него есть хотя бы одна строка данных
            # и после него остаётся хотя бы одна строка.
            if i >= 2:
                breaks.append(i)
            last_page = page
        else:
            last_page = max(last_page, page)
    return breaks


def has_continuation_after(table, full):
    """Проверить, что сразу после таблицы уже стоит «Продолжение …»."""
    nxt = table._tbl.getnext()
    while nxt is not None and nxt.tag != qn("w:p"):
        nxt = nxt.getnext()
    if nxt is None:
        return False
    text = "".join(t.text or "" for t in nxt.iter(qn("w:t"))).strip()
    m = CONT_RE.match(text)
    return bool(m and f"{m.group('ch')}.{m.group('num')}" == full)


def set_cant_split(table):
    for row in table.rows:
        trPr = row._tr.get_or_add_trPr()
        if trPr.find(qn("w:cantSplit")) is None:
            trPr.append(OxmlElement("w:cantSplit"))


def split_table_with_continuations(doc, table, breaks, full):
    """Разрезать таблицу по индексам строк, вставив «Продолжение таблицы N.M»."""
    if not breaks:
        return 0
    tbl_el = table._tbl
    all_rows = list(tbl_el.findall(qn("w:tr")))
    n = len(all_rows)
    breaks = sorted(b for b in breaks if 1 < b < n)
    if not breaks:
        return 0

    segments = []
    start = 0
    for b in breaks + [n]:
        segments.append((start, b))
        start = b

    # Снимок полной таблицы нужен для копирования строк в новые части.
    original_rows = [copy.deepcopy(r) for r in all_rows]
    template = copy.deepcopy(tbl_el)

    # Сегмент 0 остаётся в исходной таблице.
    first_end = segments[0][1]
    for row in all_rows[first_end:]:
        tbl_el.remove(row)

    anchor = tbl_el
    added = 0
    for seg_start, seg_end in segments[1:]:
        new_tbl = copy.deepcopy(template)
        for r in list(new_tbl.findall(qn("w:tr"))):
            new_tbl.remove(r)
        # Заголовок + строки сегмента; заголовок помечаем как повторяющийся.
        keep = [original_rows[0]] + original_rows[seg_start:seg_end]
        for r in keep:
            new_tbl.append(copy.deepcopy(r))
        trs = new_tbl.findall(qn("w:tr"))
        if trs:
            trPr = trs[0].find(qn("w:trPr"))
            if trPr is None:
                trPr = OxmlElement("w:trPr")
                trs[0].insert(0, trPr)
            if trPr.find(qn("w:tblHeader")) is None:
                trPr.append(OxmlElement("w:tblHeader"))

        cap = doc.add_paragraph()
        write_continuation(cap, f"Продолжение таблицы {full}")
        cap.paragraph_format.page_break_before = True

        anchor.addnext(cap._p)
        cap._p.addnext(new_tbl)
        anchor = new_tbl
        added += 1

    # В первой части заголовок тоже должен повторяться.
    trs = tbl_el.findall(qn("w:tr"))
    if trs:
        trPr = trs[0].find(qn("w:trPr"))
        if trPr is None:
            trPr = OxmlElement("w:trPr")
            trs[0].insert(0, trPr)
        if trPr.find(qn("w:tblHeader")) is None:
            trPr.append(OxmlElement("w:tblHeader"))
    return added


# --------------------------------------------------------------------------
# Основной проход
# --------------------------------------------------------------------------
def collect(doc):
    """Собрать рисунки, таблицы, главы и статистику."""
    blocks = list(iter_blocks(doc))
    chapter = None
    last_chapter = 0
    in_appendix = False
    figures = []
    tables = []
    body_paragraphs = []

    # Параграфы-подписи рисунков: изображение + следующий параграф-подпись.
    for idx, block in enumerate(blocks):
        if not isinstance(block, Paragraph):
            continue
        text = block.text.strip()
        if is_heading1(block):
            if APPENDIX_RE.match(text):
                in_appendix = True
                continue
            ch = heading_chapter(text, last_chapter)
            if ch is not None:
                chapter = ch
                last_chapter = max(last_chapter, ch)
            else:
                chapter = None
            continue
        if in_appendix:
            continue
        body_paragraphs.append(block)
        cap = parse_caption(text)
        if cap and cap["kind"] == "fig":
            figures.append(
                {
                    "p": block,
                    "chapter": chapter if chapter is not None else cap["ch"],
                    "old": cap["full"],
                    "old_num": cap["num"],
                    "title": cap["title"],
                }
            )


    # Таблицы: подпись — ближайший непустой параграф перед таблицей.
    for idx, block in enumerate(blocks):
        if not isinstance(block, Table):
            continue
        prev_text = ""
        prev_p = None
        j = idx - 1
        while j >= 0:
            b = blocks[j]
            if isinstance(b, Paragraph) and b.text.strip():
                prev_text = b.text.strip()
                prev_p = b
                break
            j -= 1
        # глава таблицы: идём по заголовкам до этой таблицы
        ch = chapter
        # вычислим главу заново, чтобы не зависеть от порядка
        current = None
        last = 0
        app = False
        for b in blocks[:idx]:
            if isinstance(b, Paragraph) and is_heading1(b):
                t = b.text.strip()
                if APPENDIX_RE.match(t):
                    app = True
                    break
                c = heading_chapter(t, last)
                if c is not None:
                    current = c
                    last = max(last, c)
                else:
                    current = None
        if app:
            continue
        cap = parse_caption(prev_text)
        cont = is_continuation(prev_text)
        tables.append(
            {
                "tbl": block,
                "p": prev_p if cap or cont else None,
                "caption": prev_text if cap or cont else "",
                "chapter": current,
                "old": cap["full"] if cap else None,
                "old_num": cap["num"] if cap else None,
                "title": cap["title"] if cap else "",
                "continuation": cont,
                "unnamed": not (cap or cont),
                "heading": prev_text if (not cap and not cont) else "",
            }
        )
    return blocks, figures, tables, body_paragraphs


def derive_unnamed_title(table_info):
    heading = NUM_PREFIX_RE.sub("", table_info.get("heading", "")).strip()
    if not heading and table_info.get("p") is not None:
        heading = NUM_PREFIX_RE.sub("", table_info["p"].text.strip()).strip()
    if not heading:
        return "Тест-кейсы"
    # Если заголовок — это название раздела тестирования, делаем подпись.
    return f"Тест-кейсы раздела «{heading}»"


def main():
    ap = argparse.ArgumentParser(description="Исправление подписей рисунков и таблиц")
    ap.add_argument("input", help="входной .docx")
    ap.add_argument("output", help="выходной .docx")
    ap.add_argument(
        "--safe",
        action="store_true",
        help="только форматирование подписей и шрифтов, без перенумерации",
    )
    ap.add_argument(
        "--no-continuation",
        action="store_true",
        help="не добавлять «Продолжение таблицы N.M»",
    )
    ap.add_argument(
        "--json-report",
        help="куда сохранить машинный отчёт (JSON)",
    )
    args = ap.parse_args()

    doc = docx.Document(args.input)
    blocks, figures, tables, body_paragraphs = collect(doc)

    report = {
        "input": args.input,
        "output": args.output,
        "safe": args.safe,
        "figures": [],
        "tables": [],
        "references": [],
        "warnings": [],
    }

    # --- статистика шрифтов таблиц до правки ---
    before_stats = {}
    for i, t in enumerate(tables):
        if t["continuation"]:
            continue
        if t["tbl"] is not None:
            st = table_font_stats(t["tbl"])
            if st:
                before_stats[i] = {f"{k[0]} {k[1]}": v for k, v in st.items()}
    report["table_fonts_before"] = before_stats

    # --- перенумерация ---
    fig_maps = {}
    tab_maps = {}
    if not args.safe:
        by_ch = {}
        for f in figures:
            by_ch.setdefault(f["chapter"], []).append(f)
        for ch, items in by_ch.items():
            for n, f in enumerate(items, 1):
                f["new"] = f"{ch}.{n}"
                fig_maps[f["old"]] = f["new"]
        by_ch = {}
        for t in tables:
            if t["continuation"]:
                continue
            if t["chapter"] is None:
                continue
            by_ch.setdefault(t["chapter"], []).append(t)
        for ch, items in by_ch.items():
            for n, t in enumerate(items, 1):
                t["new"] = f"{ch}.{n}"
                if t["old"]:
                    tab_maps[t["old"]] = t["new"]
    else:
        for f in figures:
            f["new"] = f["old"]
        for t in tables:
            t["new"] = t["old"] or ""
        for old in {t["old"] for t in tables if t["old"]}:
            tab_maps[old] = old
        unnamed = [t for t in tables if t["unnamed"]]
        if unnamed:
            report["warnings"].append(
                "Безопасный режим: %d таблиц без названия оставлены без подписи "
                "(нужна ручная нумерация)" % len(unnamed)
            )

    # --- подписи рисунков ---
    for f in figures:
        old_text = f["p"].text.strip()
        title = f["title"] or "Название рисунка"
        new_text = f"Рисунок {f['new']}. {title}"
        if old_text != new_text or args.safe:
            # в safe-режиме всё равно правим формат, но номер не меняем
            if args.safe:
                new_text = f"Рисунок {f['old']}. {title}"
            write_caption(f["p"], new_text, "fig")
        else:
            # формат мог быть верным текстом, но неверным шрифтом
            write_caption(f["p"], new_text, "fig")
        report["figures"].append(
            {
                "old": f["old"],
                "new": f["new"] if not args.safe else f["old"],
                "title": title,
                "paragraph": old_text,
            }
        )

    # --- подписи таблиц ---
    for t in tables:
        if t["continuation"]:
            if t["p"] is not None:
                m = CONT_RE.match(t["p"].text)
                if m:
                    write_continuation(
                        t["p"],
                        f"Продолжение таблицы {m.group('ch')}.{m.group('num')}",
                    )
            continue
        if t["chapter"] is None:
            report["warnings"].append(
                f"Таблица без главы: «{t['caption'] or t['heading']}» — пропущена"
            )
            continue
        if args.safe and not t["old"]:
            # В безопасном режиме названия не придумываем.
            continue
        if t["old"]:
            title = t["title"] or "Название таблицы"
        else:
            title = derive_unnamed_title(t)
        new_num = t["new"]
        new_text = f"Таблица {new_num}. {title}"
        if t["p"] is None:
            # вставить подпись перед таблицей
            p = doc.add_paragraph()
            t["tbl"]._tbl.addprevious(p._p)
            t["p"] = p
        write_caption(t["p"], new_text, "tab")
        report["tables"].append(
            {
                "old": t["old"],
                "new": new_num,
                "title": title,
                "unnamed": t["unnamed"],
                "chapter": t["chapter"],
                "split": None,
            }
        )

    # --- ссылки в тексте ---
    if not args.safe:
        caption_paras = {id(f["p"]._p) for f in figures}
        caption_paras |= {id(t["p"]._p) for t in tables if t["p"] is not None}
        ref_paragraphs = [
            p
            for p in body_paragraphs
            if id(p._p) not in caption_paras and not is_continuation(p.text)
        ]
        report["references"] = replace_references(
            ref_paragraphs, tab_maps, fig_maps
        )

    # --- какие рисунки/таблицы упомянуты в основном тексте ---
    referenced = {"fig": set(), "tab": set()}
    range_re = re.compile(
        r"(?P<kind>рисун\w*|таблиц\w*)\s+(?P<a>\d+)\.(?P<b>\d+)"
        r"\s*[–—]\s*(?P<c>\d+)\.(?P<d>\d+)",
        re.I,
    )
    for p in body_paragraphs:
        text = p.text
        if parse_caption(text) or is_continuation(text):
            continue
        for m in REF_RE.finditer(text):
            kind = "fig" if m.group("kind").lower().startswith("рисун") else "tab"
            referenced[kind].add(f"{int(m.group('ch'))}.{int(m.group('num'))}")
        for m in range_re.finditer(text):
            kind = "fig" if m.group("kind").lower().startswith("рисун") else "tab"
            ch, a, c = int(m.group("a")), int(m.group("b")), int(m.group("d"))
            for n in range(a, c + 1):
                referenced[kind].add(f"{ch}.{n}")

    for item in report["figures"]:
        item["referenced"] = item["new"] in referenced["fig"]
    for item in report["tables"]:
        item["referenced"] = item["new"] in referenced["tab"]

    # --- шрифт таблиц ---
    for t in tables:
        set_table_fonts(t["tbl"])
        # Запрещаем разрыв строки между страницами: тогда разрыв таблицы
        # всегда проходит по границе строк, и «Продолжение» можно поставить
        # однозначно.
        set_cant_split(t["tbl"])

    # --- продолжения таблиц ---
    # Разрез меняет разбиение на страницы, поэтому после каждого разреза
    # документ заново конвертируется и проверка повторяется, пока разрывов
    # не останется. Так гарантируется корректность и идемпотентность.
    if not args.safe and not args.no_continuation:
        with tempfile.TemporaryDirectory(prefix="r11_cont_") as tmp:
            tmp = Path(tmp)
            mid = tmp / "mid.docx"
            split_info = {}
            for _pass in range(20):
                doc.save(mid)
                pdf, err = convert_to_pdf(mid, tmp)
                if err:
                    report["warnings"].append(
                        "Определение разрывов таблиц недоступно: " + err
                    )
                    break
                pages, err = pdf_pages_text(pdf)
                if err:
                    report["warnings"].append(
                        "Определение разрывов таблиц недоступно: " + err
                    )
                    break
                blocks2, _figs2, tabs2, _body2 = collect(doc)
                found = False
                for t in tabs2:
                    if t["continuation"]:
                        m = CONT_RE.match(t["caption"])
                        if not m:
                            continue
                        full = f"{m.group('ch')}.{m.group('num')}"
                        prefix = "Продолжение таблицы"
                    elif t["old"]:
                        full = t["old"]
                        prefix = "Таблица"
                    else:
                        continue
                    if t["chapter"] is None:
                        continue
                    cap_page = find_caption_page(pages, full, prefix)
                    if cap_page is None:
                        continue
                    rp = row_pages(t["tbl"], pages, cap_page)
                    breaks = detect_breaks(rp, cap_page)
                    if not breaks:
                        continue
                    added = split_table_with_continuations(
                        doc, t["tbl"], breaks, full
                    )
                    set_cant_split(t["tbl"])
                    info = split_info.setdefault(
                        full, {"pages": set(), "breaks": [], "added": 0}
                    )
                    info["pages"].update(p for p in rp if p is not None)
                    info["breaks"].extend(breaks)
                    info["added"] += added
                    found = True
                    # После разреза разбиение на страницы изменилось —
                    # пересобираем PDF и начинаем проверку заново.
                    break
                if not found:
                    break
            for item in report["tables"]:
                info = split_info.get(item["new"])
                if info:
                    item["split"] = {
                        "pages": sorted(info["pages"]),
                        "breaks": info["breaks"],
                        "continuations_added": info["added"],
                    }
    # --- сохранение ---
    doc.save(args.output)

    # --- отчёт ---
    if args.json_report:
        Path(args.json_report).write_text(
            json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
        )
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
