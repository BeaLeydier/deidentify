#!/usr/bin/env python3
"""scan_id_order_dependence.py -- does the analysis code depend on the ORDER or MAGNITUDE of an
id variable? If it does, a random (non-monotone) scramble changes results, and the fix is in
the code or the map design -- NOT an order-preserving map, which is trivially reversible.

Usage: scan_id_order_dependence.py OUT.csv "id1 id2 ..." dofile1.do [dofile2.do ...]
       (pass the do-files the master actually runs: see minimize-variables/reachable_dofiles.py)

One row per hit: file, line, the code, id variable, construct, LEVEL, suggested fix.
  A  magnitude   the id's VALUE is compared or binned: `if id > 154`, inrange(id,..), recode id
                 -> banded scramble (cuts() in scramble_id) and rewrite the cutoff once, or replace
                    the condition with a shipped indicator variable
  B  numbering   numbers DERIVED from the id's sort order feed the code: egen group(id),
                 tab id, gen(), encode, levelsof id + a counter, and hardcoded `x_84`-style names
                 -> build dummies by value from an explicit list, or ship the indicator
  C  position    a row is picked by POSITION after sorting on the id: sort id + _n/_N/[1]/[_N],
                 duplicates drop, collapse (first)/(last), keep in, sample, by id: x[_n-1]
                 -> add a stable secondary sort key / set sortseed; make the pick explicit
  D  invariant   uses that a 1-to-1 relabel cannot change (informational): bysort id: sums,
                 xtset/tsset, merge/joinby keys, cluster(id), i.id, absorb(id), egen ... by(id)
  H  hardcoded   a literal id value in the code (`if hhid==149`, inlist(id,...)): not an order
                 problem, but the literal must be recoded through the map
Comments are stripped first (// ..., * lines, /* */ blocks). The scan is conservative -- every
hit is a place to LOOK; the arbiter is empirical: scramble randomly on a copy, run the package,
compare every output with compare_before_after.py. Identical outputs = no dependence.
"""
import sys, re, csv, os

out, ids, files = sys.argv[1], sys.argv[2].split(), sys.argv[3:]
ID = "(" + "|".join(re.escape(i) for i in ids) + ")"
W = r"(?<![A-Za-z0-9_])"      # word boundaries that respect Stata names
E = r"(?![A-Za-z0-9_])"

RULES = [  # (level, construct, regex, fix)
 ("H", "hardcoded id value",     rf"{W}{ID}{E}\s*(==|!=)\s*-?\d|{W}inlist\s*\(\s*{ID}{E}", "not order dependence: the literal must be recoded through the map (scramble-ids step 4 does this)"),
 ("A", "id compared to a value", rf"{W}{ID}{E}\s*(>=|<=|>|<)\s*-?\d", "banded scramble with cuts() at this value, then rewrite the cutoff once; or ship an indicator variable and test that instead"),
 ("A", "value compared to id",   rf"-?\d+\s*(>=|<=|>|<)\s*{W}{ID}{E}", "same as above"),
 ("A", "id binned",              rf"{W}(inrange|inlist|recode|irecode|autocode|cut)\s*\(\s*{ID}{E}|{W}recode\s+{ID}{E}|{W}egen\b.*\bcut\s*\(\s*{ID}", "bin on a shipped variable, not on the id"),
 ("B", "group numbers from id order", rf"{W}egen\b.*\bgroup\s*\(\s*[^)]*{W}{ID}{E}", "group numbers follow sort order: build indicators by value from an explicit list, or ship the indicator"),
 ("B", "dummies numbered by id order", rf"{W}(tab|tabulate|tab1)\b[^,\n]*{W}{ID}{E}[^,\n]*,.*\bgen(erate)?\s*\(", "dummy k is the k-th smallest id: create dummies by value (`gen d_x = id==<value>`) or ship them"),
 ("B", "encode/levelsof numbering", rf"{W}(encode|levelsof)\s+{ID}{E}", "if a counter or the numeric code is used downstream it follows sort order; iterate over the mapped values instead"),
 ("C", "position after sort on id", rf"{W}(sort|gsort|bysort|bys)\b[^:\n]*{W}{ID}{E}", "check the next lines for _n/_N/[1]/[_N]; add a stable secondary key or make the pick explicit"),
 ("C", "row picked by position",  rf"{W}(_n|_N)\b|\[\s*(1|_N|_n\s*[-+]\s*\d+)\s*\]", "depends on the current sort order; fine only if that order is fully determined by non-id keys"),
 ("C", "first/last row kept",     rf"{W}(duplicates\s+drop|collapse\b.*\((first|last|firstnm|lastnm)\)|keep\s+in\b|drop\s+in\b)|^\s*(qui\w*\s+|cap\w*\s+)*(bsample|sample)\b", "which row survives depends on sort order; sort on a stable key first"),
 ("D", "order-invariant use",     rf"{W}(xtset|tsset|merge|joinby|cluster|vce|absorb|areg|xtreg|reghdfe)\b.*{W}{ID}{E}|{W}i\.{ID}{E}", "a 1-to-1 relabel cannot change this"),
]

def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    keep = []
    for l in text.split("\n"):
        l = re.sub(r"//.*", "", l)
        keep.append("" if re.match(r"^\s*\*", l) else l)
    return keep

rows = []
for f in files:
    if not os.path.exists(f): continue
    lines = strip_comments(open(f, encoding="latin-1", errors="ignore").read())
    for i, l in enumerate(lines, 1):
        if not l.strip(): continue
        for level, construct, rx, fix in RULES:
            m = re.search(rx, l, flags=re.I)
            if not m: continue
            # position hits (_n, [1] ...) only matter if an id sort is nearby: look back 3 lines
            if construct == "row picked by position":
                ctx = " ".join(lines[max(0, i - 4):i])
                if not re.search(rf"{W}(sort|gsort|bysort|bys)\b[^:\n]*{W}{ID}{E}", ctx, flags=re.I): continue
            idv = next((x for x in ids if re.search(rf"{W}{re.escape(x)}{E}", l)), "")
            rows.append([os.path.basename(f), i, l.strip()[:160], idv, construct, level, fix])
            break
rows.sort(key=lambda r: (r[5], r[0], r[1]))
with open(out, "w", newline="") as fh:
    csv.writer(fh).writerows([["file", "line", "code", "id_variable", "construct", "level", "suggested_fix"]] + rows)
by = {}
for r in rows: by[r[5]] = by.get(r[5], 0) + 1
print("hits by level:", {k: by.get(k, 0) for k in "ABCDH"}, "->", out)
print("levels A-C need a look; then the arbiter: random scramble on a copy, run, compare_before_after.py")
