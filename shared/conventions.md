# Conventions every skill follows

Each skill keeps a two-line summary of these rules and points here. The scripts in this
folder are shared tools: each runs on its own and needs nothing else from the plugin.

## 1. Reproducible from the project folder

- **Every step is a script saved in the project** — in the deliverable's `code/` folder —
  *before* it runs. Nothing is run from a Claude session scratchpad, `/tmp`, a temporary
  directory or a one-off shell line that is not saved. A step done by hand (copying a
  folder, editing a path, taking a checksum) is a script too.
- **One config holds every path**, derived from where the `code/` folder sits (in Stata:
  `c(pwd)` when the step is run from `code/`; in Python: `__file__`). No absolute path to a
  user's home, Dropbox or a temp folder appears anywhere else. Moving the project folder
  must not break anything.
- **Third-party packages are installed inside the project** (Stata: `sysdir set PLUS` and
  `PERSONAL` to a folder of the deliverable, e.g. `run/_ado/`), never taken from, or written
  to, the user's own installation. A run that only works because a package happens to be
  installed on this machine has a defect to report (an installer that misses a dependency).
- **Python requirements are listed** in `code/requirements.txt`; Stata's version and the
  path to its executable are stated in `code/README.md`.
- **One master runs everything in order** (`code/run_all.sh`, or `master.do` when every
  step is Stata), from a fresh copy of the inputs to the final workbooks.
- **Check before handing over:** run the master end to end, then search `code/` for
  `/tmp`, `scratchpad`, `/Users/`, `C:/Users` and `Dropbox` — only the config may name the
  project's own folders, and only relative to itself.
- **Private material stays private.** Re-identification keys (crosswalks, watch lists of
  original ids) live in a folder the user names; never in a public package. A deliverable
  folder that is itself internal may hold them, in a clearly named subfolder.

## 2. Outputs: one workbook per skill, nothing pre-filtered

- Every result lands in a **file**, never only in a log. Each skill writes **one review
  workbook** (`.xlsx`): a `README` tab saying how to read the others, a `summary` tab
  with a `result` cell (`PASS` / `FAIL` / `REVIEW`), and full row-level tabs (every
  variable / estimate / flag — nothing pre-filtered), with empty columns for the
  reviewer's decisions where one is needed.
- Tools **write their tabs straight into the workbook** (Stata: `export excel …,
  sheet("x") sheetreplace`; Python: `shared/xlsx_sheet.py`). No intermediate CSVs to
  assemble afterwards; a large evidence dump (e.g. every residue cell) may be a side CSV.
- **Failure is loud:** Python tools exit nonzero; Stata steps write `FAIL` in the
  `result` cell and stop a do-file chain with `exit 459`. Stata batch mode always returns
  OS exit code 0, so read the `result` cell (or the log's `r(…)` lines), not the exit code.

## 3. Running Stata headless

```bash
"/Applications/Stata/StataSE.app/Contents/MacOS/stata-se" -b do FILE.do
```
- The log lands in `FILE.log` in the working directory; an error that halted the run is a
  line `r(NNN);` — `grep -nE "^r\([0-9]+\);" FILE.log`.
- Stock macOS has no `timeout`; use the tool's own timeout.

## 4. Work on copies, prove it changed nothing

Never write to the audited or original package. Every change happens in a copy, every edit
to a do-file is logged as a diff, and a SHA-256 manifest of the source folders taken before
and after the work shows they were not touched. Align any two datasets by their key, never
by row position (`merge` re-sorts).
