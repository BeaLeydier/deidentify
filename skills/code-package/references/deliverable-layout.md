# Deliverable layout, code folder and report skeleton (from practice)

## One folder per package, the audited package never touched
```
<PKG-deliverable>/
├── REPORT_<pkg>.md              external-facing (see skeleton below)
├── id_inventory.csv             the user's list of identifier variables and data structure (input)
├── code/                        every step, reviewable: master.do, config.do (all paths), numbered
│                                01..11 scripts (Stata where natural, Python where easier — commented
│                                block by block, pseudo-code style), ado/, README.md (step table)
├── audit/                       <pkg>_review_workbook.xlsx · _dta_list.txt · _intermediate/
├── minimize/                    varusage_review.xlsx · unreachable_dofiles.txt · _intermediate/
├── compare/                     <pkg>_comparison_workbook.xlsx · published_*.csv (inputs) · _intermediate/
├── logs/                        step logs; SHA-256 manifests BEFORE / AFTER / DIFF
└── run/                         <pkg>_run/ (the executed copy) · run wrapper · drop scripts ·
                                 RUN_COPY_EDITS.diff · outputs_before_minimize/ · outputs_after_minimize/
```
- **Integrity proof.** SHA-256 manifest of every file in the audited package, the
  crosswalk folder and any reference package, taken before work starts and again
  after it ends; identical manifests are the proof nothing was modified.
- **Run on a copy.** Path globals, backslash paths and similar edits go in the copy
  only, each logged in `RUN_COPY_EDITS.diff` (ignore carriage returns if the
  rewrite changed line endings). Redirect `sysdir set PLUS` to a scratch folder so
  the run cannot alter the user's Stata installation.
- **Private material** (watch lists of original ids, crosswalks) stays outside the
  deliverable, in a scratch folder.
- **Tidy at the end.** Every CSV a step writes is a workbook tab; move them into
  `_intermediate/` (kept so the workbook builder can re-run alone), delete files
  superseded by later rounds, keep the workbooks, the hand-transcribed inputs and
  the logs at the top level.

## Report skeleton (external-facing)
1. **Bottom line** — one table: unused variables (how many dropped, by type,
   pipeline re-run identical); original identifiers surviving (no, with the three
   tests); string-tail residue; PII shortlist (*indicative*: how many flagged, by
   reason, by redaction status, "needs a reviewer", where); other surfaces (notes,
   characteristics, value labels, whether code reads them); reproduction
   (cells matched / predicted differences); can a fresh replicator run it.
2. **Integrity of the audited folders** — the copy-and-manifest process.

The sections will then depend on the skills invoked int hat particular task. In general, there will be one section per skill. The below is only one example, which will depend based on skills applied.

3. **Variable minimisation** — reachable do-files, rules, classes, both rounds,
   the proof, where the drops concentrate.
4. **Identifier leak tests** — which variables were tested (the user's inventory;
   scan candidates the user accepted or rejected, with reasons), the watch-list
   size table with overlap, tests 1–3, text sweep.
5. **PII surfaces** — classifier rules and counts; notes/characteristics/labels
   with the decision the PIs must make.
6. **Reproduction** — tables, appendix, in-text, figures; each differing cell tied
   to the package's own change log.
7. **Defects and observations** — portability first, then housekeeping, then a
   positive note; fixes stated, not applied.
8. **Not done** · 9. **Folder index**.

No scoping paragraph, no instructions-to-self, no tooling bugs (those go to the
PI in chat). 

## Examples of defects to look for (report, do not silently fix)
Illustrations of the kind of defect a package may carry — not a checklist of
findings to expect in any particular package. These have been populated from practice, and can be updated in future versions of this skill.
- Windows backslash paths in do-files (`"$root\data\x.dta"`): r(601) on POSIX.
- `ssc install <pkg>` for a package that lives on the Stata Journal (e.g. `zanthro`
  → `dm0004_1`, `dropmiss` → `dm89_2`); an un-captured `which` after it stops the run.
- A bundled `ado/` folder (e.g. `some-command-master/`) never added to the adopath,
  so the code depends on a web install instead of the shipped copy.
- The release's root global pointing at the *internal* identified folder.
- An unexpanded macro left in a variable label (e.g. ``Value: `label_x' ``) —
  harmless to results, breaks naive label handling (sanitise backticks/quotes
  through Mata before writing labels to files).
