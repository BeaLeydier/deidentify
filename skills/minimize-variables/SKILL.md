---
name: minimize-variables
description: >-
  Reduce a dataset to only the variables the package's own code actually uses, and
  report exactly what was dropped. Use when someone wants to keep only used/needed
  variables, drop unused columns before sharing data, shrink a release dataset, or
  remove extra survey columns a paper never touches. This is both a privacy win
  (raw extracts carry columns the analysis never uses -- open-ended text, GPS,
  enumerator notes) and housekeeping. Builds the keep-list from the do-files the
  master actually runs (comments ignored), classes every variable by HOW it is
  used, keeps ID/merge/sort keys, drops in one round and proves nothing broke by
  re-running. Examples are in Stata (.do/.dta); the method is language-agnostic.
---

# Minimize variables to what the package uses

Conventions (every step a script in the project's `code/`, paths from one config, one
workbook, loud failure): `shared/conventions.md`. Keys come from the user's ID inventory
(`shared/id-inventory.md`).

Shipping only the used columns removes exposure (a raw extract can carry
hundreds of columns the results never touch) and shrinks the package. The risk is dropping something used
indirectly, so build the keep-list from the code and **prove it by re-running**.

## Steps

1. **Only the do-files the master reaches count.** A folder can hold dead
   scripts and calls commented out of the master (steps that cannot run on
   public data, steps from other languages or old code).
   `shared/reachable_dofiles.py <release> <master.do …> > dofiles.txt` follows every
   `do`/`include`/`run` line from the master, comments stripped, `$root`/macro paths
   resolved, and writes the reachable list (unreachable ones on stderr: save them for
   the report). List the study datasets the same way, one path per line, relative to
   the package root (`datasets.txt`; example data inside third-party `ado/` folders is
   not study data).

2. **Build the keep-list with `find_used_variables` — a static read of the do-files,
   nothing is run.** Put `scripts/` on the adopath;
   `find_used_variables, dofiles(dofiles.txt) datasets(datasets.txt) root(<release>)
   outdir(<dir>) alwayskeep("<id / merge / sort / panel keys>")` — the keys are the
   variables of the user's ID inventory, not names guessed from the data. It tokenises
   the reachable do-files with comments removed (`// …`, `* …` lines, `/* … */` blocks)
   and marks a variable *used* if referenced by exact name, a wildcard (`t_*_irt`,
   `*_va`), an `a-b` range, a `reshape` stub, a `renpfix` prefix or a `keepusing()`
   list. Three rules keep it from over-counting:
   - **case-sensitive** matching, as Stata's variable names are (`s*` does not reach
     `S_SEC8_q3`);
   - **macro-built names are filled in** where the do-file spells the values out
     (``forvalues i = 1/12``, ``foreach i in a b``, ``foreach i of numlist``, ``local L a b``)
     — ``hf`i'_q2`` becomes `hf1_q2 … hf12_q2`; values that come from the data
     (`r()`, `levelsof`, varlists, other files) leave a wildcard (``hf`i'_q2`` → `hf*_q2`);
   - **names the code creates match nothing**: the target of `gen`/`egen` cannot be an
     existing variable (`gen` fails if it exists), so ``gen s`x' = …`` protects no `s*`
     variable of the data — nor does the same macro-built name collecting those new
     variables elsewhere in that file (``local L `L' s`x'``). Right-hand sides and
     literal names/wildcards on other lines still count;
   - **two constructs prove nothing and are ignored**: a wildcard with no letter in its
     literal part (`**12`), and `rename * *_suffix`, which renames whatever happens to be
     in memory at that line. Exact and grouped renames (`rename a b`,
     `rename (a b) (c d)`) carry the new name's use back to the old one;
   - every member of an `a-b` **range** counts as used: a range follows the dataset's
     variable order, so dropping a member changes what it covers.
   The `variables` tab of `varusage_review.xlsx` gives per variable: `how`,
   `referenced_in` (dofile:line, up to 20), `calc_context`/`calc_via` (computed with,
   directly, through a pattern, or under the name it acquires through `rename A* B*`),
   and `class`:
   - `used-calc` — computed with somewhere (gen, egen, regressions, collapse, reshape,
     merge/sort keys, …), or named in an `if` condition of any command (`keep if age >= 6`);
   - `structural-only` — named only in structural commands (keep, drop, order, rename,
     keepusing, format, label, …); includes one *pattern anchor* per wildcard family
     whose every member is otherwise droppable, so a `keep x*` cannot become empty.
     Dropping one means editing those lines too; pattern anchors are not dropped, as
     removing the pattern would change what the command does to variables the code creates;
   - `wildcard-only-droppable` — reached only through wildcards/ranges that also match
     other variables, never in a calculation, also after renames;
   - `always-keep`; `drop?` — referenced nowhere.

3. **Drop in one round, on the run copy, and let the re-run arbitrate.** Copy
   `scripts/drop_unused.do` (template) into the project's `code/`: it drops `drop?` and
   `wildcard-only-droppable` (and `structural-only` with `$DROP_STRUCTURAL=1`, together
   with a project script that edits the lines naming them and lists every change), and
   writes the manifest as the `dropped` tab of the same workbook. Drop a structural-only
   variable only when every line naming it holds its literal name (a line that reaches it
   through a macro-built name, ``ch`x'_bmi``, cannot be edited safely) — keep the others. Snapshot the outputs
   of the run copy *before* the drop, run the package's master end to end after it, and
   compare every output file (`shared/compare_before_after.py`): 0 errors and all files
   identical is the proof. Inside a full de-identification (code-package) this run only
   checks the package still runs; the outputs are compared once, original against cleaned
   package, at the end. When the run halts it names what the static read missed (a
   macro-built name it could not fill in, a chain of renames): automate the put-back with
   `scripts/restore_missing.py` in a loop (rebuild the copy, drop, run; on a halt, put the
   variable back and go again), and list every variable put back, with the line that
   needed it, in the report. Outputs that differ only beyond the 6th significant digit
   (full-precision exports) are "same up to numerical precision"; say so, do not call
   them identical. Drop from the **release copy only**.

4. **Report both levels.** Per dataset: variables, kept, used-calc,
   structural-only, wildcard-only, dropped; per variable: the manifest with type,
   string flag and label ("other (specify)" is a string subset, not a separate
   type). List the `structural-only` variables separately: removing them means
   editing the code too, which is the authors' call — they can allow a much larger
   reduction.

## Notes
- Identifier, merge, sort, panel and time keys — the user's ID inventory — are
  `alwayskeep()` even when they look unused; a key the scan did not see used is
  still a key.
- A static scan is conservative by design; the re-run is the arbiter. Never skip it.
- Record the manifests in the private processing readme; the public readme says
  only that unused survey variables were removed.
