"""Создаёт reference.docx для pandoc: стили под требования методички.

Запуск: python3 tools/make_reference.py
Результат: docs/kr22/reference.docx
"""
from pathlib import Path

from docx import Document
from docx.enum.section import WD_SECTION
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_LINE_SPACING
from docx.oxml.ns import qn
from docx.shared import Cm, Pt


OUT = Path(__file__).resolve().parent.parent / "docs" / "kr22" / "reference.docx"


def set_font(style, name="Times New Roman", size=14, bold=False):
    style.font.name = name
    style.font.size = Pt(size)
    style.font.bold = bold
    style.font.underline = False
    rpr = style.element.get_or_add_rPr()
    rfonts = rpr.find(qn("w:rFonts"))
    if rfonts is None:
        rfonts = rpr.makeelement(qn("w:rFonts"), {})
        rpr.append(rfonts)
    for attr in ("w:ascii", "w:hAnsi", "w:cs", "w:eastAsia"):
        rfonts.set(qn(attr), name)


def set_para(style, align=WD_ALIGN_PARAGRAPH.JUSTIFY, indent=1.25, spacing=1.5,
             before=0, after=0, page_break=False):
    pf = style.paragraph_format
    pf.alignment = align
    pf.first_line_indent = None if indent is None else Cm(indent)
    pf.line_spacing = spacing
    pf.space_before = Pt(before)
    pf.space_after = Pt(after)
    pf.page_break_before = page_break
    pf.keep_with_next = False
    pf.widow_control = True


def main():
    doc = Document()

    # Страница А4 и поля по методичке.
    section = doc.sections[0]
    section.page_width = Cm(21.0)
    section.page_height = Cm(29.7)
    section.left_margin = Cm(3.0)
    section.right_margin = Cm(1.0)
    section.top_margin = Cm(2.0)
    section.bottom_margin = Cm(2.0)

    styles = doc.styles

    normal = styles["Normal"]
    set_font(normal, size=14, bold=False)
    set_para(normal, align=WD_ALIGN_PARAGRAPH.JUSTIFY, indent=1.25,
             spacing=1.5, before=0, after=0)

    for name in ("Body Text", "First Paragraph", "Compact"):
        if name in styles:
            st = styles[name]
            set_font(st, size=14, bold=False)
            set_para(st, align=WD_ALIGN_PARAGRAPH.JUSTIFY,
                     indent=0 if name == "Compact" else 1.25,
                     spacing=1.5, before=0, after=0)

    if "Heading 1" in styles:
        st = styles["Heading 1"]
        set_font(st, size=14, bold=False)
        set_para(st, align=WD_ALIGN_PARAGRAPH.CENTER, indent=0,
                 spacing=1.5, before=0, after=12, page_break=True)

    if "Heading 2" in styles:
        st = styles["Heading 2"]
        set_font(st, size=14, bold=False)
        set_para(st, align=WD_ALIGN_PARAGRAPH.CENTER, indent=0,
                 spacing=1.5, before=12, after=6)

    if "Heading 3" in styles:
        st = styles["Heading 3"]
        set_font(st, size=14, bold=False)
        set_para(st, align=WD_ALIGN_PARAGRAPH.LEFT, indent=1.25,
                 spacing=1.5, before=6, after=0)

    # Подписи рисунков и таблиц.
    for style_name in ("Caption", "Image Caption", "Table Caption"):
        if style_name in styles:
            st = styles[style_name]
            set_font(st, size=14, bold=False)
            set_para(st, align=WD_ALIGN_PARAGRAPH.CENTER, indent=0,
                     spacing=1.5, before=6, after=6)

    # Оглавление.
    if "TOC Heading" in styles:
        st = styles["TOC Heading"]
        set_font(st, size=14, bold=False)
        set_para(st, align=WD_ALIGN_PARAGRAPH.CENTER, indent=0,
                 spacing=1.5, before=0, after=12)

    # Таблицы: 12 пт.
    if "Table" in styles:
        st = styles["Table"]
        set_font(st, size=12, bold=False)

    doc.save(OUT)
    print(f"created {OUT}")


if __name__ == "__main__":
    main()
