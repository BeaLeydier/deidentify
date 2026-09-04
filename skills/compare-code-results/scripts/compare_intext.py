#!/usr/bin/env python3
"""compare_intext.py -- check the numbers a paper quotes in its TEXT against the package's
in-text logs.

Usage: compare_intext.py MAPPING.csv LOG_DIR OUT.csv

MAPPING.csv is hand-written, one row per in-text log (quote every field; the regexes contain
commas):
  log            file name of the log the package writes
  statistic      what the number is
  extract_regex  a Python regex with ONE capture group that pulls the statistic out of the log
  take           which occurrence corresponds to the paper: first | last | all | minmax
  paper_value    what the paper prints ("n/a" if no sentence quotes this log's value)
  paper_statement the sentence, and paper_line its location, for the reviewer
The comparison is left to the reader of OUT.csv (log value next to paper value): in-text numbers
are printed at odd precisions and in prose, so a mechanical match is not attempted.
"""
import csv, re, sys
mapping, logdir, out = sys.argv[1], sys.argv[2], sys.argv[3]
rows = []
for r in csv.DictReader(open(mapping)):
    txt = open(f"{logdir}/{r['log']}", encoding="latin-1", errors="ignore").read()
    vals = [v.replace(",", "") for v in re.findall(r["extract_regex"], txt, flags=re.M)]
    take = r.get("take", "first")
    if not vals: got = ""
    elif take == "minmax": got = f"{min(map(int, vals))}-{max(map(int, vals))}"
    elif take == "last": got = vals[-1]
    elif take == "all": got = " / ".join(vals[-4:])
    else: got = vals[0]
    rows.append([r["log"], r["statistic"], got, r["paper_value"], r.get("paper_statement", ""), r.get("paper_line", "")])
    print(f"  {r['log']:<40} log: {got:<28} paper: {r['paper_value']}")
with open(out, "w", newline="") as f:
    csv.writer(f).writerows([["log", "statistic", "package_value", "paper_value", "paper_statement", "paper_line"]] + rows)
