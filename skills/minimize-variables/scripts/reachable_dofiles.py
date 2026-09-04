# _reachable_dofiles.py -- which do-files does the package's master actually run?
#
# A package folder can hold do-files that no master calls any more (dead code) or whose
# call is commented out in the master. Variables referenced only in such files are NOT used
# by the pipeline, so the minimisation must ignore those files. This script starts from the
# master do-file(s), strips comments, follows every `do`, `include` and `run` line
# (resolving $root / relative paths, and treating a macro inside a path -- table`x' -- as a
# wildcard), and prints the list of reachable do-files. Unreachable do-files are listed on
# stderr for the reviewer.
#
#   usage: _reachable_dofiles.py <release folder> <master1.do> [master2.do ...]
import sys, os, re, glob

release = sys.argv[1]
masters = sys.argv[2:]

def strip_comments(text):                       # same rules as the tokenizer: /* */, //, * lines
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    out = []
    for line in text.split("\n"):
        line = re.sub(r"//.*", "", line)
        if re.match(r"^\s*\*", line):
            continue
        out.append(line)
    return "\n".join(out)

CALL = re.compile(r'^\s*(?:qui\w*\s+|cap\w*\s+|noi\w*\s+)*(?:do|include|run)\s+"?([^"\n]+?)"?\s*(?:,.*)?$', re.M)

def resolve(path, from_dir):
    p = path.strip().replace("\\", "/")
    p = re.sub(r"\$\{?root\}?", release, p)     # $root / ${root}
    p = re.sub(r"`[^']*'", "*", p)                # table`x' -> table*
    if not p.endswith(".do"):
        p += ".do"
    if not os.path.isabs(p):
        p = os.path.join(from_dir, p)             # relative to the caller's folder (Stata's cwd = package root in practice)
        if not glob.glob(p):
            p = os.path.join(release, path.strip().replace("\\", "/").rstrip(".do") + ".do") if False else os.path.join(release, os.path.relpath(p, from_dir))
    return sorted(glob.glob(p))

seen, todo = [], list(masters)
while todo:
    f = todo.pop(0)
    if f in seen or not os.path.exists(f):
        continue
    seen.append(f)
    text = strip_comments(open(f, encoding="latin-1", errors="ignore").read())
    for m in CALL.finditer(text):
        for g in resolve(m.group(1), release):
            if g not in seen:
                todo.append(g)
for f in seen:
    print(f)
all_do = sorted(p for p in glob.glob(f"{release}/**/*.do", recursive=True) if "/ado/" not in p)
dead = [p for p in all_do if p not in seen]
sys.stderr.write(f"reachable: {len(seen)}  unreachable (ignored): {len(dead)}\n" + "".join("  " + os.path.relpath(p, release) + "\n" for p in dead))
