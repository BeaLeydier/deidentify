---
name: minimize-variables
description: >-
  Reduce a dataset to only the variables the package's own code actually uses, and
  report exactly what was dropped. Use when someone wants to keep only used/needed
  variables, drop unused columns before sharing data, shrink a release dataset, or
  remove extra survey columns a paper never touches. This is both a privacy win
  (raw extracts carry columns the analysis never uses -- open-ended text, GPS,
  enumerator notes) and housekeeping. Builds the keep-list from ALL scripts
  (construction + analysis), keeps ID/merge/sort keys, and proves nothing broke by
  re-running. Examples are in Stata (.do/.dta); the method is language-agnostic.
---

# Minimize variables to what the package uses

Shipping only the used columns removes exposure (a raw extract can carry hundreds
of columns the results never touch) and shrinks the package. The risk is dropping
something used indirectly, so build the keep-list from the code and prove it by
re-running.

## Steps

1. **Build the keep-list from ALL code, not just the analysis file.** A variable
   may exist only to build another, so scan construction/cleaning scripts too.
   Put `scripts/` on the adopath and call `find_used_variables, dofiles("<a.do
   b.do>") datasets("<x.dta y.dta>") outdir(<dir>) alwayskeep("<id patterns>")`. It
   tokenizes every script and, per dataset, writes a review CSV (`varusage_<name>.csv`:
   each variable marked used/how) plus a `varusage_summary.csv` (kept vs candidates
   to drop per dataset). It is deliberately **conservative — when unsure, keep**.

2. **Always keep the structural variables** even if they look unused: ID variables
   (and their scrambled versions) and anything needed to **merge, sort, or set a
   panel**. Dropping one of these breaks the pipeline silently.

3. **Review the "unused" list with the user before dropping.** Tokenizing misses
   variables reached only through macros/globals, loops, wildcard (`ds`) logic, or
   `merge ... , keepusing()` — so the flags are a *proposal*, not a verdict. Drop
   from the **release copy only**, never from source files.

4. **Confirm by re-running.** The real test is the full run: if the keep-list is
   wrong, the package errors on a missing variable. A clean end-to-end run (and an
   unchanged `compare-code-results` result) is the proof that minimization
   broke nothing.

## Output convention (systematic report)

Emit a **dropped-variable report** with both levels:
- **Full:** one row per (dataset, variable) with its disposition — `kept-used`,
  `kept-structural`, or `dropped` — and where in the code it was (or wasn't) seen.
- **Summary:** per dataset, counts of kept vs dropped (and total columns removed),
  so the reduction is visible at a glance.

Record the report in the private processing readme.
