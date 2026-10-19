#!/usr/bin/env python3
# restore_missing.py LOG VARUSAGE.xlsx KEEP_BACK.txt [STRUCTURAL_RENAMES.txt [DOFILES.txt]]
# The re-run is the arbiter of the static read. If the run of the minimised copy halted on
# "variable X not found" (LOG = the package run's Stata log), put back what the static read
# missed and exit 0, so the master rebuilds the copy, drops again without those variables
# (the drop step reads KEEP_BACK.txt: lines "variable|reason" after a header) and re-runs:
#   - X itself, if it was dropped;
#   - a wildcard X* whose every match was dropped: the dropped variables it matches;
#   - X the new name of a dropped variable taken out of a grouped rename (STRUCTURAL_RENAMES:
#     lines "old|new"), or the end of a rename chain: the dropped variables named ...X;
#   - otherwise, every dropped variable the halting do-file names (last resort, errs on the
#     side of keeping).
# Exit 2 when the halt cannot be tied to a dropped variable: a person looks.
# Typical loop (bash): for try in 1..10: rebuild copy; drop; run; grep -q "^r(" log || break;
#                       python3 restore_missing.py log ... || exit 1
import os, re, sys
from openpyxl import load_workbook
log = open(sys.argv[1], encoding="latin-1").read().split("\n")
VARUSAGE, KB = sys.argv[2], sys.argv[3]
RENAMES = sys.argv[4] if len(sys.argv) > 4 else ""
if len(sys.argv) > 5:
    DOFILES = sys.argv[5]
first = next((i for i, l in enumerate(log) if re.match(r"^r\(\d+\);", l)), None)
if first is None:
    sys.exit(0)
m = None
for l in reversed(log[max(0, first - 3):first]):
    m = re.search(r"variable (\S+) not found", l) or re.search(r"^(\S+) not found", l)
    if m:
        break
dropped = {r[1] for r in list(load_workbook(VARUSAGE, read_only=True)["dropped"].iter_rows(values_only=True))[1:]}
# a name a dropped variable would have been renamed to (05a took the pair out of a rename)
ren = {}
RF = RENAMES if "RENAMES" in globals() else f"{DELIV}/minimize/structural_renames.txt"
if RF and os.path.exists(RF):
    for l in open(RF):
        if "|" in l:
            o, n = l.strip().split("|")
            ren.setdefault(n, []).append(o)
if m and m.group(1) in ren:
    olds = sorted(set(ren[m.group(1)]))
    with open(KB if "KB" in globals() else f"{DELIV}/minimize/keep_back.txt", "a") as f:
        for o in olds:
            f.write(f"{o}|renamed to {m.group(1)}, which a later line names\n")
    print(f"put back {', '.join(olds)} (renamed to {m.group(1)})")
    sys.exit(0)
# a wildcard whose every match was dropped (rename tr1_s1* *): put back what it matches
if m and "*" in m.group(1):
    import fnmatch
    hits = sorted(d for d in dropped if fnmatch.fnmatchcase(d, m.group(1)))
    if hits:
        ctx = next((re.sub(r"^\.?\s*\d*\.\s*", "", l).strip() for l in reversed(log[max(0, first - 40):first])
                    if re.match(r"^(\. |\s+\d+\. )", l)), "")
        with open(KB, "a") as f:
            for v in hits:
                f.write(f"{v}|run halted without the pattern's variables: {ctx[:150].replace('|', '/')}\n")
        print(f"put back {len(hits)} variables matching {m.group(1)}")
        sys.exit(0)
# a name a dropped variable carries after a wildcard rename chain (rename tr1_s1* * then
# rename (q10 ...) (absent ...)): put back the dropped variables whose name ends with it
if m and m.group(1) not in dropped and "*" not in m.group(1):
    hits = sorted(d for d in dropped if d.endswith(m.group(1)) and d != m.group(1))
    if hits:
        ctx = next((re.sub(r"^\.?\s*\d*\.\s*", "", l).strip() for l in reversed(log[max(0, first - 40):first])
                    if re.match(r"^(\. |\s+\d+\. )", l)), "")
        with open(KB, "a") as f:
            for v in hits:
                f.write(f"{v}|run halted without {m.group(1)}, the name it is renamed to: {ctx[:120].replace('|', '/')}\n")
        print(f"put back {len(hits)} variables ending in {m.group(1)}")
        sys.exit(0)
if not m or m.group(1) not in dropped:
    # the failing command itself (with its "> " continuation lines) names a dropped variable:
    # e.g. a dropped h_s1bq8 that Stata then abbreviates to h_s1bq8_other in a rename
    k = max((i for i in range(max(0, first - 40), first) if re.match(r"^(\. |\s+\d+\. )", log[i])), default=None)
    if k is not None:
        cmd = " ".join([log[k]] + [l[2:] for l in log[k + 1:first] if l.startswith("> ")])
        named = set(re.findall(r"[A-Za-z_][A-Za-z0-9_]*", re.sub(r'"[^"]*"', " ", cmd)))
        done0 = {l.split("|")[0] for l in open(KB if "KB" in globals() else f"{DELIV}/minimize/keep_back.txt").read().split("\n")[1:] if l}
        # names the halting do-file creates by wildcard renames (rename hm1* h*): the originals
        calls0 = [re.search(r'(?:do|include|run)\s+"?([^"]*?([^/"]+\.do))"?', l) for l in log[:first]
                  if re.match(r"^(\.|\s+\d+\.)\s+(do|include|run)\s", l) and "master-directory" not in l]
        calls0 = [c for c in calls0 if c]
        dofiles = [l.strip() for l in open(DOFILES if "DOFILES" in globals() else f"{DELIV}/minimize/dofiles.txt") if l.strip()]
        if calls0:
            src = [f for f in dofiles if os.path.basename(f) == calls0[-1].group(2)]
            pairs = re.findall(r"(?m)^\s*ren(?:ame)?\s+([A-Za-z0-9_]+)\*\s+([A-Za-z0-9_]*)\*", open(src[0], encoding="latin-1").read()) if src else []
            for n in list(named):
                for a, b in pairs:
                    if n.startswith(b):
                        named.add(a + n[len(b):])
        hits = sorted((named & dropped) - done0)
        if hits:
            with open(KB if "KB" in globals() else f"{DELIV}/minimize/keep_back.txt", "a") as f:
                for v in hits:
                    f.write(f"{v}|named in the command that halted: {cmd.strip()[:120].replace('|', '/')}\n")
            print(f"put back {', '.join(hits)} (named in the halting command)")
            sys.exit(0)
if not m or m.group(1) not in dropped:
    # last resort: the do-file that halted (the last `do`/`include` of a package do-file before
    # the error); put back every dropped variable it names (structural-only, wildcard-only).
    # Errs on the side of keeping; each do-file can trigger this once.
    calls = [re.search(r'(?:do|include|run)\s+"?([^"]*?([^/"]+\.do))"?', l) for l in log[:first]
             if re.match(r"^(\.|\s+\d+\.)\s+(do|include|run)\s", l) and "master-directory" not in l]
    calls = [c for c in calls if c]
    base = calls[-1].group(2) if calls else None
    rows = list(load_workbook(VARUSAGE, read_only=True)["dropped"].iter_rows(values_only=True))
    H = rows[0]; iv, ic, ir = H.index("variable"), H.index("class"), H.index("referenced_in")
    done = {l.split("|")[0] for l in open(KB).read().split("\n")[1:] if l}
    hits = sorted({r[iv] for r in rows[1:] if base and r[ic] != "drop?" and base + ":" in (r[ir] or "")} - done)
    if not hits:
        print("halt not caused by a dropped variable:", "\n".join(log[max(0, first - 6):first + 1]))
        sys.exit(2)
    with open(KB, "a") as f:
        for v in hits:
            f.write(f"{v}|{base} halted ({(m.group(1) if m else 'error')} not found) and names it\n")
    print(f"put back {len(hits)} dropped variables named in {base}")
    sys.exit(0)
v = m.group(1)
# the command that halted: the last log line echoing a command before the error (". " or "  3. ")
ctx = next((re.sub(r"^\.?\s*\d*\.\s*", "", l).strip() for l in reversed(log[max(0, first - 40):first])
            if re.match(r"^(\. |\s+\d+\. )", l)), "")
with open(KB, "a") as f:
    f.write(f"{v}|run halted without it: {ctx[:150].replace('|', '/')}\n")
print(f"put back {v} (used at: {ctx[:100]})")
