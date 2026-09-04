#!/usr/bin/env python3
"""compare_figures.py -- are two sets of figure PDFs the same picture?

Usage: compare_figures.py REF_DIR NEW_DIR OUT.csv [SCRATCH_DIR]

Two levels, per file name present in both folders:
  1. content streams: the PDF's printable text minus CreationDate/ModDate/Producer/Creator lines;
     identical streams = identical drawing commands.
  2. pixels: each PDF rendered at 150 dpi (needs `pdftoppm` from poppler, and Pillow + numpy) and
     subtracted; share of pixels that differ at all.
Pixel/byte comparison is only meaningful when BOTH sets were produced on the SAME machine: across
machines, font family and page scaling dominate (a 4-7% pixel difference from fonts alone was seen
between Windows- and macOS-built Stata figures). If the reference was built elsewhere, re-run the
reference package's figure code locally first, then compare.
"""
import os, subprocess, csv, sys
ref, new, out = sys.argv[1], sys.argv[2], sys.argv[3]
scratch = sys.argv[4] if len(sys.argv) > 4 else "/tmp/figcmp"
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
    pct = ""
    try:
        from PIL import Image; import numpy as np
        pa, pb = os.path.join(scratch, "ref_" + fn[:-4]), os.path.join(scratch, "new_" + fn[:-4])
        subprocess.run(["pdftoppm", "-r", "150", "-png", "-singlefile", a, pa], check=True)
        subprocess.run(["pdftoppm", "-r", "150", "-png", "-singlefile", b, pb], check=True)
        A = np.asarray(Image.open(pa + ".png").convert("L"), dtype=np.int16)
        B = np.asarray(Image.open(pb + ".png").convert("L"), dtype=np.int16)
        pct = f"{100 * float((abs(A - B) > 0).mean()):.4f}" if A.shape == B.shape else "size differs"
    except Exception as e:                       # no poppler/Pillow: content-stream check only
        pct = f"n/a ({type(e).__name__})"
    rows.append([fn, "identical" if same else "differs", pct])
    print(f"{fn}: content {'identical' if same else 'DIFFERS'}, pixels differing {pct}%")
with open(out, "w", newline="") as f:
    csv.writer(f).writerows([["figure", "pdf_content_stream", "pct_pixels_differing"]] + rows)
sys.exit(0 if all(r[1] == "identical" for r in rows) else 1)
