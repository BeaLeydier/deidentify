---
name: code-package
description: >-
  Orchestrate de-identification of a research code package for public
  release, then prove the cleaned package still reproduces its results. Use when
  someone wants to anonymize / de-identify / scramble IDs in a code
  package or dataset, remove PII before sharing data, prepare code files
  for a journal or repository (AEA, ICPSR, Dataverse, OSF), or verify that a
  cleaned package still reproduces published tables and figures. This is the
  top-level workflow; it sequences five focused skills (audit-pii, strip-pii,
  scramble-ids, minimize-variables, compare-code-results) and handles
  package mapping and release packaging around them. Examples are shown in Stata
  (.do/.dta); the method is language-agnostic (R/Python/SAS apply the same way).
---

# De-identify a code package (orchestrator)

Goal: produce a public package that (a) contains no re-identifying information
and (b) still reproduces every result. The invariant that makes this safe:
**relabeling an ID variable with a strict one-to-one map leaves every regression,
cluster, panel, and group statistic unchanged.** So a correctly de-identified
package must reproduce the *original package's own output* to the last decimal.

Work through the stages below, invoking the focused skill named at each step.
Check in with the user between stages — what counts as PII and how IDs are
restructured are their decisions.

## Before you start — map the package

Build a shared picture before touching anything:
- **Data lineage — source vs built.** Which datasets are raw *source inputs* and
  which are *constructed* by the package's own code? Trace from the code: a file
  some script `save`s is built; one only ever read is a source. De-identify the
  *sources* and let construction re-run; PII usually enters through raw sources.
- **Code roles.** Separate construction/cleaning code from analysis code, and
  find the master/driver script that sets paths and calls the rest in order —
  that run order is your comparison pipeline.
- **Verification target.** Decide now what the cleaned package will be checked
  against, in order of preference: the original package's **own saved outputs**
  (if it writes tables/logs), else the **published paper**. Check whether the
  analysis code saves results at all — many older packages only print to a log.
- **Folder layout.** Keep the re-identification key separate from, and never
  shipped in, the public package; work on a **copy** of the package, never on
  the audited folder, and take a SHA-256 manifest of every source folder before
  and after (identical manifests are the proof). `references/deliverable-layout.md`
  gives the deliverable/code-folder layout, the report skeleton and the defects
  met in practice. Below is an example structure for the deidentification folder. You may have a different one in each use case, but this is a reference point for information.
  ```
  <root>/            paper (if any) + top-level notes
  <pkg>_orig/        original package, never modified
  <pkg>_deid/        PUBLIC package (data, code, readme, bundled deps)
  <pkg>-deliverable/ report, code/ (every step as a reviewable script), subfolders for each skill, for example: audit/, minimize/, scramble/, strip/, compare. Also add logs/, run/ (the executed copy)
  scratch/           PRIVATE: watch lists of original ids, crosswalk exports
  ```
- **Reachable code only.** Which do-files does the master actually run? Calls
  commented out of the master (GPS steps, R steps) and dead scripts must not
  count as uses. Which data is study data? Example datasets inside third-party
  `ado/` packages are excluded from every audit count.

## The pipeline

1. **Audit PII** → invoke **`deidentify:audit-pii`**. Enumerate every PII surface across all
   files (string values, PII-bearing numerics, value labels, variable labels/
   names, notes/characteristics, hidden string-tail bytes, other files) and export
   a flag report for the user to confirm. Run it again at the end to confirm the
   cleaned package is clean.
2. **Strip PII** → invoke **`deidentify:strip-pii`**. For each confirmed PII field, drop it
   or overwrite with a user-confirmed placeholder — and clear the underlying bytes
   so no residue remains.
3. **Scramble IDs** → invoke **`deidentify:scramble-ids`**. Build seeded 1-to-1 ID
   correspondence tables (kept private), apply them, verify fail-loud, update the
   analysis code to the new IDs, and smoke-test that the package still runs.
4. **Minimize variables** → invoke **`deidentify:minimize-variables`**. Keep only variables
   the reachable code uses, in two rounds (unreferenced; wildcard-only never
   computed with), each proven by re-running the package and comparing every
   output file with a pre-drop snapshot. Do this **before** the confirm audit, so
   the PII shortlist is as short as it can be.
5. **Compare results** → invoke **`deidentify:compare-code-results`**. Run the cleaned
   package and compare every estimate against the original package's output and/or
   the paper — tables, appendix, in-text numbers, figures (same-machine
   rendering) — into one comparison workbook with a summary.
6. **Confirm audit** → `deidentify:audit-pii` again on the minimised, scrambled
   data: classifier shortlist, surfaces summary, residue, identifier leak tests.

## Finish — ship clean, and write two readmes

- **Ship clean:** delete generated outputs (figures, intermediates, logs) so the
  public package is inputs + code + readme + bundled dependencies only. Tidy the
  deliverable too: workbooks and hand-transcribed inputs at the top level,
  intermediates in `_intermediate/`, superseded files deleted.
- **Public code readme** (inside `<pkg>_deid/`): written for someone
  reproducing the results from this package — data, code, how to run, dependencies,
  expected outputs. Mention de-identification only in one line ("IDs are
  anonymized"); it should read like a normal code package, not a redaction
  log.
- **Private processing readme** (with the processing code, never shipped): the
  full audit trail — what counted as PII and how each field was handled, the
  scramble design and seed, variables dropped, any section omitted and why, the
  result→code map, and where the private key tables live.

## Output convention (applies to every skill here)

Assume **no one reads the log**. Every result lands in a **file**, in two forms: a
complete row-level table (every variable / estimate / flag, nothing pre-filtered)
**and** a summary CSV (counts, % differing, # flagged, `result` PASS/FAIL). Screen
output stays only as documentation to fold into the readme.

**Fail detection contract:** a check that should be flagged fails *hard* — Python
tools **exit nonzero**; Stata programs write a `result,FAIL` row and drop a
`*_FAILED.flag` sentinel (Stata batch always returns OS exit 0, so never rely on
its exit code — the sentinel / `result` column is the signal, and `exit 459` still
halts an in-Stata do-file chain). Check the sentinel or the summary's `result`, not
the log.
