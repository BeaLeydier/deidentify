# deidentify — code de-identification skills

A Claude Code plugin: a suite of focused skills for de-identifying research
code packages and datasets, and for proving a cleaned package still
reproduces its results. Skills are language-agnostic in method; examples are shown
in Stata (`.do`/`.dta`).

Each skill produces **one review workbook** (`.xlsx` with tabs — a summary, detail,
and columns for the reviewer to fill) rather than scattered files, and flags fail
*hard*: Python tools exit nonzero; Stata programs write a `result` cell and a
`*_FAILED.flag` sentinel (Stata batch always returns OS exit 0). Requirements: Stata
16+ for the `.ado`/`.do` tools; Python 3 with **pandas + openpyxl** for the
workbook builders, plus **Pillow + numpy** and poppler's `pdftoppm` for the figure
comparison. Every step of an audit is meant to live as a reviewable script in the
deliverable's `code/` folder (see `skills/code-package/references/deliverable-layout.md`).

## Skills

| Skill | Invoke as | Purpose |
|---|---|---|
| Orchestrator | `/deidentify:code-package` | Maps the package and sequences the five skills below, then ships clean + writes the two readmes. |
| Audit PII | `/deidentify:audit-pii` | Classify every variable (identifier / likely PII / other) with `pii_classify`, summarise the other surfaces (notes, characteristics, value labels), scan string-tail bytes, and, with the private crosswalks (if the user has access to them), prove no original id survives. One review workbook. Read-only. |
| Strip PII | `/deidentify:strip-pii` | Drop or overwrite confirmed PII with a clean overwrite (no residual "ghost tail"). |
| Scramble IDs | `/deidentify:scramble-ids` | Seeded 1-to-1 ID correspondence tables (kept private), code update, fail-loud verification. |
| Minimize variables | `/deidentify:minimize-variables` | Keep only variables the reachable code uses (comments ignored); class each variable by how it is used; drop in two rounds, each proven by re-running; `referenced_in` per variable. |
| Compare results | `/deidentify:compare-code-results` | Compare every estimate vs the original package and/or a paper (tables, appendix, in-text numbers, same-machine figures, before/after a change), full table + summary in one workbook. |

Each skill is independently useful (e.g. `audit-pii` on any dataset) and
auto-triggers on its own description. The orchestrator ties them together.


## Versions

Version 1.0: From experience deidentifying an AEJ paper replication package, outline the different skills and corresponding references.
Version 2.0: Apply the skill to two other paper replication packages (AER, QJE) and update the references, ado files and instructions with new use cases. 