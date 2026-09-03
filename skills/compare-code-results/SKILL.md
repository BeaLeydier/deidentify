---
name: compare-code-results
description: >-
  Verify that a cleaned/rebuilt code package still reproduces results, by
  comparing every estimate side-by-side against an original package's output
  and/or a published paper, with a full table plus summary statistics on how many
  match and differ. Use when someone wants to check a de-identified or modified
  package reproduces the original, compare two sets of regression results, verify
  outputs against a paper's tables, or diff coefficients/standard-errors/p-values
  across package versions. Covers extracting a paper's numbers from a PDF into a
  table first, then comparing. Examples are in Stata (.do/.dta); the method is
  language-agnostic.
---

# Compare code results systematically

Confirm the cleaned package reproduces results. Two comparisons, both producing a
full side-by-side table **and** a summary — never just a headline check.

## Get the numbers out of each package

Ask the user for the **old/original** package folder and the **new/cleaned** one,
then run both. Capture results in whichever mode fits:

- **Output-to-output (preferred).** If the package *saves* its results —
  `.tex`/`.csv`/`.txt` tables, saved matrices/estimates, logs — run both packages
  and **diff the output files directly**. A clean rebuild should make them
  identical apart from any renamed ids. No transcription, no re-derivation.
- **Capture-from-commands (when results aren't saved, or aren't text).** Many
  packages only print to a log. Then instrument the analysis script **verbatim**:
  insert lines after each estimation that write that command's own results
  (coefficients, SEs, p-values, N, R², test stats) to a table — see
  `scripts/capture_estimates.md`. Do **not** re-implement the estimations in your
  own reorganized code; you would be testing your code, not the package. Generate
  the instrumented copy programmatically from the real script so it is provably
  "the script + saves", and re-issue any display-only result's exact internal
  computation to capture it.

## Compare against a published paper (if one exists)

First **extract the paper's numbers into a table** — transcribe every printed cell
once into a CSV with metadata (`key, exhibit, panel/model, row, stat, decimals,
value`) via a small script that hard-codes each value, so it is checkable and
re-runnable. Flag tables that are not based on the data and have **no producing code**
as "not from data". Then compare as below. Comparing to a paper is weaker than
output-to-output (the paper may be rounded or predate a correction), so document
any package-vs-paper gap rather than assuming the package is wrong.

## Run the comparison (systematic, every estimate)

Build **one row per number** with its metadata and stat type (coef / SE / p /
N / R² / test), for **all** of them — not the headline few. Then merge the two
tables on a shared key and run `scripts/compare_tables.py REF.csv NEW.csv OUT_DIR`:
it differences **at the reported precision** (a cell matches when the new value
rounds to the reference; small float noise ignored) and writes **one review
workbook** `comparison_review.xlsx`:
- a `full` tab — every cell side-by-side: reference, new, difference, `status`
  (exact / differs / missing), and an **empty `reason` column to fill per mismatch**.
- a `summary` tab — totals and breakdown: # exact, # differ, # missing, `result`,
  and counts by stat type — the eyeball-able bottom line.

It **exits nonzero** when any cell differs or is missing, so a discrepancy can't be
missed by not reading the log.

Systematic coverage is the point: it catches what a spot-check misses (a single
mis-captured statistic, or a handful of cells that differ for a documented reason).
For every differing cell, record a specific `reason` — a rounding boundary, an
estimator/software version effect, or a genuine data difference — so the report
explains itself.

## Account for the whole paper, both directions
Some code produces extras not in the published subset (note them); some sections
need external data the package doesn't ship (obtain and clean it, or document what
can't be reproduced and why). A script's internal table numbering is often offset
from the published numbering — map by content, not label.

## If it's Stata and a run halts
Consult the runnability catalogue in the **`deidentify:scramble-ids`** skill
(`references/stata-runnability.md`) — the mechanical old-code→modern fixes.
