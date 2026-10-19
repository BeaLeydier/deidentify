#!/usr/bin/env python3
"""compare_before_after.py -- did a change to the package (dropping variables, editing code,
relabelling ids) alter ANY output?

Usage: compare_before_after.py BEFORE_DIR AFTER_DIR WORKBOOK.xlsx [SHEET]

Walks BEFORE_DIR (a snapshot of the output folders taken before the change) and compares every
file with its counterpart under AFTER_DIR, ignoring only what changes on every run:
  .tex/.xml/.log/.csv/.txt : text compare; lines with a timestamp ("opened on", "closed on",
                             "log:") and .tex comment lines starting with "%" are dropped.
                             If the texts differ only in numbers that agree to 1e-6 relative,
                             the status is "same up to numerical precision" (with the largest
                             relative difference): full-precision exports (xml) move in the 10th
                             to 15th digit with floating-point rounding and iterative estimators'
                             convergence, far below any printed digit.
  .pdf/.eps                : printable content minus CreationDate/ModDate lines; if that differs,
                             both are rendered (poppler's pdftoppm) and compared pixel by pixel:
                             "same picture" when no pixel differs
  .gph (Stata graph files) : as above minus "command_time", "datafile_date", ".time = ",
                             ".dta_date = " lines and Stata's in-memory object handles
Writes one row per file to tab SHEET (default before_vs_after) of WORKBOOK. Exits nonzero if any
file DIFFERS, is MISSING or is NEW.
"""
import os, subprocess, sys, re, shutil
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from xlsx_sheet import write_sheet

SKIP = ("CreationDate", "ModDate", "opened on", "closed on", "log:", "command_time", "datafile_date",
        "<BeginItem> serset K", '.time = "', '.dta_date = "')
TEXT = (".tex", ".xml", ".log", ".csv", ".txt")
NUM = re.compile(r"-?(?:\d+\.\d*|\.\d+|\d+)(?:[eE][-+]?\d+)?")

def norm(path):
    ext = os.path.splitext(path)[1].lower()
    if ext in TEXT:
        lines = open(path, encoding="latin-1").read().replace("\r", "").split("\n")
        return [l for l in lines if not (ext == ".tex" and l.startswith("%")) and not any(k in l for k in SKIP)]
    lines = subprocess.run(["strings", path], capture_output=True, text=True).stdout.splitlines()
    return [re.sub(r"\bK[0-9a-f]{8,}\b", "K<handle>", l) for l in lines if not any(k in l for k in SKIP)]

def rounding_only(a, b, tol=1e-6):
    """largest relative difference if a and b differ only in numbers within tol, else None"""
    ta, tb = "\n".join(a), "\n".join(b)
    if NUM.sub("#", ta) != NUM.sub("#", tb):
        return None
    worst = 0.0
    for x, y in zip(NUM.findall(ta), NUM.findall(tb)):
        fx, fy = float(x), float(y)
        d = abs(fx - fy) / max(abs(fx), abs(fy), 1e-300)
        if d > tol:
            return None
        worst = max(worst, d)
    return worst

def ppm(path):
    data = open(path, "rb").read()
    parts = data.split(maxsplit=4)              # P6 width height maxval pixels
    return int(parts[1]), int(parts[2]), parts[4]

def same_picture(a, b, work):
    """share of differing pixels when both are rendered at 100 dpi, or None without pdftoppm"""
    if not shutil.which("pdftoppm"):
        return None
    os.makedirs(work, exist_ok=True)
    out = []
    for i, p in enumerate((a, b)):
        stem = os.path.join(work, f"page{i}")
        subprocess.run(["pdftoppm", "-r", "100", "-singlefile", p, stem], capture_output=True)
        if not os.path.exists(stem + ".ppm"):
            return None
        out.append(ppm(stem + ".ppm"))
    (wa, ha, pa), (wb, hb, pb) = out
    if (wa, ha) != (wb, hb):
        return 1.0
    n = wa * ha
    diff = sum(1 for k in range(0, min(len(pa), len(pb)), 3) if pa[k:k + 3] != pb[k:k + 3])
    return diff / n

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
    work = os.path.join(os.path.dirname(os.path.abspath(xlsx)), "_render_" + sheet)
    fb, fa = files(before), files(after)
    rows = []
    for rel in sorted(fb | fa):
        if rel not in fa:
            rows.append([rel, "MISSING after the change", ""]); continue
        if rel not in fb:
            rows.append([rel, "NEW after the change", ""]); continue
        a, b = os.path.join(before, rel), os.path.join(after, rel)
        na, nb = norm(a), norm(b)
        if na == nb:
            rows.append([rel, "identical", ""]); continue
        ext = os.path.splitext(rel)[1].lower()
        if ext in TEXT:
            w = rounding_only(na, nb)
            rows.append([rel, "same up to numerical precision" if w is not None else "DIFFERS",
                         f"largest relative difference {w:.1e}" if w is not None else ""])
        elif ext in (".pdf", ".eps"):
            s = same_picture(a, b, work) if ext == ".pdf" else None
            rows.append([rel, "same picture" if s == 0 else "DIFFERS",
                         "" if s is None else f"{100 * s:.4f}% of pixels differ"])
        else:
            rows.append([rel, "DIFFERS", ""])
    shutil.rmtree(work, ignore_errors=True)
    write_sheet(xlsx, sheet, ["output_file", "status", "detail"], rows)
    bad = [r for r in rows if r[1] in ("DIFFERS",) or r[1].startswith(("MISSING", "NEW"))]
    from collections import Counter
    print(dict(Counter(r[1] for r in rows)), "->", f"{xlsx} [{sheet}]")
    for r in bad:
        print("  ", r)
    sys.exit(1 if bad else 0)

if __name__ == "__main__":
    main()
