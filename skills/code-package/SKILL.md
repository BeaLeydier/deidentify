---
name: code-package
description: >-
  Orchestrate the de-identification or the PII audit of a research code package: asks
  the user what the job is (a private package to publish, or a public one to audit; PII
  only or ids too; scramble ids or audit an existing scramble; compare with a paper or an
  internal package), then runs only the skills that answers call for, in order, and
  writes one report. Use when someone wants to anonymize / de-identify / scramble IDs in
  a code package, remove PII before sharing data, prepare code files for a journal or
  repository (AEA, ICPSR, Dataverse, OSF), audit a released package for leftover PII, or
  verify that a cleaned package still reproduces published tables and figures. It
  sequences the plugin's focused skills (map-ids, minimize-variables, audit-pii,
  check-id-order, strip-pii, scramble-ids, compare-code-results). Examples are shown in
  Stata (.do/.dta); the method is language-agnostic (R/Python/SAS apply the same way).
---

# De-identify or audit a code package (orchestrator)

The invariant that makes this safe: **relabelling an id with a strict one-to-one map leaves
every regression, cluster, panel and group statistic unchanged**, so a correctly
de-identified package reproduces the original's own outputs. This skill does not do the
work itself: it asks what the job is, then invokes the focused skills that job needs, in
order. What counts as PII and how ids are handled are the user's decisions — check in with
the user between stages. Every skill follows `shared/conventions.md` (every step a script in
the deliverable's `code/`, paths relative to the project, packages installed inside it, one
workbook per skill).

## Set-up: ask, then plan

Ask these questions first, before running anything, and record the answers in the
deliverable (`SETUP.md`, and the matching settings in `code/config.do`), so `run_all.sh`
holds only the chosen steps and the report says what was run and why.

1. **Do you have a list or a map of the ids?** If yes: provide it, or describe it in words.
   If not: candidates will be proposed (id-like names, variables that identify rows,
   variables with the same values in two files) for you to accept or reject.
2. **Is this a private package you are getting ready to publish, or a public package you are
   auditing for leftover PII?**
3. **Are you interested in PII only, or in the ids too?**
4. **If ids:** do you want to scramble them, or to audit an existing scramble — and do you
   have the private crosswalk (old → new ids)? If neither, the code can still be checked for
   whether it depends on id order.
5. **Do you want to compare the results** with the published paper, with an internal
   (identified) package, both, or neither?
6. **Drop the variables the code never uses?** Default: yes when publishing; when auditing,
   they are listed as a recommendation, not dropped.

| answer | what runs |
|---|---|
| 1 — list given | **map-ids**: the list becomes the inventory; the scan only checks it |
| 1 — no list | **map-ids**: scan, the user accepts or rejects each candidate, then the inventory |
| 2 — publish | the full path below, on a copy that becomes the proposed release |
| 2 — audit | read-only: the audit and its findings; a cleaned copy only if the user asks for one |
| 3 — PII only | **audit-pii** without its id part; no check-id-order, no scramble-ids |
| 4 — scramble now | **check-id-order** mode 1 (code scan, then the relabel test) to choose the method, **scramble-ids**, then the id audit on the new maps |
| 4 — audit a scramble, crosswalk available | the id audit: code scan, id maps (check-id-order mode 2), leak tests (audit-pii step 4) |
| 4 — neither | the code scan only: does the code rely on id order? |
| 5 — paper / internal / both | **compare-code-results** against what was chosen |
| 6 — yes | **minimize-variables**, task 1 |

The ID inventory is settled once, at set-up, and not revisited: every later skill reads
`id_inventory.xlsx`.

Map the package too: which datasets are raw *sources* and which the code *builds* (a file
some script `save`s is built — clean the sources and let construction re-run); the master
script and the do-files it actually reaches (calls commented out of the master and dead
scripts do not count; example data inside third-party `ado/` folders is not study data); a
working **copy** of the package, never the audited folder, with a SHA-256 manifest of every
source folder taken before and after. `references/deliverable-layout.md` gives the
deliverable layout, the report skeleton and the defects met in practice.

## The run: three tasks, in this order

Each task that changes the package runs it end to end afterwards, only to check that it
still runs; results are compared once, in task 3.

1. **Minimize** (if question 6) → **`deidentify:minimize-variables`**: keep only what the
   reachable code uses (static read), one drop round, run; what the run shows is needed goes
   back. First, because every variable dropped is one the audit no longer has to look at.
2. **Audit, then clean up**:
   - **audit** → **`deidentify:audit-pii`** on the minimised data, and the id part chosen in
     question 4 (**`deidentify:check-id-order`**, audit-pii step 4): the *before clean-up*
     workbook;
   - **clean up** (when publishing, or when the user asks for a cleaned copy), with the
     user's decisions: **`deidentify:strip-pii`** for the confirmed PII and the notes; code
     defects; **`deidentify:scramble-ids`** if ids are to be (re)scrambled; run;
   - **audit again**: the *after clean-up* workbook — the PII audit plus what the clean-up
     removed, and the id audit only if ids were scrambled in the clean-up.
3. **Compare** → **`deidentify:compare-code-results`**: whenever a cleaned copy exists, the
   original package against it, every output file (the proof the clean-up changed nothing);
   and, as chosen in question 5, the cleaned package against the paper and/or the internal
   package.

## Finish — ship clean, and write the records

- **Ship clean:** delete generated outputs (figures, intermediates, logs) so the public
  package is inputs + code + readme + bundled dependencies only.
- **Public code readme** (inside the package): for someone reproducing the results — data,
  code, how to run, dependencies, expected outputs. De-identification gets one line ("IDs
  are anonymized"); it reads like a normal code package, not a redaction log.
- **A new `CHANGES.txt`** (inside the package): the previous one updated for this release —
  the per-dataset table of variables kept out of the original count recomputed after the
  drop, statements the audit found wrong corrected — plus a section listing every code line
  changed (file, line, before, after): one record of the package's changes.
- **Private processing readme** (with the processing code, never shipped): the full trail —
  the set-up answers, what counted as PII and how each field was handled, the scramble
  design and seed, variables dropped, sections omitted and why, where the private key
  tables live.
- **The report** (`references/deliverable-layout.md`): a bottom-line table with one row per
  question answered, each tagged with its task (1. minimize, 2. audit and clean up,
  3. compare), then one section per task.
