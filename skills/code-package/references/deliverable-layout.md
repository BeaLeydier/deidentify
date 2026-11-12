# Deliverable layout, code folder and report skeleton (from practice)

## One folder per package, the audited package never touched
```
<PKG-deliverable>/
├── REPORT_<pkg>.md (+ .pdf)    external-facing (see skeleton below)
├── SETUP.md                     the set-up answers (what the job is, what was run)
├── id_inventory.xlsx            the ID inventory (map-ids): candidates, datasets, inventory, structure
├── code/                        every step, reviewable: run_all.sh (the master), config.do and
│                                _paths.py (every path, relative to this folder), numbered steps
│                                (Stata where natural, Python where easier — commented block by
│                                block), ado/ and the plugin tools used, requirements.txt, README.md
├── audit/                       <pkg>_audit_before_cleanup.xlsx · <pkg>_audit_after_cleanup.xlsx ·
│                                watchlists/ (private, internal only)
├── minimize/                    varusage_review.xlsx · dofiles.txt · datasets.txt · unreachable_dofiles.txt
├── compare/                     <pkg>_comparison_workbook.xlsx · published_*.csv (hand-transcribed inputs)
├── logs/                        one log per step; SHA-256 manifests BEFORE / AFTER / DIFF
└── run/                         <pkg>_run/ (the executed copy) · _ado/ (packages for the runs) ·
                                 RUN_COPY_EDITS.diff · outputs_<label>/ snapshots
```
- **Integrity proof.** SHA-256 manifest of every file in the audited package, the
  crosswalk folder and any reference package, taken by a script before work starts and
  again after it ends; identical manifests are the proof nothing was modified.
- **Run on a copy**, built by a script from the release: path globals, backslash paths
  and similar edits go in the copy only, each logged in `RUN_COPY_EDITS.diff`. Packages
  install into `run/_ado/` (`sysdir set PLUS` and `PERSONAL`), so the run neither uses
  nor alters the user's Stata installation — and a missing dependency shows up.
- **Private material** (watch lists of original ids, crosswalks) stays out of anything
  public: in the user's private folder, or in a named subfolder of an internal deliverable.
- **No intermediates to tidy:** tools write their tabs straight into the workbooks.

## Report skeleton (external-facing)
1. **Bottom line** — one table, columns *Task · Question · Answer*, one row per question the
   job answered, grouped by task: 1. minimize (unused variables: how many dropped, by type;
   does the minimised package run), 2. audit and clean up (does the code rely on id order;
   how much order the maps keep; do original ids survive; string-tail residue; the PII
   shortlist — *indicative*: how many, by reason, "needs a reviewer"; notes and
   characteristics; can a fresh replicator run it), 3. compare (original against cleaned
   package; cleaned package against the paper / internal package). Only the rows of the
   tasks the set-up chose.
2. **Integrity of the audited folders** — the copy-and-manifest process, where packages
   were installed, what was run.
3. **Task 1 — Minimize** — reachable do-files, rules, classes, the drop, what the run put
   back, where the drops concentrate.
4. **Task 2 — Audit, then clean up** — the id audit (does the code rely on id order: code
   scan and maps; leak tests), the PII audit before the clean-up, the clean-up and the
   defects it fixes, the PII audit after it.
5. **Task 3 — Compare** — original against cleaned package; cleaned package against the
   reference, each differing cell tied to the package's own change log.
6. **Not done** · 7. **Folder index**.

No scoping paragraph, no instructions-to-self, no tooling bugs (those go to the
PI in chat). 

## Defects to look for (report, do not silently fix)
The list of portability defects met in practice is in
`compare-code-results/references/running-and-capturing.md`.
