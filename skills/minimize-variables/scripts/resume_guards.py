#!/usr/bin/env python3
# resume_guards.py LOG RUNCOPY DOFILES.txt
# Makes a retry of the minimised package cheap: the do-files that had already run to the end
# when the previous run halted (LOG) are skipped, so the retry starts again at the do-file that
# halted, on the files the earlier ones had built (the copy is refreshed, not rebuilt: see the
# loop in SKILL.md). Each skipped do-file gets `exit` as its first line, in the run copy only.
# Skipped: a do-file the log shows called once, before the one that halted, that calls no other
# do-file of its own (a master is never skipped: its do-files are, one by one) and sets up
# nothing for the session (no global, program, ado-path or install).
# A resumed pass is a shortcut, not the proof: once it runs through, the loop runs the package
# one last time from a fresh copy, with nothing skipped.
import os, re, sys
LOG, RUNCOPY, DOFILES = sys.argv[1:4]
log = open(LOG, encoding="latin-1").read().split("\n")
first = next((i for i, l in enumerate(log) if re.match(r"^r\(\d+\);", l)), len(log))
dofiles = [l.strip() for l in open(DOFILES) if l.strip()]
bybase = {}
for f in dofiles:
    bybase.setdefault(os.path.basename(f), []).append(f)

CALL = re.compile(r'^\.?\s*(?:\d+\.)?\s*(?:(?:cap|qui|noi)\w*\s+)*(?:do|run|include)\s+"?([^"]+?\.do)"?\s*(?:,.*)?$')
calls = []
for l in log[:first]:
    if not re.match(r"^(\.|\s+\d+\.)\s", l):
        continue
    m = CALL.match(l)
    if m:
        calls.append(os.path.basename(m.group(1).replace("\\", "/")))
once = [b for b in calls if calls.count(b) == 1 and len(bybase.get(b, [])) == 1]

def is_master(path):
    """calls a do-file other than the set-up ones every do-file calls (those called many times),
    or sets up the session (globals, programs, the ado-path, installs): must run every time"""
    for l in open(path, encoding="latin-1"):
        if re.match(r"^\s*(?:(?:cap|qui|noi)\w*\s+)*(gl|glo|glob|globa|global|adopath|sysdir|program|net|ssc)\s", l):
            return True
        m = re.match(r'^\s*(?:(?:cap|qui|noi)\w*\s+)*(?:do|run|include)\s+"?([^"\n]+)', l)
        if m and calls.count(os.path.basename(m.group(1).strip().replace("\\", "/"))) <= 1:
            return True
    return False

PKGROOT = os.path.commonpath([os.path.dirname(f) for f in dofiles]) if all(os.path.isabs(f) for f in dofiles) else ""

def path_of(b):
    """the do-file in the run copy (DOFILES lists it in the package the list was made from)"""
    p = bybase[b][0]
    return os.path.join(RUNCOPY, os.path.relpath(p, PKGROOT) if PKGROOT else p)

skipped = []
for b in once[:-1]:                                    # the last one is where the run halted
    p = path_of(b)
    if not os.path.exists(p) or is_master(p):
        continue
    body = open(p, "rb").read()
    open(p, "wb").write(b"exit  // resume: this do-file ran to its end in the previous pass\n" + body)
    skipped.append(b)
print(f"resume at {once[-1] if once else 'the start'}: {len(skipped)} do-file(s) already run are skipped"
      + (": " + ", ".join(skipped) if skipped else ""))
