#!/usr/bin/env python3
"""compare_before_after.py -- did a change to the package (dropping variables, editing code,
relabelling ids) alter ANY output?

Usage: compare_before_after.py BEFORE_DIR AFTER_DIR WORKBOOK.xlsx [SHEET]

Walks BEFORE_DIR (a snapshot of the output folders taken before the change) and compares every
file with its counterpart under AFTER_DIR, ignoring only what changes on every run:
  .tex/.xml/.log/.csv/.txt : text compare; lines with a timestamp ("opened on", "closed on",
                             "log:") and .tex comment lines starting with "%" are dropped
  .pdf/.eps                : printable content minus CreationDate/ModDate lines
  .gph (Stata graph files) : as above minus "command_time", "datafile_date", ".time = ",
                             ".dta_date = " lines and Stata's in-memory object handles
                             ("serset K1398d4700" -> constant), which differ on every run
Writes one row per file (identical / DIFFERS / MISSING / NEW) to tab SHEET (default
before_vs_after) of WORKBOOK. Exits nonzero if anything differs or is missing.
"""
import os, subprocess, sys, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from xlsx_sheet import write_sheet

SKIP = ("CreationDate", "ModDate", "opened on", "closed on", "log:", "command_time", "datafile_date",
        "<BeginItem> serset K", '.time = "', '.dta_date = "')

def norm(path):
    ext = os.path.splitext(path)[1].lower()
    if ext in (".tex", ".xml", ".log", ".csv", ".txt"):
        lines = open(path, encoding="latin-1").read().replace("\r", "").split("\n")
        return [l for l in lines if not (ext == ".tex" and l.startswith("%")) and not any(k in l for k in SKIP)]
    lines = subprocess.run(["strings", path], capture_output=True, text=True).stdout.splitlines()
    return [re.sub(r"\bK[0-9a-f]{8,}\b", "K<handle>", l) for l in lines if not any(k in l for k in SKIP)]

def files(root):
    out = set()
    for dp, _, fns in os.walk(root):
        for fn in fns:
            if not fn.startswith("."):
                out.add(os.path.relpath(os.path.join(dp, fn), root))
    return out

def main():
    before, after, xlsx = sys.argv[1], sys.argv[2], sys.argv[3]
    sheet = sys.argv[4] if len(sys.argv) > 4 else "before_vs_after"
    fb, fa = files(before), files(after)
    rows = []
    for rel in sorted(fb | fa):
        if rel not in fa:
            rows.append([rel, "MISSING after the change"])
        elif rel not in fb:
            rows.append([rel, "NEW after the change"])
        else:
            same = norm(os.path.join(before, rel)) == norm(os.path.join(after, rel))
            rows.append([rel, "identical" if same else "DIFFERS"])
    write_sheet(xlsx, sheet, ["output_file", "status"], rows)
    n_bad = sum(r[1] != "identical" for r in rows)
    print(f"{len(rows) - n_bad} identical, {n_bad} differ/missing/new -> {xlsx} [{sheet}]")
    for r in rows:
        if r[1] != "identical":
            print("  ", r)
    sys.exit(1 if n_bad else 0)

if __name__ == "__main__":
    main()
