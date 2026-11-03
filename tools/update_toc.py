"""Обновляет поле оглавления в готовом DOCX через LibreOffice UNO.

Запуск (сначала — слушатель LibreOffice на порту 2002):

    soffice --headless --norestore --nofirststartwizard \
        -env:UserInstallation=file:///tmp/lo_profile \
        --accept=socket,host=127.0.0.1,port=2002;urp;StarOffice.ComponentContext &
    python3 tools/update_toc.py docs/kr22/Пояснительная_записка_КР2_2.docx

Поле TOC обновляется один раз; из-за переразбивки страниц после подстановки
оглавления скрипт нужно запустить дважды, чтобы номера страниц совпали с
итоговой вёрсткой.
"""
from __future__ import annotations

import sys
from pathlib import Path

import uno
from com.sun.star.beans import PropertyValue


def prop(name: str, value):
    p = PropertyValue()
    p.Name = name
    p.Value = value
    return p


def main() -> None:
    if len(sys.argv) != 2:
        print("usage: python3 tools/update_toc.py <file.docx>", file=sys.stderr)
        sys.exit(2)
    path = Path(sys.argv[1]).resolve()
    if not path.exists():
        print(f"нет файла {path}", file=sys.stderr)
        sys.exit(1)

    local = uno.getComponentContext()
    resolver = local.ServiceManager.createInstanceWithContext(
        "com.sun.star.bridge.UnoUrlResolver", local
    )
    ctx = resolver.resolve(
        "uno:socket,host=127.0.0.1,port=2002;urp;StarOffice.ComponentContext"
    )
    desktop = ctx.ServiceManager.createInstanceWithContext(
        "com.sun.star.frame.Desktop", ctx
    )
    doc = desktop.loadComponentFromURL(
        uno.systemPathToFileUrl(str(path)),
        "_blank",
        0,
        (prop("Hidden", True),),
    )
    indexes = doc.getDocumentIndexes()
    for i in range(indexes.getCount()):
        indexes.getByIndex(i).update()
    doc.refresh()
    doc.storeToURL(
        uno.systemPathToFileUrl(str(path)),
        (prop("FilterName", "MS Word 2007 XML"),),
    )
    doc.close(False)
    print(f"оглавление обновлено: {path}")


if __name__ == "__main__":
    main()
