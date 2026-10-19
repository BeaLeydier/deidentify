#!/usr/bin/env python3
"""scan_text_files.py -- does any ORIGINAL identifier appear as text anywhere in the package?

Usage: scan_text_files.py WORKBOOK.xlsx WATCH_DIR PACKAGE_DIR "fam1 fam2 ..."

id_leak_tests.do looks inside the .dta files; this looks at every text-bearing file (do, ado,
csv, txt, md, tex, log, ...), where an original id could survive in a hard-coded line of code
or a CSV. Binary files are skipped (.dta is covered by the Stata tests; runs of printable bytes
inside PDFs are coincidence), and so are third-party ado/ folders.
Every whole number of 2-12 digits is matched against each family's OLD-ONLY watch list
(WATCH_DIR/WL_origonly_<fam>.txt, written by id_leak_tests.do): hits of >= 5 digits are
distinctive; 2-4 digit hits are ambient numbers (line numbers, years, codes) and only counted.
Writes tab `id_text_sweep` (one row per family, examples with their files). Exits nonzero on
any distinctive hit, for a reviewer to look at.
"""
import os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path[:0] = [HERE, os.path.join(HERE, "..", "..", "..", "shared")]
from xlsx_sheet import write_sheet

TEXT_EXT = {".do", ".ado", ".txt", ".csv", ".md", ".r", ".tex", ".log", ".rtf", ".json", ".toc",
            ".hlp", ".sthlp", ".grec", ".py", ".xml"}
NUM = re.compile(r"(?<![0-9A-Za-z_.])([0-9]{2,12})(?![0-9A-Za-z_.])")

xlsx, watch, pkg, fams = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4].split()
tokens, n_files = {}, 0
for dp, dn, fns in os.walk(pkg):
    dn[:] = [d for d in dn if d != "ado"]
    for fn in fns:
        if os.path.splitext(fn)[1].lower() not in TEXT_EXT:
            continue
        n_files += 1
        rel = os.path.relpath(os.path.join(dp, fn), pkg)
        for m in NUM.finditer(open(os.path.join(dp, fn), encoding="latin-1", errors="ignore").read()):
            tokens.setdefault(m.group(1), set()).add(rel)
rows, n_big = [], 0
for fam in fams:
    old_only = {x.strip() for x in open(os.path.join(watch, f"WL_origonly_{fam}.txt")) if x.strip()}
    old_only = {str(int(float(x))) for x in old_only}
    hits = sorted(set(tokens) & old_only, key=lambda x: -int(x))
    big = [h for h in hits if len(h) >= 5]
    n_big += len(big)
    ex = "; ".join(f"{h} ({', '.join(sorted(tokens[h])[:3])})" for h in big[:20])
    rows.append([fam, n_files, len(hits), len(big), len(hits) - len(big), ex])
    print(f"{fam}: distinctive hits {len(big)} (small-number noise {len(hits) - len(big)})")
write_sheet(xlsx, "id_text_sweep", ["family", "text_files_swept", "old_only_hits", "distinctive_hits_5plus_digits",
            "small_number_hits", "distinctive_examples (files)"], rows)
sys.exit(1 if n_big else 0)
