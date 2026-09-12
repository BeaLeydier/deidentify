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
  used, keeps ID/merge/sort keys, drops in two rounds and proves nothing broke by
  re-running. Examples are in Stata (.do/.dta); the method is language-agnostic.
---

# Minimize variables to what the package uses

Shipping only the used columns removes exposure (a raw extract can carry
hundreds of columns the results never touch) and shrinks the package. The risk is dropping something used
indirectly, so build the keep-list from the code and **prove it by re-running**.

## Steps

1. **Only the do-files the master reaches count.** A folder can hold dead
   scripts and calls commented out of the master (steps that cannot run on
   public data, steps from other languages or old code). `scripts/reachable_dofiles.py <release> <master.do …>`
   follows every `do`/`include`/`run` line from the master, comments stripped,
   `$root`/macro paths resolved, and prints the reachable list (unreachable ones on
   stderr). `scripts/make_links.sh` builds a space-free symlink tree of those files
   and of the datasets (the ado splits its lists on spaces).

2. **Build the keep-list with `find_used_variables`.** Put `scripts/` on the
   adopath; `find_used_variables, dofiles("…") datasets("…") outdir(<dir>)
   alwayskeep("<id / merge / sort / panel key patterns>")` — the variables of the
   user's ID inventory (`code-package/references/id-inventory.md`), not names
   guessed from the data. It tokenises the reachable
   do-files with comments removed (`// …`, `* …` lines, `/* … */` blocks across
   lines) and marks a variable *used* if referenced by exact name, a wildcard/glob
   (e.g. `t_*_irt`, `*_va`, `x*_q1`), a macro-built name (e.g. ``s`i'_q`j' `` → `s*_q*`),
   an `a-b` range, a `reshape` stub, a `renpfix` prefix, or a `keepusing()` list —
   a `*` glued to a name (`x*100`) also registers its literal pieces. The
   `variables` tab of `varusage_review.xlsx` gives per variable: `how`,
   `referenced_in` (dofile:line of each use, up to 20), `calc_context` and
   `calc_via` (is it computed with, directly, through a pattern, or under the name
   it acquires through `rename A* B*` or a rename to a fixed name such as
   ``rename q`x'_s`y' income``), and `class`:
   - `used-calc` — computed with somewhere (gen, egen, regressions, collapse,
     reshape, merge/sort keys, …);
   - `structural-only` — named only in structural commands (keep, drop, order,
     rename, keepusing, format, label, …); includes one *pattern anchor* per
     wildcard family whose every member is otherwise droppable, so a `keep x*`
     cannot become empty. Not dropped; flagged for the authors;
   - `wildcard-only-droppable` — reached only through wildcards/ranges that also
     match other variables (for example `drop sec4*`, `rename r1_* r_*`,
     `drop _merge*`), never in a calculation, also after renames. Droppable
     without breaking the code;
   - `always-keep`; `drop?` — referenced nowhere.

3. **Drop in two rounds, on the run copy, and let the pipeline arbitrate.**
   `scripts/drop_unused.do` (template; `$ROUND` 1 drops `drop?`, 2 drops
   `wildcard-only-droppable`; writes a manifest with type/label per variable).
   After each round run the package's master end to end and compare **every**
   output file with a snapshot taken before any drop (`compare-code-results`,
   `compare_before_after.py`): 0 errors and all files identical is the proof. When
   the run fails it names the construct the static scan missed; typical examples
   of such constructs, which the rules above cover, are a suffix wildcard
   (`*_va`), `reshape` stubs, a `*` used as multiplication, a rename to a fixed
   name, a family whose every member was droppable, and a tab-indented `cap drop`.
   Drop from the **release copy only**.

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
