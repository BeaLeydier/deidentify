"""xlsx_sheet.py -- write one tab of a review workbook (shared by the plugin's Python tools).

    from xlsx_sheet import write_sheet
    write_sheet("audit/review.xlsx", "string_tails", header, rows)

Creates the workbook if it does not exist and replaces the tab if it does; the other tabs
are kept, so several tools (Stata `export excel ..., sheetreplace` included) can fill one
workbook. Cells are cleaned of characters Excel refuses (control bytes). Needs openpyxl.
"""
import os, re
from openpyxl import Workbook, load_workbook

_BAD = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f]")

def _clean(v):
    return _BAD.sub(" ", v) if isinstance(v, str) else v

def write_sheet(xlsx, name, header, rows):
    if os.path.exists(xlsx):
        wb = load_workbook(xlsx)
        if name in wb.sheetnames:
            del wb[name]
    else:
        wb = Workbook()
        wb.remove(wb.active)
    ws = wb.create_sheet(name[:31])
    ws.append(list(header))
    for r in rows:
        ws.append([_clean(v) for v in r])
    os.makedirs(os.path.dirname(os.path.abspath(xlsx)), exist_ok=True)
    wb.save(xlsx)
