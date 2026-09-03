---
name: replication-package
description: >-
  Orchestrate de-identification of a research replication package for public
  release, then prove the cleaned package still reproduces its results. Use when
  someone wants to anonymize / de-identify / scramble IDs in a replication
  package or dataset, remove PII before sharing data, prepare replication files
  for a journal or repository (AEA, ICPSR, Dataverse, OSF), or verify that a
  cleaned package still reproduces published tables and figures. This is the
  top-level workflow; it sequences five focused skills (audit-pii, strip-pii,
  scramble-ids, minimize-variables, compare-replication-results) and handles
  package mapping and release packaging around them. Examples are shown in Stata
  (.do/.dta); the method is language-agnostic (R/Python/SAS apply the same way).
---

# De-identify a replication package (orchestrator)

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
  shipped in, the public package:
  ```
  <root>/            paper (if any) + top-level notes
  <pkg>_orig/        original package, never modified
  <pkg>_deid/        PUBLIC package (data, code, readme, bundled deps)
  work/              processing code, ID key tables (PRIVATE), audit reports, logs
  ```

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
   the code uses; report what was dropped per dataset.
5. **Compare results** → invoke **`deidentify:compare-replication-results`**. Run the cleaned
   package and compare every estimate against the original package's output and/or
   the paper, with a full side-by-side table plus a summary.

## Finish — ship clean, and write two readmes

- **Ship clean:** delete generated outputs (figures, intermediates, logs) so the
  public package is inputs + code + readme + bundled dependencies only.
- **Public replication readme** (inside `<pkg>_deid/`): written for someone
  reproducing the results from this package — data, code, how to run, dependencies,
  expected outputs. Mention de-identification only in one line ("IDs are
  anonymized"); it should read like a normal replication package, not a redaction
  log.
- **Private processing readme** (with the processing code, never shipped): the
  full audit trail — what counted as PII and how each field was handled, the
  scramble design and seed, variables dropped, any section omitted and why, the
  result→code map, and where the private key tables live.

## Output convention (applies to every skill here)

Every report is **systematic**: a complete row-level table (every variable /
estimate / flag, nothing pre-filtered) **and** a summary block (counts, % differing,
# flagged, pass/fail). Eyeball-able and summarizable, both.
