# Deliverable layout, code folder and report skeleton (from practice)

## One folder per package, the audited package never touched
```
<PKG-deliverable>/
├── REPORT_<pkg>.md (+ .pdf)    external-facing (see skeleton below)
├── id_inventory.csv             the user's list of identifier variables and data structure (input)
├── code/                        every step, reviewable: run_all.sh (the master), config.do and
│                                _paths.py (every path, relative to this folder), numbered steps
│                                (Stata where natural, Python where easier — commented block by
│                                block), ado/ and the plugin tools used, requirements.txt, README.md
├── audit/                       <pkg>_review_workbook.xlsx · watchlists/ (private, internal only)
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
1. **Bottom line** — one table: unused variables (how many dropped, by type,
   pipeline re-run identical); original identifiers surviving (no, with the three
   tests); string-tail residue; PII shortlist (*indicative*: how many flagged, by
   reason, by redaction status, "needs a reviewer", where); other surfaces (notes,
   characteristics, value labels, whether code reads them); reproduction
   (cells matched / predicted differences); can a fresh replicator run it.
2. **Integrity of the audited folders** — the copy-and-manifest process.

The sections then depend on the skills invoked in that particular task. In general, there will be one section per skill. The below is only one example, which will depend based on skills applied.

3. **Variable minimisation** — reachable do-files, rules, classes, the drop,
   the proof, where the drops concentrate.
4. **Identifier leak tests** — which variables were tested (the user's inventory;
   scan candidates the user accepted or rejected, with reasons), the watch-list
   size table with overlap, tests 1–2, text sweep; the order each map keeps
   (check-id-order: rank correlation, overlap) and where the code relies on it.
5. **PII surfaces** — classifier rules and counts; notes/characteristics/labels
   with the decision the PIs must make.
6. **Reproduction** — tables, appendix, in-text, figures; each differing cell tied
   to the package's own change log.
7. **Defects and observations** — portability first, then housekeeping, then a
   positive note; fixes stated, not applied.
8. **Not done** · 9. **Folder index**.

No scoping paragraph, no instructions-to-self, no tooling bugs (those go to the
PI in chat). 

## Defects to look for (report, do not silently fix)
The list of portability defects met in practice is in
`compare-code-results/references/running-and-capturing.md`.
