"""Создаёт reference.docx для pandoc: стили под требования методички.

За основу берётся штатный reference.docx pandoc — в нём есть все служебные
стили таблиц (Table, Compact и др.). Если собрать документ с нуля, pandoc
ссылается на отсутствующий стиль Table, и LibreOffice разваливает таблицы
в один столбец.

Запуск: python3 tools/make_reference.py
Результат: docs/kr22/reference.docx
"""
import subprocess
from pathlib import Path

from docx import Document
from docx.enum.style import WD_STYLE_TYPE
from docx.enum.text import WD_ALIGN_PARAGRAPH
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
    pf.left_indent = Cm(0)
    pf.right_indent = Cm(0)
    pf.line_spacing = spacing
    pf.space_before = Pt(before)
    pf.space_after = Pt(after)
    pf.page_break_before = page_break
    pf.keep_with_next = False
    pf.widow_control = True


def main():
    subprocess.run(
        ["pandoc", "--print-default-data-file", "reference.docx"],
        check=True,
        stdout=OUT.open("wb"),
    )
    doc = Document(OUT)

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

    for style_name in ("Caption", "Image Caption", "Table Caption"):
        if style_name in styles:
            st = styles[style_name]
            set_font(st, size=14, bold=False)
            set_para(st, align=WD_ALIGN_PARAGRAPH.CENTER, indent=0,
                     spacing=1.5, before=6, after=6)

    if "TOC Heading" in styles:
        st = styles["TOC Heading"]
        set_font(st, size=14, bold=False)
        set_para(st, align=WD_ALIGN_PARAGRAPH.CENTER, indent=0,
                 spacing=1.5, before=0, after=12)

    # Стиль для блоков кода: pandoc ссылается на SourceCode, но в штатном
    # reference.docx его нет. Без определения Word и LibreOffice подставляют
    # Normal с выравниванием по ширине, и код растягивается пробелами.
    source = styles.add_style("SourceCode", WD_STYLE_TYPE.PARAGRAPH)
    source.base_style = styles["Normal"]
    set_font(source, name="Courier New", size=12, bold=False)
    set_para(source, align=WD_ALIGN_PARAGRAPH.LEFT, indent=0,
             spacing=1.0, before=0, after=0)

    if "Table" in styles:
        st = styles["Table"]
        set_font(st, size=12, bold=False)
        st.paragraph_format.space_before = Pt(0)
        st.paragraph_format.space_after = Pt(0)
        st.paragraph_format.line_spacing = 1.0

    doc.save(OUT)
    print(f"created {OUT}")


if __name__ == "__main__":
    main()
