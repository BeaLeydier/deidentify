# deidentify — code de-identification skills

A Claude Code plugin: a suite of focused skills for de-identifying research
code packages and datasets, and for proving a cleaned package still
reproduces its results. Skills are language-agnostic in method; examples are shown
in Stata (`.do`/`.dta`).

Each skill produces **one review workbook** (`.xlsx` with tabs — a summary, detail,
and columns for the reviewer to fill) rather than scattered files, and flags fail
*hard*: Python tools exit nonzero; Stata programs write a `result` cell and a
`*_FAILED.flag` sentinel (Stata batch always returns OS exit 0). Requirements: Stata
for the `.ado`/`.do` tools; Python 3 with **openpyxl** (`pip install openpyxl`) for
the `.py` tools' workbook output.

## Skills

| Skill | Invoke as | Purpose |
|---|---|---|
| Orchestrator | `/deidentify:code-package` | Maps the package and sequences the five skills below, then ships clean + writes the two readmes. |
| Audit PII | `/deidentify:audit-pii` | Detect direct PII across all surfaces (values, PII numerics, value labels, variable labels/names, notes/characteristics, hidden string-tail bytes, other files); export a flag report. Read-only. |
| Strip PII | `/deidentify:strip-pii` | Drop or overwrite confirmed PII with a clean overwrite (no residual "ghost tail"). |
| Scramble IDs | `/deidentify:scramble-ids` | Seeded 1-to-1 ID correspondence tables (kept private), code update, fail-loud verification. |
| Minimize variables | `/deidentify:minimize-variables` | Keep only variables the code uses; report what was dropped per dataset. |
| Compare results | `/deidentify:compare-code-results` | Compare every estimate side-by-side vs the original package and/or a paper, full table + summary. |

Each skill is independently useful (e.g. `audit-pii` on any dataset) and
auto-triggers on its own description. The orchestrator ties them together.

## Use it locally

This folder is a plugin: with a `.claude-plugin/plugin.json` present, Claude Code
loads it automatically from `~/.claude/skills/deidentify/` as `deidentify@skills-dir`
— no install step. Edit any `SKILL.md` and it reloads in-session; after changing
`plugin.json` or adding a skill, run `/reload-plugins` or restart.

## Share with collaborators (later)

Push this folder to a **private** git repo. Collaborators either:
- add it as a marketplace and install — `/plugin marketplace add <repo-url>` then
  `/plugin install deidentify@deidentify-marketplace` (update the placeholder URL
  in `.claude-plugin/marketplace.json` first); or
- clone the repo and symlink it into their `~/.claude/skills/`.

Nothing is public unless the repo is made public and its URL shared — a marketplace
is just a manifest in a repo you control, not a listing visible to other users.

## Before publishing
- Set the real repo URL in `.claude-plugin/marketplace.json`.
- Add a `LICENSE` and fill in `author`/`homepage` in `plugin.json`.
- Confirm no real data or PII is committed — only code and synthetic demo files.
