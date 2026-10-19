#!/usr/bin/env python3
"""compare_tables.py -- systematic side-by-side comparison of two result tables.

Compares a REFERENCE table (original package's output, or a paper's transcribed
numbers) against a NEW table (the cleaned package), one row per estimate, at the
reference's reported precision. Emits a full cell-by-cell table AND a summary.

Both CSVs must share a `key` column and a numeric `value` column. Optional columns
are carried through from REFERENCE for context: `decimals` (reported precision, per
row), `stat` (coef/se/p/N/R2/test), and any metadata (exhibit, panel, row, ...).

Usage:
    python3 compare_tables.py REF.csv NEW.csv WORKBOOK.xlsx [NAME] [--tol=1e-9]
    (writes tabs <NAME>_summary and <NAME> of WORKBOOK; NAME defaults to `tables`)

Language-agnostic: produce the two CSVs from any tool (Stata `export delimited`,
R `write.csv`, pandas). A cell matches when the new value rounds to the reference
value at `decimals` places (if given), else when |diff| <= tol.
"""
import csv, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path[:0] = [HERE, os.path.join(HERE, "..", "..", "..", "shared")]
from xlsx_sheet import write_sheet

def load(path):
    rows = {}
    with open(path, newline="") as f:
        for r in csv.DictReader(f):
            rows[r["key"]] = r
    return rows

def num(x):
    try: return float(x)
    except (TypeError, ValueError): return None

def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    tol = 1e-9
    for a in sys.argv[1:]:
        if a.startswith("--tol"): tol = float(a.split("=",1)[1]) if "=" in a else tol
    if len(args) < 2:
        sys.exit("usage: compare_tables.py REF.csv NEW.csv WORKBOOK.xlsx [NAME] [--tol=1e-9]")
    ref, new = load(args[0]), load(args[1])
    xlsx = args[2] if len(args) > 2 else "comparison_review.xlsx"
    name = args[3] if len(args) > 3 else "tables"

    meta_cols = [c for c in next(iter(ref.values())).keys() if c not in ("value",)]
    keys = list(dict.fromkeys(list(ref) + list(new)))
    full, n_exact, n_diff, n_missing = [], 0, 0, 0
    by_stat = {}
    for k in keys:
        r, nw = ref.get(k), new.get(k)
        rv = num(r["value"]) if r else None
        nv = num(nw["value"]) if nw else None
        stat = (r or {}).get("stat", "")
        if r is None or nw is None or rv is None or nv is None:
            status, diff = "missing", ""
            n_missing += 1
        else:
            dec = (r.get("decimals") or "").strip()
            if dec != "":
                d = int(dec)
                matched = round(rv, d) == round(nv, d)
            else:
                matched = abs(nv - rv) <= tol
            diff = nv - rv
            status = "exact" if matched else "differs"
            n_exact += matched; n_diff += (not matched)
        s = by_stat.setdefault(stat or "(none)", [0,0,0])
        s[0 if status=="exact" else 1 if status=="differs" else 2] += 1
        row = {c: (r or {}).get(c, "") for c in meta_cols}
        row.update({"key": k, "reference": (r or {}).get("value",""),
                    "new": (nw or {}).get("value",""), "difference": diff,
                    "status": status, "reason": ""})
        full.append(row)

    cols = ["key"] + [c for c in meta_cols if c != "key"] + ["reference","new","difference","status","reason"]
    summ = [["total cells", len(full)], ["exact", n_exact], ["differs", n_diff],
            ["missing (one side)", n_missing],
            ["pct exact", round(100*n_exact/max(1, len(full)-n_missing), 2)],
            ["result", "PASS" if not (n_diff or n_missing) else "REVIEW"], ["", ""],
            ["by stat", "exact / differs / missing"]]
    summ += [[st, f"{e} / {d} / {m}"] for st, (e, d, m) in sorted(by_stat.items())]
    write_sheet(xlsx, f"{name}_summary", ["metric", "value"], summ)
    write_sheet(xlsx, name, cols, [[r.get(c, "") for c in cols] for r in full])

    print(f"compared {len(full)} cells: {n_exact} exact, {n_diff} differ, {n_missing} missing")
    print(f"wrote tabs {name}_summary, {name} -> {xlsx}")
    # Hard-fail (nonzero exit) so a difference cannot be missed by not reading the log.
    if n_diff or n_missing:
        print(f"FLAG: {n_diff} differing + {n_missing} missing cell(s) need review "
              f"(fill `reason` in the tab)")
        sys.exit(1)
    print("OK: every cell reproduces at the reported precision")

if __name__ == "__main__":
    main()
