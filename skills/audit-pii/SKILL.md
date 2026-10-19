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

Read-only detection of information that directly identifies a person, household or
place. Two jobs: **discover** what must be removed (before stripping), and **confirm**
nothing remains (after). Everything lands in **one review workbook** whose PII verdicts
are *indicative* — a person decides, in the `is_pii` / `action` columns.

Conventions (every step a script in the project's `code/`, paths from one config, tabs
written straight into the workbook, loud failure): `shared/conventions.md`.

**Start from the user's ID inventory** (`shared/id-inventory.md`): which variables are
identifiers, of which entity. It feeds `idkeys()`, `idvars()` and `$IDVARS_<family>`
below. Ask for it before scanning. What the scans find on their own (id-like names,
row-unique variables, family words) is reported as *candidates* to accept or reject; it
never reclassifies a listed variable.

**Study data only.** Example datasets shipped inside third-party `ado/` folders
(`auto.dta`, `florentine.dta`, …) are not study data: leave them out of the dataset list
and say so in the report. List the study datasets one per line (`datasets.txt`, paths
relative to the package root); list the do-files the master runs with
`shared/reachable_dofiles.py`.

## Steps

Put `scripts/` on the adopath (or copy the tools into the project's `code/`).

1. **Classify every variable** —
   `pii_classify, datasets(datasets.txt) root(<pkg>) workbook(<wb>) idkeys("<inventory>")`
   writes tabs `likely_pii` (direct terms first, empty `is_pii`/`action`),
   `other_variables` and `identifiers`. Rules (chosen so the shortlist stays short — a
   bare keyword match flags far too much):
   - inventory identifiers → `identifier`, their own tab, never PII candidates;
   - a direct-identifier term in name or label (name, dob/birth, address,
     phone/contact/mobile, national id/cnic, gps/latitude/longitude/coord, email, caste),
     an adjacent lat/lon **pair**, or value labels that read like free text / mention a
     direct term → `likely_pii`;
   - byte and numeric variables, strings holding numbers, time slots (`hh:mm`), strings
     whose label says count/amount/score, strings without content → `other`;
   - remaining strings **with content** → `likely_pii` ("other (specify)" is just a
     string: flagged only when it carries content);
   - `keyword_hit` carries a broad keyword list (school, village, child, house, …) for
     information only; `other_variables` lists those rows first.
   Never use a detector that uploads data to a third party.

2. **Summarise the other surfaces** —
   `pii_surfaces, datasets(datasets.txt) root(<pkg>) workbook(<wb>) dofiles(dofiles.txt)
   idvars("<inventory>")` writes tabs `pii_surfaces` (per dataset: notes and their size,
   hand-written vs machine-generated characteristics — reshape/xi/tsset leave `ReS_*`,
   `__xi__*`, `_TS*` —, value-label sets and flagged entries, variable labels with a
   direct term, labels or notes holding a file path), `dataset_notes` (full text),
   `value_label_flags` and `id_candidates`, and reports whether any do-file **reads**
   notes or characteristics (if none does, they can be removed without touching the
   code). Notes are free text: report their amount and let the PIs decide. The checklist
   of surfaces is `references/pii-surfaces.md`.

3. **Scan string-tail residue** — `scripts/scan_string_tails.py <wb> datasets.txt <pkg>`.
   Stata stores a fixed-width string with a terminator byte; the bytes after it are
   invisible to normal reads but stay on disk and can hold fragments of earlier values
   (a plain `replace` does not clear them). Tab `string_tails`; exits nonzero on residue,
   which means a value-level scan is not enough and a clean overwrite (strip-pii) is needed.

4. **Prove no original identifier survives (when crosswalks exist).** Ask whether the
   old → new crosswalks are available; without them, rely on 1–3 and say so. With them,
   copy and adapt `scripts/id_leak_tests.do` (globals for the data, crosswalks, private
   watch-list folder, families and the inventory's variables):
   - **Watch lists** per family: ALL OLD, ALL NEW, OLD-ONLY (old ids that are never a
     legal new value). Report the sizes: the overlap says how informative the test is —
     a width-preserving scramble can make most old ids legal new values, and then the
     test is read in aggregate. The lists are a re-identification key: keep them private.
   - **Test 1, membership**, per listed variable over distinct values: `n_outside_image`
     (must be 0, unless it is a derived id whose rule you then verify row by row) and
     `n_in_old_only` (must be 0), beside `expected_hits_if_unscrambled` — "0 observed
     against tens of thousands expected" is the argument when the overlap is large.
   - **Test 2**, digit-only strings ≥ 10,000 against every family's old-only set.
   - **Test 3, old id elsewhere in the row**: each row's old id recovered through the
     crosswalk and compared with every other column; a column equal on ≥ 99 % of its
     non-missing rows *and* on ≥ 10 rows is an old-id column kept by mistake (a few
     coincidental equalities are noise).
   - **Text files** — `scripts/scan_text_files.py <wb> <watch dir> <pkg> "<families>"`:
     whole-number tokens in every text file against the old-only lists; ≥ 5-digit hits
     are distinctive, shorter ones ambient numbers.
   How much *order* a map keeps (rank correlation) is checked by **check-id-order**.

5. **Hand the user the workbook**, with a `README` tab saying how to read each tab and a
   `summary` tab with the counts and a `result` cell. In the report, describe the PII
   shortlist as *indicative* and point to the tab; state plainly what is proven
   (identifiers, residue) and what needs judgement (free text).

## Notes

- **Direct disclosure only.** No k-anonymity here.
- **Run twice**: once to build the strip list; once after strip-pii, scramble-ids and
  minimize-variables, on the *minimised* data, so the shortlist is as short as it can be.
- **Author/RA names and file paths** are not PII (they are publicly attached to the
  paper; root paths are edited per machine). A path that points somewhere it should not
  is a portability defect.
- **Other file types**: apply the same value/label/metadata checks to CSV/Excel/text; for
  images/PDFs check embedded metadata (e.g. `exiftool`).
