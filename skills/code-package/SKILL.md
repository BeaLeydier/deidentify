---
name: code-package
description: >-
  Orchestrate de-identification of a research code package for public
  release, then prove the cleaned package still reproduces its results. Use when
  someone wants to anonymize / de-identify / scramble IDs in a code
  package or dataset, remove PII before sharing data, prepare code files
  for a journal or repository (AEA, ICPSR, Dataverse, OSF), or verify that a
  cleaned package still reproduces published tables and figures. This is the
  top-level workflow; it sequences six focused skills (audit-pii, strip-pii,
  check-id-order, scramble-ids, minimize-variables, compare-code-results) and handles
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
restructured are their decisions. Every skill follows `shared/conventions.md`: every
step is a script in the deliverable's `code/`, all paths come from one config relative
to the project folder, packages install inside the project, one workbook per skill.

## Before you start — map the package

Build a shared picture before touching anything:
- **Identifiers and data structure — ask the user first.** Which variables
  identify people, households, places or units, in which files, at what level;
  which are parts of a composite key or derived from other ids by a rule; which
  are the same kind of id from two sources; the panel/time variables and the
  keys that link the files; any cutoff the code applies to an id. Record the
  answers in `id_inventory.csv` (`shared/id-inventory.md` gives the columns
  and the precedence rule). Every scan below produces *candidates* to add to this
  inventory; none of them overrides what the user listed. Without an inventory,
  run the scans, show the candidates, and ask again before any id is scrambled.
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
  met in practice. An example structure (each project may differ):
  ```
  <root>/            paper (if any) + top-level notes
  <pkg>_orig/        original package, never modified
  <pkg>_deid/        PUBLIC package (data, code, readme, bundled deps)
  <pkg>-deliverable/ report, code/ (every step as a reviewable script), subfolders for each skill, for example: audit/, minimize/, scramble/, strip/, compare. Also add logs/, run/ (the executed copy)
  <private>/         PRIVATE: crosswalks, watch lists of original ids (an internal
                     deliverable may hold the watch lists in a named subfolder)
  ```
- **Reachable code only.** Which do-files does the master actually run? Calls
  commented out of the master (e.g. GPS steps, R steps) and dead scripts must not
  count as uses. Which data is study data? Example datasets inside third-party
  `ado/` packages are excluded from every audit count.

## The pipeline: three tasks, in this order

Each task runs the cleaned copy of the package end to end once it has changed it — only to
check that it still runs; results are compared once, in task 3.

1. **Minimize** → **`deidentify:minimize-variables`**: keep only what the reachable code
   uses (static read), one drop round; re-run (the run decides: what it misses is put back).
   First, because every variable it drops is one the audit no longer has to look at.
2. **Audit PII and ids, then clean up**:
   - **audit** → **`deidentify:audit-pii`** (and **`deidentify:check-id-order`**) on the
     minimised data: the *before clean-up* workbook — PII shortlist, other surfaces, string
     tails; for ids, the code scan (does the code rely on id order?) and, if the ids are
     already scrambled, the id maps and leak tests;
   - **clean up**, with the user's decisions: **`deidentify:strip-pii`** for the confirmed
     PII, notes/characteristics, code defects; **`deidentify:scramble-ids`** if ids must be
     (re)scrambled, the method chosen from the code scan; re-run;
   - **audit again**: the *after clean-up* workbook — the PII audit plus what the clean-up
     removed, and the id audit only if ids were scrambled in the clean-up.
3. **Compare** → **`deidentify:compare-code-results`**: (1) the original package against the
   cleaned one, every output file; (2) the cleaned package against the paper or the internal
   package.

## Finish — ship clean, and write two readmes

- **Ship clean:** delete generated outputs (figures, intermediates, logs) so the
  public package is inputs + code + readme + bundled dependencies only. Tidy the
  deliverable too: one workbook per skill and the hand-transcribed inputs, superseded
  files deleted.
- **Public code readme** (inside `<pkg>_deid/`): written for someone
  reproducing the results from this package — data, code, how to run, dependencies,
  expected outputs. Mention de-identification only in one line ("IDs are
  anonymized"); it should read like a normal code package, not a redaction
  log.
- **A new `CHANGES.txt`** (inside the public package): the previous one updated for this
  release — the per-dataset table of variables kept out of the original count recomputed
  after the drop, statements the audit found wrong corrected — plus a section listing every
  code line changed (file, line, before, after), so the package carries one complete record
  of its changes rather than separate diff files.
- **Private processing readme** (with the processing code, never shipped): the
  full audit trail — what counted as PII and how each field was handled, the
  scramble design and seed, variables dropped, any section omitted and why, the
  result→code map, and where the private key tables live.

## Output convention
Every skill writes one review workbook (summary with a `result` cell, full row-level
tabs, reviewer columns) — `shared/conventions.md` §2.
