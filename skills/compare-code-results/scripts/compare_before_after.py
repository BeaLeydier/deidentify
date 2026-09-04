#!/usr/bin/env python3
"""compare_before_after.py -- did a change to the package (e.g. dropping variables) alter ANY output?

Usage: compare_before_after.py BEFORE_DIR AFTER_DIR OUT.csv

Walks BEFORE_DIR (a snapshot of the output folders taken before the change) and compares every
file with its counterpart under AFTER_DIR, ignoring only things that change on every run:
  .tex/.xml/.log/.csv/.txt : text compare; lines with a timestamp ("opened on", "closed on",
                             "log:"), and .tex comment lines starting with "%" are dropped
  .pdf/.eps                : printable content minus CreationDate/ModDate lines
  .gph (Stata graph files) : as above minus "command_time", "datafile_date", ".time = ",
                             ".dta_date = " lines and Stata's in-memory object handles
                             ("serset K1398d4700" -> constant), which differ on every run
Exits nonzero if anything differs or is missing.
"""
import os, subprocess, csv, sys, re
before, after, out = sys.argv[1], sys.argv[2], sys.argv[3]
SKIP = ("CreationDate", "ModDate", "opened on", "closed on", "log:", "command_time", "datafile_date", "<BeginItem> serset K", '.time = "', '.dta_date = "')

def norm(path):
    ext = os.path.splitext(path)[1].lower()
    if ext in (".tex", ".xml", ".log", ".csv", ".txt"):
        lines = open(path, encoding="latin-1").read().replace("\r", "").split("\n")
        return [l for l in lines if not (ext == ".tex" and l.startswith("%")) and not any(k in l for k in SKIP)]
    lines = subprocess.run(["strings", path], capture_output=True, text=True).stdout.splitlines()
    return [re.sub(r"\bK[0-9a-f]{8,}\b", "K<handle>", l) for l in lines if not any(k in l for k in SKIP)]

rows = []
for dp, _, fns in os.walk(before):
    for fn in sorted(fns):
        if fn.startswith("."):
            continue
        a = os.path.join(dp, fn); rel = os.path.relpath(a, before); b = os.path.join(after, rel)
        if not os.path.exists(b):
            rows.append([rel, "MISSING after change"]); continue
        rows.append([rel, "identical" if norm(a) == norm(b) else "DIFFERS"])
with open(out, "w", newline="") as f:
    csv.writer(f).writerows([["output_file", "status"]] + rows)
n_bad = sum(r[1] != "identical" for r in rows)
print(f"{len(rows) - n_bad} identical, {n_bad} differ/missing")
for r in rows:
    if r[1] != "identical": print("  ", r)
sys.exit(1 if n_bad else 0)
