---
name: audit-pii
description: >-
  Systematically detect direct personally-identifying information in a dataset or
  a folder of data files, and export ONE review workbook for a human to confirm.
  Use when someone wants to check/scan/audit data for PII, find personal
  information in variables, confirm a dataset has no identifiers before sharing,
  or verify that a de-identified file is actually clean. Covers surfaces a
  value-scan misses: value labels, variable labels/names, dataset notes and
  characteristics, the hidden residual bytes after a string's terminator, and --
  when private id crosswalks exist -- proves no original identifier survives.
  Read-only (it detects, it does not modify): run it to decide what to remove,
  and again afterward to confirm removal. Scope is DIRECT disclosure only (a value
  that is itself identifying), not statistical/re-identification risk. Examples
  are in Stata (.do/.dta); the method is language-agnostic.
---

# Audit a dataset for direct PII

Read-only detection of information that directly identifies a person/household/
place. Two jobs: **discover** what must be removed (before stripping), and
**confirm** nothing remains (after). It never changes data, and everything it
finds lands in **one review workbook** whose PII verdicts are *indicative* — a
person decides, in the `is_pii` / `action` columns.

Scope the audit to **study data only**: example or mock datasets shipped inside
third-party `ado/` packages or scripts (for example, `florentine.dta`, `auto.dta`, …) are not
study data. Exclude them from the analysis, and  say so in the final report.

## Steps

1. **Enumerate every PII surface — not just cell values.** Walk the checklist in
   `references/pii-surfaces.md`. Put `scripts/` on the adopath and call
   `list_pii_surfaces, stub(<name>) outdir(<dir>)` on each dataset: per-dataset
   workbook (`variables`, `identifiers`, `summary` tabs) plus a free-text dump of
   value labels, notes and `char`. Then run `scripts/pii_surfaces_summary.do`
   (a template: set `$DATADIR $DTALIST $OUTDIR $CODEDIR`) for summary statistics on these
   other potential places for pii (allowing the human reviewer to decide whether to keep, drop, or investigate further): per dataset, the number and size of notes (full text exported to `dataset_notes.csv`), characteristics (machine-generated reshape/xi/tsset bookkeeping told apart from hand-written
   ones), value-label sets and entries with entries flagged for a direct term or
   long free text (`value_label_flags.csv`), variable labels with a direct term — and **whether any do-file reads notes or characteristics**
   (`notes_readers.txt`; if none does, notes can be removed without touching code).
   Dataset notes are free text and therefore can be a disclosure risk; report their amount and let the PIs decide.

2. **Scan string-tail residue.** 
In Stata, string variables are stored with a terminator byte; the bytes after that are invisible to normal reads, but they remain on disk and could contain values from previous versions of the dataset, as string commands do not overwrite the entire string, only the portion up to the terminator of the new value. A value-level scan is not enough to detect this residue.

Run
   `scripts/scan_string_tails.py PATH.dta OUT_DIR` on every data file (give each
   file its own OUT_DIR — the script writes a fixed file name). It reads the bytes
   after each string's terminator — invisible to normal reads, present on disk —
   and exits nonzero on residue. Residue means a value-level scan is *not* enough
   and a clean overwrite (strip-pii) is required.

3. **Classify every variable with `pii_classify` (same logic as `pii_scan`, but with more details).** Put
   `scripts/` on the adopath; per dataset:
   `pii_classify, out(<csv>) dataset(<label>) idkeys("<id glob list>") [append]`.
   One row per variable with `category` = `identifier` / `likely_pii` / `other`,
   the `reason`, `redaction_status` (content / single value / placeholder / missing
   code / empty), four sample values, and `keyword_hit`. The rules (chosen so the
   shortlist stays short: a bare keyword match flags far too much):
   - identifier keys (`idkeys()`) → `identifier`, their own tab, never PII candidates;
   - a direct-identifier term in name or label (name, dob/birth, address,
     phone/contact/mobile, national id/cnic, gps/latitude/longitude/coord, email,
     caste), a lat/lon **pair** of adjacent variables, or value labels that read
     like free text / mention a direct term → `likely_pii`;
   - byte and numeric variables, strings holding numbers, time slots (`hh:mm`),
     strings whose label says count/amount/score, strings without content → `other`;
   - remaining strings **with content** → `likely_pii`. 
   - `keyword_hit` carries `pii_scan`'s broad list (school, village, child, house,
     …) as information only; the `other_variables` tab is sorted so those rows come
     first. The keyword alone is not a criterion to be considered likely pii on its own.
   Never use a detector that uploads data to a third party. If `pii_classify` is not enough, other tools can be used (for example, `pii_scan` though it is in theory less complete than `pii_classify`). Note on `pii_scan` if it is used as a cross-check: it is not on SSC (J-PAL GitHub), writes malformed CSV rows for free text containing quotes/semicolons, and leaks tempvars until it hits Stata's 5,000-variable ceiling on wide files (`set maxvar 32767`).

4. **Prove no original identifier survives (when crosswalks exist).** Ask whether
   the old→new id crosswalks are available; without them,
   rely on 1–3 and say so. With them, run `scripts/id_leak_tests.do` (a template:
   globals for data, crosswalk folder, id families and their crosswalk columns):
   - **Which variables are identifiers.** Either ask the user for input on this, or perform your own scan with the rules below. A variable whose *name* carries a family
     word is a *candidate*; it is kept as an identifier only if numeric with more
     than two distinct values. 0/1 indicators that merely mention an id  keyword
     are content, not ids — list them as excluded, keep them out of the tests. Export the kept list.
   - **Watch lists.** Per family, from the crosswalk: ALL OLD, ALL NEW, and
     OLD-ONLY (old ids that are never a legal new value). Report the sizes: the
     **overlap** says how informative the test is. A width-preserving scramble can
     make 80 % of old ids legal new values; then a single value cannot be told
     apart and the test is read in aggregate. The same table reports the
     **rank retention** of each map — Spearman ρ between old and new over the
     crosswalk: ≈ 0 for a random relabel, ≈ 1 for an order-preserving map, which
     anyone holding the original ids reverses with one sort. Report a high ρ as a
     weakness of the release, not a pass. Keep the lists private — they are a
     re-identification key.
   - **Test 1, membership**, per identifier variable over *distinct values*:
     `n_outside_image` (not a legal new id; must be 0 unless the variable is a
     derived id whose rule you then verify row by row) and `n_in_old_only` (provably
     an old id; must be 0). Show `expected_hits_if_unscrambled` = n_distinct ×
     share old-only beside the observed count — "0 observed against tens of
     thousands expected" is the argument for families with a large overlap.
   - **Test 2, old id elsewhere in the row, column-wise**: recover each row's old
     id through the crosswalk (new → old) and compare every other column with it;
     flag a column equal on ≥ 99 % of its non-missing rows *and* on ≥ 10 rows — an
     `old_id` column kept by mistake, or a composite that embeds it. Expect many
     columns with one or two coincidental equalities; they are noise.
   - **Text files** (do, csv, txt, tex, log …; not binary): whole-token search for
     old-only ids, distinctive (≥ 5 digits) hits reported separately from
     two-to-four-digit ambient numbers. `.dta` are binary — that is what test 1
     is for; `strings | grep` on them is noise.

5. **Hand the user one workbook.** Assemble the CSVs into a single review workbook
   (see `code-package` for the builder pattern): `README` (how to read each tab),
   `summary`, `likely_pii` (highest risk first, `is_pii`/`action` to fill),
   `other_variables`, `identifiers`, `pii_surfaces`, `dataset_notes`,
   `value_label_flags`, `id_watchlist_sizes`, `id_crossref_numeric` (with a
   plain-language `verdict`), `id_crossref_string`, `id_mergeback_rowtest`,
   `string_tails`. In the report, describe the PII shortlist as *indicative* and
   point to the tab; state plainly what is proven (identifiers, residue) and what
   needs judgement (free text).

## Notes

- **Direct disclosure only.** Do not attempt k-anonymity here.
- **Run twice.** Once to build the strip list; once after strip-pii, scramble-ids
  and minimize-variables to confirm the released files are clean — on the
  *minimised* data, so the shortlist is as short as it can be.
- **Author/RA names and file paths** are not PII (they are publicly
  attached to the paper, and root paths are expected to be edited per machine).
- **Other file types.** Apply the same value/label/metadata checks to CSV/Excel/
  text; for images/PDFs check embedded metadata (e.g. `exiftool`).
