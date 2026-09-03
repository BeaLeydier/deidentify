---
name: audit-pii
description: >-
  Systematically detect direct personally-identifying information in a dataset or
  a folder of data files, and export a flag report to confirm with a human. Use
  when someone wants to check/scan/audit data for PII, find personal information
  in variables, confirm a dataset has no identifiers before sharing, or verify
  that a de-identified file is actually clean. Covers surfaces a value-scan misses:
  value labels, variable labels/names, dataset notes and characteristics, and the
  hidden residual bytes stored after a string's terminator. Read-only (it detects,
  it does not modify) -- run it to decide what to remove, and again afterward to
  confirm removal. Scope is DIRECT disclosure only (a value that is itself
  identifying), not statistical/re-identification risk. Examples are in Stata
  (.do/.dta); the method is language-agnostic.
---

# Audit a dataset for direct PII

Read-only detection of information that directly identifies a person/household/
place. It has two jobs: **discover** what must be removed (before stripping), and
**confirm** nothing remains (after). It does not change data.

## Steps

1. **Enumerate every PII surface — not just cell values.** Walk the full checklist
   in `references/pii-surfaces.md` (string values; PII-bearing numerics like
   national IDs, phone, GPS, exact dates; value labels; variable labels and names;
   dataset label, notes, characteristics; embedded file paths; other files in the
   package). Put `scripts/` on the adopath and call `list_pii_surfaces, stub(<name>)
   outdir(<dir>)` on a Stata dataset: it writes **one review workbook**
   (`<name>_review.xlsx`) with a `summary` tab (counts), a `variables` tab listing
   every variable with **empty `is_pii` and `action` columns for the reviewer to
   fill**, and an `identifiers` tab (see step 4b), plus a free-text dump
   (`<name>_dump.txt`: value labels, notes, `char`, keyword hits). Miss a surface and
   PII ships even after every string is redacted.

2. **Scan string-tail residue (self-contained), into the same workbook.** Run
   `scripts/scan_string_tails.py PATH.dta OUT_DIR --xlsx=<name>_review.xlsx` on every
   data file. It reads the bytes after each string's terminator — invisible to
   normal reads but present on disk — appends a **`string_tails`** tab to the review
   workbook (per-variable residue counts) and writes the full per-cell dump to a
   side `string_tails_full.csv` (evidence), exiting nonzero if any residue is found.
   Residue means a value-level scan is *not* enough and a clean-overwrite (strip-pii)
   is required.

3. **Run one PII detector — local only, your choice.** Pick a single detector
   appropriate to your tool; **never use anything that uploads data to a third
   party** (no cloud DLP/API). Options, all run locally: **Stata** `pii_scan`;
   **Python** `presidio-analyzer`, `scrubadub`, or a regex battery
   (email/phone/national-ID/GPS-range); **R** a regex/`stringr` battery. Ask the
   user which one to implement (default to the native tool for the language in use),
   then run it on all files. Treat it as a noisy aid — it flags ordinary content
   too — so its output is reviewed, not obeyed.

4. **Cross-reference known identifier values (strongest confirmation).** When the
   original, pre-de-identification data is available, search every shipped byte for
   any original name/id/value: `strings FILE | grep -Ff known_values.txt`, or grep
   the raw file. "No original identifier appears anywhere in the released files" is a
   specific proof, not a heuristic — make it the backbone of the *confirm* pass.
   - **Building `known_values.txt` (who/how):** the data owner creates it from the
     ORIGINAL data — export the distinct values of the confirmed-PII fields and the
     original id variables, one value per line (in Stata, e.g. `keep <pii/id vars>`,
     reshape/stack to one column, `export delimited ... , novarnames`). It is the
     re-identification "watch list"; keep it private, never ship it.

4b. **Identifier / linkage review (FYI, not a flag).** The `identifiers` tab of the
   review workbook lists variables whose name looks like an id/code/key and any
   variable that **uniquely identifies rows** (alone, or the id-named set jointly).
   This is *not* a pass/fail — it is for a human to confirm that the keys shipped in
   the release belong there and do **not** invite linkage: a unique id (or a
   combination that is unique) could be merged with an external dataset that still
   holds PII (checklist item D2). Judge combinations beyond the id-named set by hand;
   the tab flags the candidates.

5. **Hand the user ONE workbook to confirm.** The `<name>_review.xlsx` from steps
   1–2 *is* the confirm sheet: its `variables` tab lists every variable with the
   `is_pii` / `action` columns to fill and the `string_tails` tab flags residue; the
   `summary` tab gives the counts. The user marks the columns in that single file —
   that confirmed list is the input to `strip-pii`. (Fold any extra surfaces from
   the dump, or other files, into the same workbook as more tabs.) Numeric variables
   especially need human judgment
   (an id vs an analysis value), so present, don't decide.

## Notes

- **Direct disclosure only.** Flag values that *are* identifying. Do not attempt
  k-anonymity / combination-based re-identification risk here.
- **Run twice.** Once to build the strip list; once after strip-pii + scramble-ids
  to confirm the released files are clean (surfaces enumerated, tails clean,
  detector clear, no known value found).
- **Other file types.** Apply the same value/label/metadata checks to CSV/Excel/
  text; for images/PDFs check embedded metadata (e.g. `exiftool` for EXIF/GPS/author).
