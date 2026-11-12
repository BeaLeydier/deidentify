# deidentify — code de-identification skills

A Claude Code plugin: a suite of focused skills for de-identifying research
code packages and datasets, and for proving a cleaned package still
reproduces its results. Skills are language-agnostic in method; examples are shown
in Stata (`.do`/`.dta`).

Each skill produces **one review workbook** (`.xlsx`: a summary with a `result` cell,
full row-level tabs, columns for the reviewer to fill), written directly by the tools,
and fails loud (Python tools exit nonzero; Stata steps write `FAIL` in the `result` cell).
Every step of a project is meant to live as a reviewable script in the project's
`code/` folder, with all paths relative to the project and packages installed inside it,
so the whole audit re-runs from the project folder alone (`shared/conventions.md`).
Requirements: Stata 16+ for the `.ado`/`.do` tools; Python 3 with **openpyxl** (plus
poppler's `pdftoppm` for the pixel comparison of figures).

`shared/` holds what several skills use: the conventions, the ID-inventory spec, and
small standalone tools (`reachable_dofiles.py`, `compare_before_after.py`,
`xlsx_sheet.py`).

## Skills

| Skill | Invoke as | Purpose |
|---|---|---|
| Orchestrator | `/deidentify:code-package` | Asks what the job is (publish or audit; PII only or ids too; scramble or audit a scramble; what to compare with; drop unused variables), then runs only the skills needed, in order, and writes the records. |
| Map ids | `/deidentify:map-ids` | Build the ID inventory once, at set-up: the user's list or description of the ids, checked by a scan (id-like names, row-unique variables, same values in two files); without a list, the scan proposes candidates to accept or reject. Every other skill reads it. |
| Audit PII | `/deidentify:audit-pii` | Classify every variable (identifier / likely PII / other) with `pii_classify`, summarise the other surfaces (notes, characteristics, value labels) with `pii_surfaces`, scan string-tail bytes, and, with the private crosswalks (if the user has access to them), prove no original id survives. One review workbook. Read-only. |
| Check id order | `/deidentify:check-id-order` | Does the code use an id's value or order (static scan + random-relabel test)? How much order does an old→new map keep (rank correlation, overlap)? Before scrambling, to choose the method; after, to audit it. |
| Strip PII | `/deidentify:strip-pii` | Drop or overwrite confirmed PII with a clean overwrite (no residual "ghost tail"). |
| Scramble IDs | `/deidentify:scramble-ids` | Seeded 1-to-1 ID correspondence tables (kept private), code update, fail-loud verification. |
| Minimize variables | `/deidentify:minimize-variables` | Keep only variables the reachable code uses (comments ignored); class each variable by how it is used; static read of the do-files (case-sensitive, literal macros filled in, `gen` targets ignored); drop in one round, proven by re-running; `referenced_in` per variable. |
| Compare results | `/deidentify:compare-code-results` | Compare every estimate vs the original package and/or a paper (tables, appendix, in-text numbers, same-machine figures, before/after a change), full table + summary in one workbook. |

## Install

Through the Claude Code plugin manager (one-time `add`, then updates via `/plugin update`):

```
/plugin marketplace add BeaLeydier/deidentify
/plugin install deidentify@deidentify
```

Or as a plain folder of skills, kept current with `git pull`:

```
git clone https://github.com/BeaLeydier/deidentify ~/.claude/skills/deidentify
```

Each skill is independently useful (e.g. `audit-pii` on any dataset) and
auto-triggers on its own description. The orchestrator ties them together.

Every skill starts from an **ID inventory**, built once at set-up by `map-ids` from the user's own list or description — which variables
identify which entities, in which files, with which composite/derived rules, and how
the datasets link (`shared/id-inventory.md`). Scans of the
data only add *candidates* to that inventory; they never override it.


## Provenance

The method and the tooling were developed on, and tested against, several published
economics replication packages (Stata). Every package-specific detail was removed:
variable names, thresholds and defects quoted in the skills are illustrations of the
kind of thing to look for, not findings to check a given package against.
