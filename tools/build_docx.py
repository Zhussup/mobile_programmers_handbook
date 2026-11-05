"""Сборка пояснительной записки КР_2_2 из Markdown-разделов агентов.

Запуск:
    python3 tools/build_docx.py

Что делает:
1. Читает разделы R02–R09 из docs/kr22/.
2. Собирает единый Markdown в порядке методички.
3. Конвертирует SVG-схемы в PNG (ImageMagick).
4. Прогоняет pandoc с docs/kr22/reference.docx.
5. Добавляет титульный лист, поле оглавления, разрыв секции,
   нумерацию страниц, убирает полужирный из основного текста,
   ставит TNR 12 в таблицах.

Результат: docs/kr22/Пояснительная_записка_КР2_2.docx
"""
from __future__ import annotations

import re
import shutil
import subprocess
import sys
from pathlib import Path

from docx import Document
from docx.enum.section import WD_SECTION
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Pt

ROOT = Path(__file__).resolve().parent.parent
KR = ROOT / "docs" / "kr22"
OUT = KR / "Пояснительная_записка_КР2_2.docx"
MD = KR / "_assembled.md"

SECTIONS = [
    ("R02_intro_conclusion.md", "intro"),
    ("R03_theory.md", "all"),
    ("R04_architecture.md", "all"),
    ("R05_database.md", "all"),
    ("R06_api.md", "all"),
    ("R07_functionality.md", "all"),
    ("R08_practical.md", "all"),
    ("R02_intro_conclusion.md", "conclusion"),
    ("R09_literature_final.md", "all"),
    ("APPENDIX_A.md", "all"),
    ("APPENDIX_B.md", "all"),
    ("APPENDIX_V.md", "all"),
    ("APPENDIX_G.md", "all"),
]

TITLE_LINES = [
    ("Колледж ТОО «Astana IT University»", "center"),
    ("Цикловая комиссия «Специальные дисциплины»", "center"),
    ("", "center"),
    ("", "center"),
    ("КУРСОВОЙ ПРОЕКТ", "center"),
    ("", "center"),
    ("06130100 «Программное обеспечение (по видам)»", "center"),
    ("", "center"),
    ("«Мобильный справочник программиста с интерактивными примерами кода", "center"),
    ("и административной web-панелью»", "center"),
    ("", "center"),
    ("", "center"),
    ("Выполнил(а): студент(ка) группы ________ _______________________________", "left"),
    ("Преподаватели: Тілеулес Д.Н., Темірке С.Ф.", "left"),
    ("", "center"),
    ("", "center"),
    ("Астана 2026 г.", "center"),
]


def read_text(name: str) -> str:
    path = KR / name
    if not path.exists():
        raise FileNotFoundError(f"нет файла {path}")
    text = path.read_text(encoding="utf-8")
    # YAML front matter
    if text.startswith("---"):
        parts = text.split("---", 2)
        if len(parts) == 3:
            text = parts[2]
    return text.strip() + "\n"


def split_intro_conclusion(text: str) -> tuple[str, str]:
    marker = re.search(r"^#\s+ЗАКЛЮЧЕНИЕ\s*$", text, re.M)
    if not marker:
        raise ValueError("в R02 не найден заголовок '# ЗАКЛЮЧЕНИЕ'")
    return text[: marker.start()].rstrip() + "\n", text[marker.start():].strip() + "\n"


def normalize(text: str) -> str:
    # Убираем служебные заголовки вида "# R01. ..." и "**Агент:** R1".
    text = re.sub(r"^#\s+R\d+\.?.*\n", "", text, flags=re.M)
    lines = []
    for line in text.splitlines():
        if re.match(r"^\*\*(Агент|Требования|Источники|Дата|Статус):\*\*", line):
            continue
        if line.strip() == "---":
            continue
        lines.append(line)
    text = "\n".join(lines)
    # Точки после номеров разделов: "## 1.1." -> "## 1.1"
    text = re.sub(r"^(#{1,3}\s+\d+(?:\.\d+)*)\.\s+", r"\1 ", text, flags=re.M)
    # Уровни: "## 2.4.1." -> "### 2.4.1"
    text = re.sub(r"^##\s+(\d+\.\d+\.\d+)\s+", r"### \1 ", text, flags=re.M)
    return text.strip() + "\n"


def convert_svgs() -> None:
    for svg in KR.rglob("*.svg"):
        png = svg.with_suffix(".png")
        if png.exists() and png.stat().st_mtime >= svg.stat().st_mtime:
            continue
        try:
            subprocess.run(
                ["convert", "-background", "white", "-density", "180", str(svg), str(png)],
                check=True,
                capture_output=True,
            )
            print(f"svg -> png: {svg.name}")
        except Exception as exc:  # noqa: BLE001
            print(f"WARN: не удалось конвертировать {svg}: {exc}", file=sys.stderr)


def collect_markdown() -> str:
    intro, conclusion = split_intro_conclusion(read_text("R02_intro_conclusion.md"))
    parts = [normalize(intro)]
    for name, mode in SECTIONS[1:]:
        if mode == "conclusion":
            parts.append(normalize(conclusion))
            continue
        if name == "R02_intro_conclusion.md":
            continue
        parts.append(normalize(read_text(name)))
    body = "\n\n".join(p.strip() for p in parts if p.strip()) + "\n"
    # SVG -> PNG в ссылках на изображения (pandoc не читает SVG без rsvg).
    body = re.sub(r"(!\[[^\]]*\]\()([^)]+)\.svg(\))",
                  lambda m: m.group(1) + m.group(2) + ".png" + m.group(3), body)
    return body


def add_page_number_footer(section) -> None:
    footer = section.footer
    footer.is_linked_to_previous = False
    p = footer.paragraphs[0] if footer.paragraphs else footer.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    for run in list(p.runs):
        run._element.getparent().remove(run._element)
    run = p.add_run()
    fld_begin = OxmlElement("w:fldChar")
    fld_begin.set(qn("w:fldCharType"), "begin")
    instr = OxmlElement("w:instrText")
    instr.set(qn("xml:space"), "preserve")
    instr.text = " PAGE "
    fld_sep = OxmlElement("w:fldChar")
    fld_sep.set(qn("w:fldCharType"), "separate")
    placeholder = OxmlElement("w:t")
    placeholder.text = "3"
    fld_end = OxmlElement("w:fldChar")
    fld_end.set(qn("w:fldCharType"), "end")
    run._r.append(fld_begin)
    run._r.append(instr)
    run._r.append(fld_sep)
    run._r.append(placeholder)
    run._r.append(fld_end)


def add_title_page(doc: Document) -> None:
    for text, align in TITLE_LINES:
        p = doc.add_paragraph()
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER if align == "center" else WD_ALIGN_PARAGRAPH.LEFT
        p.paragraph_format.first_line_indent = Cm(0)
        p.paragraph_format.line_spacing = 1.5
        p.paragraph_format.space_after = Pt(0)
        r = p.add_run(text)
        r.font.name = "Times New Roman"
        r.font.size = Pt(14)
        r.font.bold = False
        r.font.underline = False


def add_toc(doc: Document) -> None:
    heading = doc.add_paragraph(style="TOC Heading")
    heading.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = heading.add_run("СОДЕРЖАНИЕ")
    run.font.name = "Times New Roman"
    run.font.size = Pt(14)
    run.font.bold = False

    p = doc.add_paragraph()
    p.paragraph_format.first_line_indent = Cm(0)
    run = p.add_run()
    fld_begin = OxmlElement("w:fldChar")
    fld_begin.set(qn("w:fldCharType"), "begin")
    instr = OxmlElement("w:instrText")
    instr.set(qn("xml:space"), "preserve")
    instr.text = ' TOC \\o "1-2" \\h \\z \\u '
    fld_sep = OxmlElement("w:fldChar")
    fld_sep.set(qn("w:fldCharType"), "separate")
    placeholder = OxmlElement("w:t")
    placeholder.text = "Обновите оглавление: Ctrl+A → F9 → «Обновить целиком»"
    fld_end = OxmlElement("w:fldChar")
    fld_end.set(qn("w:fldCharType"), "end")
    run._r.append(fld_begin)
    run._r.append(instr)
    run._r.append(fld_sep)
    run._r.append(placeholder)
    run._r.append(fld_end)


def insert_section_break_before(doc: Document, needle: str) -> None:
    """Вставляет разрыв секции перед абзацем, содержащим needle."""
    for p in doc.paragraphs:
        if needle in p.text:
            sect_pr = OxmlElement("w:sectPr")
            typ = OxmlElement("w:type")
            typ.set(qn("w:val"), "nextPage")
            sect_pr.append(typ)
            # Копируем размер страницы и поля из текущей секции.
            src = doc.sections[0]._sectPr
            for tag in ("w:pgSz", "w:pgMar"):
                el = src.find(qn(tag))
                if el is not None:
                    sect_pr.append(el.__copy__())
            p_pr = p._p.get_or_add_pPr()
            p_pr.append(sect_pr)
            return
    raise RuntimeError(f"не найден абзац для разрыва секции: {needle}")


def style_document(doc: Document) -> None:
    for section in doc.sections:
        section.page_width = Cm(21.0)
        section.page_height = Cm(29.7)
        section.left_margin = Cm(3.0)
        section.right_margin = Cm(1.0)
        section.top_margin = Cm(2.0)
        section.bottom_margin = Cm(2.0)

    first_heading = True
    for p in doc.paragraphs:
        style = p.style.name if p.style is not None else ""
        # Блоки кода: pandoc оставляет их обычными абзацами с переводами строк.
        if "\n" in p.text and not style.startswith("Heading"):
            p.alignment = WD_ALIGN_PARAGRAPH.LEFT
            p.paragraph_format.first_line_indent = Cm(0)
            p.paragraph_format.line_spacing = 1.0
            p.paragraph_format.space_after = Pt(0)
            for r in p.runs:
                r.font.name = "Courier New"
                r.font.size = Pt(12)
                r.font.bold = False
                r.font.underline = False
            continue
        # Рисунок и его подпись не разрываются между страницами.
        if "<w:drawing>" in p._p.xml:
            p.alignment = WD_ALIGN_PARAGRAPH.CENTER
            p.paragraph_format.first_line_indent = Cm(0)
            p.paragraph_format.keep_with_next = True
            p.paragraph_format.space_before = Pt(6)
            p.paragraph_format.space_after = Pt(0)
            continue
        # Подпись рисунка — по центру под рисунком.
        if p.text.startswith("Рисунок "):
            p.alignment = WD_ALIGN_PARAGRAPH.CENTER
            p.paragraph_format.first_line_indent = Cm(0)
            p.paragraph_format.keep_together = True
            continue
        # Название таблицы — над таблицей, с абзацного отступа.
        # Небольшую таблицу держим вместе с названием, чтобы подпись
        # не оставалась внизу страницы без самой таблицы.
        if p.text.startswith("Таблица ") or p.text.startswith("Продолжение таблицы "):
            p.alignment = WD_ALIGN_PARAGRAPH.LEFT
            p.paragraph_format.first_line_indent = Cm(1.25)
            nxt = p._p.getnext()
            if nxt is not None and nxt.tag == qn("w:tbl"):
                if len(nxt.findall(qn("w:tr"))) <= 10:
                    p.paragraph_format.keep_with_next = True
            continue
        if style.startswith("Heading"):
            p.alignment = WD_ALIGN_PARAGRAPH.CENTER
            p.paragraph_format.first_line_indent = Cm(0)
            p.paragraph_format.line_spacing = 1.5
            if style == "Heading 1":
                # Каждая глава и приложение начинаются с новой страницы.
                # Первый заголовок уже стоит после разрыва секции.
                if not first_heading:
                    p.paragraph_format.page_break_before = True
                first_heading = False
            for r in p.runs:
                r.font.name = "Times New Roman"
                r.font.size = Pt(14)
                r.font.bold = False
                r.font.underline = False
        else:
            for r in p.runs:
                if r.font.bold:
                    r.font.bold = False
                if r.font.underline:
                    r.font.underline = False

    for table in doc.tables:
        for row in table.rows:
            for cell in row.cells:
                for p in cell.paragraphs:
                    p.paragraph_format.first_line_indent = Cm(0)
                    p.paragraph_format.left_indent = Cm(0)
                    p.paragraph_format.right_indent = Cm(0)
                    p.paragraph_format.space_before = Pt(0)
                    p.paragraph_format.space_after = Pt(0)
                    p.paragraph_format.line_spacing = 1.0
                    for r in p.runs:
                        r.font.name = "Times New Roman"
                        r.font.size = Pt(12)


def main() -> None:
    missing = [name for name, _ in SECTIONS if not (KR / name).exists()]
    if missing:
        print("Нет разделов:", ", ".join(sorted(set(missing))), file=sys.stderr)
        print("Сборка остановлена: сначала должны завершиться агенты.", file=sys.stderr)
        sys.exit(1)

    convert_svgs()
    MD.write_text(collect_markdown(), encoding="utf-8")

    cmd = [
        "pandoc",
        str(MD),
        "-f",
        "markdown+pipe_tables+raw_html",
        "-t",
        "docx",
        "--reference-doc",
        str(KR / "reference.docx"),
        "-o",
        str(OUT),
    ]
    subprocess.run(cmd, check=True, cwd=KR)
    print(f"pandoc: {OUT}")

    # Работаем с документом pandoc: в нём уже есть изображения и связи,
    # которые потерялись бы при переносе тела в другой пакет DOCX.
    doc = Document(OUT)
    body = doc.element.body
    final_sect = body.find(qn("w:sectPr"))
    # Содержимое pandoc временно вынимаем и вернём после титула и оглавления.
    children = [child for child in list(body) if child is not final_sect]
    for child in children:
        body.remove(child)

    add_title_page(doc)
    doc.add_section(WD_SECTION.NEW_PAGE)
    add_toc(doc)
    doc.add_section(WD_SECTION.NEW_PAGE)
    for child in children:
        final_sect.addprevious(child)

    style_document(doc)
    # Нумерация страниц только в основной секции (последней).
    if len(doc.sections) >= 1:
        add_page_number_footer(doc.sections[-1])
    # Просим Word обновить поле оглавления при открытии.
    settings = doc.settings.element
    update = OxmlElement("w:updateFields")
    update.set(qn("w:val"), "true")
    settings.append(update)
    doc.save(OUT)
    print(f"готово: {OUT}")


if __name__ == "__main__":
    main()
