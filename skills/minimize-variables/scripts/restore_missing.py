#!/usr/bin/env python3
# restore_missing.py LOG VARUSAGE.xlsx KEEP_BACK.txt [STRUCTURAL_RENAMES.txt [DOFILES.txt]]
# The re-run is the arbiter of the static read. If the run of the minimised copy halted on
# "variable X not found" (LOG = the package run's Stata log), put back ONLY the dropped
# variables tied to that halt and exit 0, so the loop drops again without them (the drop step
# reads KEEP_BACK.txt: lines "variable|reason" after a header) and runs again. X may be a name
# or a pattern (bonus* not found). In this order:
#   1. X itself, if it was dropped;
#   2. the dropped variables whose own name matches the pattern X (rename tr1_s1* *);
#   3. the dropped variables that a rename would have given a name matching X (a pair taken
#      out of a grouped rename: STRUCTURAL_RENAMES, lines "old|new");
#   4. the dropped variables whose name ends in X (the end of a rename chain: rename tr1_s1* *
#      then rename q10 absent);
#   5. the dropped variables the halting command names, directly or through a wildcard rename
#      of the halting do-file (rename hm1* h*).
# Nothing else is put back: when the halt cannot be tied to a dropped variable, exit 2 and a
# person looks (a halt that is not about a variable is not the minimisation's doing).
import fnmatch, os, re, sys
from openpyxl import load_workbook

LOG, VARUSAGE, KB = sys.argv[1], sys.argv[2], sys.argv[3]
RENAMES = sys.argv[4] if len(sys.argv) > 4 else ""
DOFILES = sys.argv[5] if len(sys.argv) > 5 else ""
log = open(LOG, encoding="latin-1").read().split("\n")
first = next((i for i, l in enumerate(log) if re.match(r"^r\(\d+\);", l)), None)
if first is None:
    sys.exit(0)

# what was not found (a name or a pattern), and the command that halted
X = None
for l in reversed(log[max(0, first - 3):first]):
    m = re.search(r"variable (\S+) not found", l) or re.search(r"^(\S+) not found", l)
    if m:
        X = m.group(1)
        break
k = max((i for i in range(max(0, first - 40), first) if re.match(r"^(\. |\s+\d+\. )", log[i])), default=None)
cmd = ""
if k is not None:
    cmd = " ".join([re.sub(r"^\.?\s*\d*\.\s*", "", log[k])] + [l[2:] for l in log[k + 1:first] if l.startswith("> ")]).strip()
ctx = cmd[:150].replace("|", "/")

dropped = {r[1] for r in list(load_workbook(VARUSAGE, read_only=True)["dropped"].iter_rows(values_only=True))[1:]}
back = {l.split("|")[0] for l in open(KB).read().split("\n")[1:] if l}
dropped -= back
ren = {}                                  # new name -> the dropped variables renamed to it
if RENAMES and os.path.exists(RENAMES):
    for l in open(RENAMES):
        if "|" in l:
            o, n = l.strip().split("|")[:2]
            ren.setdefault(n, set()).add(o)

def put_back(hits, why):
    with open(KB, "a") as f:
        for v in sorted(hits):
            f.write(f"{v}|{why}: {ctx}\n")
    shown = ", ".join(sorted(hits)[:6]) + (" ..." if len(hits) > 6 else "")
    print(f"put back {len(hits)} variable(s) ({why}): {shown}")
    sys.exit(0)

if X:
    wild = "*" in X or "?" in X
    if X in dropped:
        put_back({X}, "the run halted without it")
    if wild:
        hits = {d for d in dropped if fnmatch.fnmatchcase(d, X)}
        if hits:
            put_back(hits, f"the run halted with no variable matching {X}")
    hits = set()
    for n, olds in ren.items():
        if n == X or (wild and fnmatch.fnmatchcase(n, X)):
            hits |= olds & dropped
    if hits:
        put_back(hits, f"renamed to a name the run needs ({X})")
    if not wild:
        hits = {d for d in dropped if d.endswith(X) and d != X}
        if hits:
            put_back(hits, f"the run halted without {X}, the name it is renamed to")

# the halting command names a dropped variable (e.g. a dropped h_s1bq8 that Stata then
# abbreviates to h_s1bq8_other), directly or under the name a wildcard rename gives it
if cmd:
    named = set(re.findall(r"[A-Za-z_][A-Za-z0-9_]*", re.sub(r'"[^"]*"', " ", cmd)))
    calls = [re.search(r'(?:do|include|run)\s+"?[^"]*?([^/"]+\.do)"?', l) for l in log[:first]
             if re.match(r"^(\.|\s+\d+\.)\s+(do|include|run)\s", l)]
    calls = [c.group(1) for c in calls if c]
    dofiles = [l.strip() for l in open(DOFILES) if l.strip()] if DOFILES and os.path.exists(DOFILES) else []
    for base in reversed(calls):                       # the innermost package do-file running
        src = [f for f in dofiles if os.path.basename(f) == base]
        if not src:
            continue
        pairs = re.findall(r"(?m)^\s*ren(?:ame)?\s+([A-Za-z0-9_]+)\*\s+([A-Za-z0-9_]*)\*", open(src[0], encoding="latin-1").read())
        for n in list(named):
            for a, b in pairs:
                if n.startswith(b):
                    named.add(a + n[len(b):])
        break
    hits = named & dropped
    if hits:
        put_back(hits, "named in the command that halted")

print("halt not tied to a dropped variable -- nothing put back; look at:")
print("\n".join(log[max(0, first - 8):first + 1]))
sys.exit(2)
