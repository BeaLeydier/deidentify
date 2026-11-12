---
name: compare-code-results
description: >-
  Verify that a cleaned/rebuilt code package still reproduces results, by
  comparing every estimate side-by-side against an original package's output
  and/or a published paper, with a full table plus summary statistics on how many
  match and differ. Use when someone wants to check a de-identified or modified
  package reproduces the original, compare two sets of regression results, verify
  outputs against a paper's tables, in-text numbers or figures, or diff
  coefficients/standard-errors/p-values across package versions. Covers extracting
  a paper's numbers from a PDF into a table first, then comparing. Examples are in
  Stata (.do/.dta); the method is language-agnostic.
---

# Compare code results systematically

Conventions (every step a script in the project's `code/`, paths from one config, one
workbook with a `result` cell, loud failure): `shared/conventions.md`.

Confirm the cleaned package reproduces results. Two comparisons, no more:
1. **the original package against the cleaned one** — every output file of the package as
   received (run here, with only the edits needed to run it) against the cleaned package's
   (`shared/compare_before_after.py`): what the whole clean-up changed;
2. **the cleaned package against the reference** — the published paper, or the internal
   (identified) package run on the same machine: does it reproduce the results.
Intermediate runs during the work (after dropping variables, after a code fix) only check
that the package runs end to end; their outputs are not compared. Every comparison produces a
full side-by-side table **and** a summary — never just a headline check — and all
of them end up in **one comparison workbook** (tabs: summary, tables, appendix,
in-text, figures, before-vs-after).

## Get the numbers out of each package

Ask the user for the **old/original** package folder and the **new/cleaned** one,
then run both (on copies — never edit a package in place; log every edit needed
to make it run as a diff). Capture results in whichever mode fits:

- **Output-to-output (preferred).** If the package *saves* its results —
  `.tex`/`.csv`/`.txt` tables, saved matrices/estimates, logs — run both packages
  and **diff the output files directly**. Normalise Windows line endings first: a
  reference built on Windows differs from a macOS run in every line by CRLF alone
  and is otherwise byte-identical. A clean rebuild should be identical apart from
  renamed ids.
- **Capture-from-commands (when results aren't saved, or aren't text).** Many
  packages only print to a log. Instrument the analysis script **verbatim** —
  see `scripts/capture_estimates.md`. Do **not** re-implement the estimations.

## Compare against a published paper (if one exists)

First **transcribe the paper's numbers into a CSV**, one row per cell
(`table, panel, row, col, stat, value`), main text and appendix both, and keep
that CSV as a deliverable (it is an input, not an intermediate). Then parse the
package's `.tex`/`.xml` and match each cell, at the paper's printed precision,
into `MATCH` / `MATCH (display rounding: ±1 in the last digit)` / `DIFFERS` /
`NOT FOUND`, with a `note` column. Read the package's own change log first —
a well-kept `CHANGES.txt` predicts the differing cells (an order-dependent
estimator such as UJIVE; a corrected imputation) and the report should say
"predicted" rather than "unexplained". Comparing to a paper is weaker than
output-to-output (rounding, corrections after publication); document a gap, do
not assume the package is wrong.

**In-text numbers** count too: pair every in-text log the package writes with the
sentence it supports (`scripts/compare_intext.py` with a hand-written mapping
CSV, kept as an input: log, regex that extracts the statistic, which occurrence, paper value,
sentence, line). Logs with no sentence quoting their value are listed without a
verdict.

## Figures

Byte- or pixel-comparing PDFs is only meaningful when **both were produced on the
same machine**: across machines, font family and page scaling alone change 4–7 %
of pixels and every byte, hiding or faking a data difference. So when the
reference figures were built elsewhere, re-run the reference package's *figure
code* locally and compare against that rendering with
`scripts/compare_figures.py REF_DIR NEW_DIR <workbook> <work dir>`: identical content streams
and 0.0000 % differing pixels is the standard. Stata's `.gph` working files embed
timestamps and in-memory object handles that differ on every run; ignore those
lines (`compare_before_after.py` does).

## Original against cleaned package

Snapshot the output folders of the original package's run and of the cleaned package's run, and compare every
file with `shared/compare_before_after.py BEFORE_DIR AFTER_DIR <workbook> [tab]` (text
outputs with timestamps stripped, PDFs/EPS on content, `.gph` on content minus Stata's
object handles). "N of N identical, 0 differ, 0 missing" is the proof that the clean-up
altered nothing; full-precision exports differing only beyond the 6th significant digit are
"same up to numerical precision" — say so, do not call them identical.

## Run the comparison (systematic, every estimate)

For two estimate tables with a shared key, `scripts/compare_tables.py REF.csv
NEW.csv <workbook> [name]` differences at the reported precision and writes tabs
`<name>` (every cell, with an empty `reason` column) and `<name>_summary`; it
exits nonzero on any difference. For every differing cell record a specific
reason — the checklist is in `references/running-and-capturing.md` (rounding boundary,
package version, documented correction, id-order dependence, an adaptation made to run,
a genuine data difference). For id-order dependence, `check-id-order` says where.

## Account for the whole paper, both directions
Some code produces extras not in the published subset (note them); some sections
need external data or software the package doesn't ship. Script table numbering is often offset from the published one — map by content.

## Running the two packages (they may differ)
`references/running-and-capturing.md` covers running Stata headless, the runnability-fix
catalogue, the portability defects to report (not silently fix) and capture gotchas.
