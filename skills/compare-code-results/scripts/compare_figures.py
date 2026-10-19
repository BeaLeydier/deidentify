#!/usr/bin/env python3
"""compare_figures.py -- are two sets of figure PDFs the same picture?

Usage: compare_figures.py REF_DIR NEW_DIR WORKBOOK.xlsx WORK_DIR
       (WORK_DIR: a folder of the project for the rendered pages; tab `figures` of WORKBOOK)

Two levels, per file name present in both folders:
  1. content streams: the PDF's printable text minus CreationDate/ModDate/Producer/Creator lines;
     identical streams = identical drawing commands.
  2. pixels: each PDF rendered at 150 dpi (needs `pdftoppm` from poppler; read as PPM, so no
     other library) and compared; share of pixels that differ at all.
Pixel/byte comparison is only meaningful when BOTH sets were produced on the SAME machine: across
machines, font family and page scaling dominate (a 4-7% pixel difference from fonts alone was seen
between Windows- and macOS-built Stata figures). If the reference was built elsewhere, re-run the
reference package's figure code locally first, then compare.
"""
import os, subprocess, sys, shutil
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path[:0] = [HERE, os.path.join(HERE, "..", "..", "..", "shared")]
from xlsx_sheet import write_sheet
ref, new, out, scratch = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
os.makedirs(scratch, exist_ok=True)

def content_stream(path):
    lines = subprocess.run(["strings", path], capture_output=True, text=True).stdout.splitlines()
    return [l for l in lines if not any(k in l for k in ("CreationDate", "ModDate", "Producer", "Creator"))]

rows = []
for fn in sorted(os.listdir(ref)):
    if not fn.endswith(".pdf") or not os.path.exists(os.path.join(new, fn)):
        continue
    a, b = os.path.join(ref, fn), os.path.join(new, fn)
    same = content_stream(a) == content_stream(b)
    pct = "n/a (no pdftoppm)"
    if shutil.which("pdftoppm"):
        imgs = []
        for tag, p in (("ref", a), ("new", b)):
            stem = os.path.join(scratch, f"{tag}_{fn[:-4]}")
            subprocess.run(["pdftoppm", "-r", "150", "-singlefile", p, stem], capture_output=True)
            raw = open(stem + ".ppm", "rb").read().split(maxsplit=4)     # P6 width height maxval pixels
            imgs.append((int(raw[1]), int(raw[2]), raw[4]))
            os.remove(stem + ".ppm")
        (wa, ha, pa), (wb, hb, pb) = imgs
        if (wa, ha) != (wb, hb):
            pct = "size differs"
        else:
            nd = sum(1 for k in range(0, len(pa), 3) if pa[k:k + 3] != pb[k:k + 3])
            pct = f"{100 * nd / (wa * ha):.4f}"
    rows.append([fn, "identical" if same else "differs", pct])
    print(f"{fn}: content {'identical' if same else 'DIFFERS'}, pixels differing {pct}%")
write_sheet(out, "figures", ["figure", "pdf_content_stream", "pct_pixels_differing"], rows)
sys.exit(0 if all(r[1] == "identical" for r in rows) else 1)
