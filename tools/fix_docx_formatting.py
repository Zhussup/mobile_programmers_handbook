#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Автоисправление оформления курсовой работы ПМ07 (DOCX).

Скрипт приводит документ к требованиям методички (разделы 3.1–3.2)
и реестра КР_2_2 (О1–О9, О13–О14):

* А4, поля 30 / 20 / 10 / 20 мм;
* Normal: Times New Roman 14 пт, интервал 1,5, по ширине, отступ 1,25 см;
* основной текст без полужирного и подчёркивания;
* заголовки: по центру, TNR 14, без полужирного/подчёркивания,
  без точки после номера и в конце;
* пустая строка между заголовком раздела и подраздела;
* каждый основной раздел — с новой страницы;
* нумерация страниц внизу по центру, начиная с «ВВЕДЕНИЯ»;
  титул и содержание входят в нумерацию, но номер на них не печатается.

Скрипт идемпотентен: повторный запуск на уже исправленном файле не
создаёт новых разрывов секций, пустых строк и т. п.

Использование:
    python3 tools/fix_docx_formatting.py input.docx [output.docx]

Если output не указан, результат сохраняется рядом с исходником как
``<имя>_formatted.docx``. Перезапись исходного файла запрещена без --force.

Зависимости: python-docx (>= 1.0).
"""

from __future__ import annotations

import argparse
import copy
import re
import sys
from pathlib import Path

import docx
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Pt
from docx.text.paragraph import Paragraph

FONT_NAME = "Times New Roman"
FONT_SIZE = Pt(14)

# Шрифты, которыми набраны листинги кода. Их не переводим в TNR,
# чтобы не разрушить выравнивание ASCII-схем и подсветку.
MONO_FONTS = {
    "courier new",
    "consolas",
    "menlo",
    "monaco",
    "pt mono",
    "source code pro",
    "monospace",
}

# Структурные заголовки, которые могут быть оформлены стилем Normal.
STRUCTURAL_HEADINGS = {
    "СОДЕРЖАНИЕ",
    "ВВЕДЕНИЕ",
    "ЗАКЛЮЧЕНИЕ",
    "СПИСОК ЛИТЕРАТУРЫ",
    "СПИСОК ИСПОЛЬЗОВАННОЙ ЛИТЕРАТУРЫ",
    "СПИСОК ИСПОЛЬЗОВАННЫХ ИСТОЧНИКОВ",
}

CAPTION_RE = re.compile(r"^(Рисунок|Таблица)\s+\d+", re.IGNORECASE)
NUMBERED_HEADING_RE = re.compile(r"^(\d+(?:\.\d+)*)\.(?=\s|$)")

stats: dict[str, int] = {
    "headings": 0,
    "headings_renumbered": 0,
    "body_paragraphs": 0,
    "code_paragraphs": 0,
    "caption_paragraphs": 0,
    "table_paragraphs": 0,
    "blank_lines_inserted": 0,
    "bold_runs_removed": 0,
    "underline_runs_removed": 0,
    "sections_before": 0,
    "sections_after": 0,
}


# ---------------------------------------------------------------------------
# Вспомогательные функции
# ---------------------------------------------------------------------------


def log(message: str, quiet: bool = False) -> None:
    if not quiet:
        print(message)


def _iter_runs(paragraph: Paragraph):
    """Все run-элементы абзаца, включая вложенные в гиперссылки."""
    return list(paragraph.runs)


def _is_mono_run(run) -> bool:
    name = (run.font.name or "").strip().lower()
    return name in MONO_FONTS


def _set_run_font(run, name: str = FONT_NAME, size=FONT_SIZE) -> None:
    """Задать шрифт/кегль run и явно прописать rFonts во всех слотах."""
    run.font.name = name
    run.font.size = size
    rpr = run._element.get_or_add_rPr()
    rfonts = rpr.find(qn("w:rFonts"))
    if rfonts is None:
        rfonts = OxmlElement("w:rFonts")
        rpr.insert(0, rfonts)
    for attr in ("w:ascii", "w:hAnsi", "w:eastAsia", "w:cs"):
        rfonts.set(qn(attr), name)
    # Тематические шрифты могут перекрывать явный rFonts — убираем их.
    for attr in ("w:asciiTheme", "w:hAnsiTheme", "w:eastAsiaTheme", "w:cstheme"):
        if rfonts.get(qn(attr)) is not None:
            del rfonts.attrib[qn(attr)]


def _set_style_font(style, name: str = FONT_NAME, size=FONT_SIZE) -> None:
    style.font.name = name
    style.font.size = size
    rpr = style.element.get_or_add_rPr()
    rfonts = rpr.find(qn("w:rFonts"))
    if rfonts is None:
        rfonts = OxmlElement("w:rFonts")
        rpr.insert(0, rfonts)
    for attr in ("w:ascii", "w:hAnsi", "w:eastAsia", "w:cs"):
        rfonts.set(qn(attr), name)
    for attr in ("w:asciiTheme", "w:hAnsiTheme", "w:eastAsiaTheme", "w:cstheme"):
        if rfonts.get(qn(attr)) is not None:
            del rfonts.attrib[qn(attr)]


def _remove_bold_underline(paragraph: Paragraph) -> None:
    for run in _iter_runs(paragraph):
        if run.bold:
            stats["bold_runs_removed"] += 1
        if run.underline:
            stats["underline_runs_removed"] += 1
        run.bold = False
        run.underline = False


def _has_toc_field(paragraph: Paragraph) -> bool:
    for instr in paragraph._p.findall(".//" + qn("w:instrText")):
        if "TOC" in (instr.text or "").upper():
            return True
    return False


def _is_toc_placeholder(paragraph: Paragraph) -> bool:
    text = paragraph.text.strip().lower()
    return _has_toc_field(paragraph) or text.startswith("содержание обновится")


def _is_caption(paragraph: Paragraph) -> bool:
    return bool(CAPTION_RE.match(paragraph.text.strip()))


def _is_code_paragraph(paragraph: Paragraph) -> bool:
    """Листинг кода, а не абзац с внутристрочной вставкой кода.

    Листингом считаем абзац, в котором *все* непустые run моноширинные,
    либо абзац с псевдографикой дерева каталогов.
    """
    runs = [run for run in _iter_runs(paragraph) if run.text.strip()]
    if runs and all(_is_mono_run(run) for run in runs):
        return True
    return bool(re.search(r"[├└│]", paragraph.text))


def _is_structural_heading(paragraph: Paragraph) -> bool:
    """Структурный заголовок набран прописными («СПИСОК ЛИТЕРАТУРЫ»)."""
    raw = paragraph.text.strip()
    if not raw or raw != raw.upper():
        # «Приложение разработано на Flutter…» — это обычный текст, не заголовок.
        return False
    if raw in STRUCTURAL_HEADINGS:
        return True
    if raw.startswith("СПИСОК ") and len(raw) <= 120:
        return True
    return bool(re.match(r"^ПРИЛОЖЕНИЯ?(?:\s+[А-ЯЁA-Z]\.?)(?:\s|$)", raw))


def _is_heading(paragraph: Paragraph) -> bool:
    return paragraph.style.name.startswith("Heading") or _is_structural_heading(paragraph)


def _is_heading_level(paragraph: Paragraph, level: int) -> bool:
    return paragraph.style.name == f"Heading {level}"


def _clean_heading_text(text: str) -> str:
    """Убрать точку после номера и точку в конце заголовка."""
    result = text.strip()
    # Точка в конце не ставится (многоточие не трогаем).
    while result.endswith(".") and not result.endswith(".."):
        result = result[:-1].rstrip()
    # «1.1. Название» -> «1.1 Название», «1.1.» -> «1.1».
    result = NUMBERED_HEADING_RE.sub(r"\1", result)
    return result


def _replace_paragraph_text(paragraph: Paragraph, new_text: str) -> None:
    """Заменить текст абзаца, сохранив rPr первого run."""
    first_rpr = None
    if paragraph.runs and paragraph.runs[0]._r.rPr is not None:
        first_rpr = copy.deepcopy(paragraph.runs[0]._r.rPr)
    for run in list(paragraph.runs):
        run._r.getparent().remove(run._r)
    new_run = paragraph.add_run(new_text)
    if first_rpr is not None:
        new_run._r.insert(0, first_rpr)


# ---------------------------------------------------------------------------
# Оформление
# ---------------------------------------------------------------------------


def setup_page(doc) -> None:
    """А4 и поля 30 / 20 / 10 / 20 мм для всех секций."""
    for section in doc.sections:
        section.page_width = Cm(21)
        section.page_height = Cm(29.7)
        section.left_margin = Cm(3.0)
        section.top_margin = Cm(2.0)
        section.right_margin = Cm(1.0)
        section.bottom_margin = Cm(2.0)
        section.gutter = Cm(0)


def setup_styles(doc) -> None:
    """Настроить Normal и Heading 1–3 согласно методичке."""
    normal = doc.styles["Normal"]
    _set_style_font(normal)
    normal.font.bold = False
    normal.font.underline = False
    pf = normal.paragraph_format
    pf.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    pf.line_spacing = 1.5
    pf.first_line_indent = Cm(1.25)

    for level in (1, 2, 3):
        try:
            style = doc.styles[f"Heading {level}"]
        except KeyError:
            continue
        _set_style_font(style)
        style.font.bold = False
        style.font.underline = False
        spf = style.paragraph_format
        spf.alignment = WD_ALIGN_PARAGRAPH.CENTER
        spf.line_spacing = 1.5
        spf.first_line_indent = Cm(1.25)
        spf.keep_with_next = True


def format_heading(paragraph: Paragraph) -> None:
    stats["headings"] += 1

    cleaned = _clean_heading_text(paragraph.text)
    if cleaned != paragraph.text.strip():
        _replace_paragraph_text(paragraph, cleaned)
        stats["headings_renumbered"] += 1

    pf = paragraph.paragraph_format
    pf.alignment = WD_ALIGN_PARAGRAPH.CENTER
    pf.line_spacing = 1.5
    pf.first_line_indent = Cm(1.25)
    pf.keep_with_next = True

    _remove_bold_underline(paragraph)
    for run in _iter_runs(paragraph):
        _set_run_font(run)


def format_body_paragraph(paragraph: Paragraph) -> None:
    stats["body_paragraphs"] += 1
    pf = paragraph.paragraph_format
    pf.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    pf.line_spacing = 1.5
    pf.first_line_indent = Cm(1.25)
    _remove_bold_underline(paragraph)
    for run in _iter_runs(paragraph):
        # Внутрикодовые вставки сохраняют моноширинный шрифт.
        if not _is_mono_run(run):
            _set_run_font(run)


def format_code_paragraph(paragraph: Paragraph) -> None:
    stats["code_paragraphs"] += 1
    pf = paragraph.paragraph_format
    pf.alignment = WD_ALIGN_PARAGRAPH.LEFT
    pf.line_spacing = 1.0
    pf.first_line_indent = Cm(0)
    _remove_bold_underline(paragraph)


def format_caption(paragraph: Paragraph) -> None:
    """Подписи рисунков/таблиц оформляет R11; здесь только снимаем bold."""
    stats["caption_paragraphs"] += 1
    # Не даём унаследовать новый абзацный отступ Normal.
    paragraph.paragraph_format.first_line_indent = Cm(0)
    _remove_bold_underline(paragraph)


def format_tables(doc) -> None:
    """Убрать bold/подчёркивание в таблицах, не меняя их шрифт (это R11)."""
    for table in doc.tables:
        for row in table.rows:
            for cell in row.cells:
                for paragraph in cell.paragraphs:
                    if not paragraph.text.strip():
                        continue
                    stats["table_paragraphs"] += 1
                    pf = paragraph.paragraph_format
                    pf.first_line_indent = Cm(0)
                    pf.line_spacing = 1.0
                    _remove_bold_underline(paragraph)


def apply_page_breaks(doc) -> None:
    """Каждый основной раздел начинается с новой страницы.

    Новую страницу получают только главы/структурные элементы
    (Heading 1), но не подразделы Heading 2–3.
    """
    for paragraph in doc.paragraphs:
        if paragraph.style.name == "Heading 1" or _is_structural_heading(paragraph):
            paragraph.paragraph_format.page_break_before = True


def _next_body_paragraph_element(element):
    """Следующий w:p на уровне body (таблицы и sectPr пропускаем)."""
    nxt = element.getnext()
    while nxt is not None:
        if nxt.tag == qn("w:p"):
            return nxt
        if nxt.tag == qn("w:tbl"):
            return None
        nxt = nxt.getnext()
    return None


def _add_blank_paragraph_after(paragraph: Paragraph) -> None:
    blank = OxmlElement("w:p")
    ppr = OxmlElement("w:pPr")
    pstyle = OxmlElement("w:pStyle")
    pstyle.set(qn("w:val"), "Normal")
    ppr.append(pstyle)
    blank.append(ppr)
    paragraph._p.addnext(blank)
    stats["blank_lines_inserted"] += 1


def ensure_blank_lines_between_headings(doc) -> None:
    """Одна пустая строка между заголовком раздела и подраздела."""
    for paragraph in list(doc.paragraphs):
        if not _is_heading(paragraph):
            continue
        level = 1 if paragraph.style.name == "Heading 1" else (
            2 if paragraph.style.name == "Heading 2" else None
        )
        if level is None:
            continue
        next_el = _next_body_paragraph_element(paragraph._p)
        if next_el is None:
            continue
        nxt = Paragraph(next_el, paragraph._parent)
        expected = f"Heading {level + 1}"
        if nxt.style.name != expected:
            continue
        if not nxt.text.strip():  # пустая строка уже есть
            continue
        _add_blank_paragraph_after(paragraph)


# ---------------------------------------------------------------------------
# Нумерация страниц
# ---------------------------------------------------------------------------


def _find_intro_paragraph(doc):
    for paragraph in doc.paragraphs:
        if paragraph.text.strip().upper() == "ВВЕДЕНИЕ":
            return paragraph
    return None


def _count_sections_before(body, target_element) -> int:
    """Сколько sectPr расположено в body до указанного элемента."""
    count = 0
    for element in body.iterchildren():
        if element is target_element:
            break
        if element.tag == qn("w:p"):
            ppr = element.find(qn("w:pPr"))
            if ppr is not None and ppr.find(qn("w:sectPr")) is not None:
                count += 1
        elif element.tag == qn("w:sectPr"):
            count += 1
    return count


def _strip_section_props(section_el) -> None:
    for tag in ("w:titlePg", "w:pgNumType"):
        for element in section_el.findall(qn(tag)):
            section_el.remove(element)


def _remove_footer_references(section_el) -> None:
    for element in section_el.findall(qn("w:footerReference")):
        section_el.remove(element)


def _append_page_field(paragraph: Paragraph) -> None:
    def styled_run():
        run = paragraph.add_run()
        _set_run_font(run)
        run.bold = False
        run.underline = False
        return run

    run_begin = styled_run()
    begin = OxmlElement("w:fldChar")
    begin.set(qn("w:fldCharType"), "begin")
    instr = OxmlElement("w:instrText")
    instr.set(qn("xml:space"), "preserve")
    instr.text = " PAGE "
    run_begin._r.append(begin)
    run_begin._r.append(instr)

    run_end = styled_run()
    separate = OxmlElement("w:fldChar")
    separate.set(qn("w:fldCharType"), "separate")
    text = OxmlElement("w:t")
    text.text = "1"  # кэшированное значение, Word/LibreOffice пересчитают
    finish = OxmlElement("w:fldChar")
    finish.set(qn("w:fldCharType"), "end")
    run_end._r.append(separate)
    run_end._r.append(text)
    run_end._r.append(finish)


def _write_page_footer(section) -> None:
    footer = section.footer
    footer.is_linked_to_previous = False
    # Полностью очищаем колонтитул (могут остаться абзацы/таблицы).
    for child in list(footer._element):
        if child.tag in (qn("w:p"), qn("w:tbl")):
            footer._element.remove(child)

    paragraph = footer.add_paragraph()
    try:
        paragraph.style = "Footer"
    except KeyError:
        pass
    paragraph.alignment = WD_ALIGN_PARAGRAPH.CENTER
    paragraph.paragraph_format.first_line_indent = Cm(0)
    paragraph.paragraph_format.line_spacing = 1.0
    _append_page_field(paragraph)


def setup_page_numbering(doc, quiet: bool = False) -> None:
    """Разорвать секцию перед «ВВЕДЕНИЕМ» и включить PAGE в нижнем колонтитуле."""
    intro = _find_intro_paragraph(doc)
    if intro is None:
        log("  ! «ВВЕДЕНИЕ» не найдено — нумерация страниц не настроена.", quiet)
        return

    body = doc.element.body
    prev = intro._p.getprevious()
    while prev is not None and prev.tag != qn("w:p"):
        prev = prev.getprevious()
    if prev is None:
        log("  ! Перед «ВВЕДЕНИЕМ» нет абзаца — разрыв секции не создан.", quiet)
        return

    prev_ppr = prev.find(qn("w:pPr"))
    already_split = prev_ppr is not None and prev_ppr.find(qn("w:sectPr")) is not None

    if not already_split:
        body_sect = body.find(qn("w:sectPr"))
        if body_sect is None:
            log("  ! В документе нет sectPr — нумерация не настроена.", quiet)
            return
        new_sect = copy.deepcopy(body_sect)
        _remove_footer_references(new_sect)
        for tag in ("w:headerReference", "w:titlePg", "w:pgNumType"):
            for element in new_sect.findall(qn(tag)):
                new_sect.remove(element)
        if prev_ppr is None:
            prev_ppr = OxmlElement("w:pPr")
            prev.insert(0, prev_ppr)
        prev_ppr.append(new_sect)
        log("  + создан разрыв секции перед «ВВЕДЕНИЕМ» "
            "(титул и содержание — без номера).", quiet)

    # Все секции: убираем titlePg и принудительный старт нумерации.
    for section in doc.sections:
        _strip_section_props(section._sectPr)

    intro_section_index = _count_sections_before(body, intro._p)
    intro_section_index = max(0, min(intro_section_index, len(doc.sections) - 1))

    # Секции до «Введения» (титул, содержание) — без колонтитула.
    for section in doc.sections[:intro_section_index]:
        _remove_footer_references(section._sectPr)

    # Секция «Введение» и далее — номер страницы внизу по центру.
    for section in doc.sections[intro_section_index:]:
        _write_page_footer(section)

    log(f"  + нумерация: PAGE внизу по центру с секции №{intro_section_index + 1} "
        f"(«ВВЕДЕНИЕ»), всего секций {len(doc.sections)}.", quiet)


# ---------------------------------------------------------------------------
# Основной проход
# ---------------------------------------------------------------------------


def fix_document(doc, quiet: bool = False) -> None:
    stats["sections_before"] = len(doc.sections)

    paragraphs = list(doc.paragraphs)

    # Граница титульного листа — первый структурный заголовок «СОДЕРЖАНИЕ».
    content_index = next(
        (i for i, p in enumerate(paragraphs)
         if p.text.strip().upper() == "СОДЕРЖАНИЕ"),
        None,
    )
    if content_index is None:
        content_index = next(
            (i for i, p in enumerate(paragraphs) if _is_heading(p)), 0
        )

    setup_styles(doc)
    setup_page_numbering(doc, quiet=quiet)
    setup_page(doc)

    for index, paragraph in enumerate(paragraphs):
        # Титульный лист не переоформляем (у него собственный макет).
        if index < content_index:
            paragraph.paragraph_format.first_line_indent = Cm(0)
            continue

        if _is_toc_placeholder(paragraph):
            # Поле TOC собирает R1; здесь только не даём унаследовать отступ.
            paragraph.paragraph_format.first_line_indent = Cm(0)
            _remove_bold_underline(paragraph)
            continue

        if _is_heading(paragraph):
            format_heading(paragraph)
            continue

        if _is_caption(paragraph):
            format_caption(paragraph)
            continue

        if _is_code_paragraph(paragraph):
            format_code_paragraph(paragraph)
            continue

        if not paragraph.text.strip():
            # Пустые абзацы-разделители: достаточно стиля Normal.
            continue

        format_body_paragraph(paragraph)

    format_tables(doc)
    ensure_blank_lines_between_headings(doc)
    apply_page_breaks(doc)

    stats["sections_after"] = len(doc.sections)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Автоисправление оформления DOCX курсовой работы ПМ07."
    )
    parser.add_argument("input", help="исходный .docx")
    parser.add_argument(
        "output",
        nargs="?",
        help="куда сохранить результат (по умолчанию <имя>_formatted.docx)",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="разрешить перезапись исходного файла",
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="не печатать ход работы",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)

    input_path = Path(args.input).expanduser().resolve()
    if not input_path.is_file():
        print(f"Ошибка: файл не найден: {input_path}", file=sys.stderr)
        return 2
    if input_path.suffix.lower() != ".docx":
        print("Ошибка: поддерживаются только файлы .docx", file=sys.stderr)
        return 2

    if args.output:
        output_path = Path(args.output).expanduser().resolve()
    else:
        output_path = input_path.with_name(f"{input_path.stem}_formatted.docx")

    if output_path == input_path and not args.force:
        print(
            "Ошибка: выходной файл совпадает с исходным. "
            "Укажите другой путь или --force (перезапись оригинала).",
            file=sys.stderr,
        )
        return 2

    output_path.parent.mkdir(parents=True, exist_ok=True)

    log(f"Исходник: {input_path}")
    log(f"Результат: {output_path}")

    document = docx.Document(str(input_path))
    fix_document(document, quiet=args.quiet)
    document.save(str(output_path))

    log("")
    log("Готово:")
    log(f"  заголовков обработано:            {stats['headings']}")
    log(f"  заголовков с исправленной нумерацией: {stats['headings_renumbered']}")
    log(f"  абзацев основного текста:         {stats['body_paragraphs']}")
    log(f"  листингов кода (сохранён моношрифт): {stats['code_paragraphs']}")
    log(f"  подписей рисунков/таблиц:         {stats['caption_paragraphs']}")
    log(f"  абзацев в таблицах:               {stats['table_paragraphs']}")
    log(f"  вставлено пустых строк:           {stats['blank_lines_inserted']}")
    log(f"  снято полужирных run:             {stats['bold_runs_removed']}")
    log(f"  снято подчёркнутых run:           {stats['underline_runs_removed']}")
    log(f"  секций было / стало:              "
        f"{stats['sections_before']} / {stats['sections_after']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
