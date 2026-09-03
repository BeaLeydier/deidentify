---
name: scramble-ids
description: >-
  Replace identifier variables in a dataset with scrambled substitutes via seeded
  one-to-one correspondence tables, keep those tables private, update the analysis
  code to the new IDs, and verify the scramble fail-loud. Use when someone wants
  to anonymize / scramble / pseudonymize ID variables (household, person, school,
  village, cluster codes), build a crosswalk between old and new IDs, or make a
  package shareable without exposing real identifiers while keeping every result
  identical. A strict 1-to-1 relabel leaves every regression, cluster, panel, and
  group statistic unchanged, so the scrambled data must reproduce the original's
  output exactly. Examples are in Stata (.do/.dta); the method is language-agnostic.
---

# Scramble IDs and update the code

A strict one-to-one relabel of an identifier is a bijection: clustering on a
renamed id gives identical SEs, an `xtset` on a renamed id is the same panel. So
if the map is a clean bijection, **every result is unchanged** — that is the
correctness guarantee you verify at the end.

## Steps

`scripts/scramble_id.ado` is a standalone command (`adopath + "<scripts>"`, then
call it); `scripts/verify_scramble.do` is an adaptable **template** you copy and
edit per package.

1. **Build one correspondence table per ID — seeded, monotonic, 1-to-1, new
   range.** Load the id's old values into a variable `oldval` (for an id spanning
   files, union them first: `clear; tempfile a; save `a', emptyok; foreach f in
   f1 f2 { use <id> using "`f'", clear; append using `a'; save `a', replace };
   rename <id> oldval`), then call `scramble_id <newname> <lo> <hi>` — the engine
   that produces the `<id>,<id>_pubrep` table (it errors if the range is too tight
   to stay 1-to-1). Each property has a reason:
   - **Seeded** (`set seed N`) — replicable.
   - **1-to-1** — a bijection; anything else changes counts/merges.
   - **Monotonic (order-preserving), not a random shuffle** — analysis code often
     has sort/`_n`/threshold logic (`sort id; gen first=_n<4; drop if id>K`); a
     random permutation silently changes which rows those pick. Order-preservation
     keeps every such operation identical while values are unrecognizable.
   - **New range disjoint from the old**, similar magnitude/digit-count — so old
     and new can never be confused; store the new id as a wide integer type.

2. **Respect ID relationships (this is where correctness lives):**
   - **Same-universe IDs share one map** — if two variables are the same kind of
     id from different sources, map both through one table so an entity gets the
     same new id in both.
   - **IDs in several datasets use a UNION map** — build from the union of values
     across *every* file holding the id, so the same entity is consistent
     everywhere; a map built from one file drops rows on merges elsewhere.
   - **Composite keys are free** — mapping each part as a bijection keeps every
     (part1,part2) pair consistent; no special handling.

3. **Apply and save keys privately.** Merge each map in, drop the original id,
   keep the new one, re-declare anything that referenced it (panel/sort/merge
   keys). Save the public datasets to the release copy; save each key table
   (`old,new`) with the processing code — **the key is the re-identification
   crosswalk and is never shipped**.

4. **Update the analysis code — flag, then apply.** Scan the analysis script and
   export every line that references an ID *variable* or a hardcoded ID *value*
   (`if hhid==149`) to a review sheet (`lineno, original, proposed`) for the user
   before rewriting. Then apply the renames into the release copy. The rename is a
   pure relabel — **do not assume the code is old or needs modernizing**; before
   publication it is usually concurrent, current-Stata code that runs as-is. See
   `references/editing-dofiles.md` for the mechanics (read verbatim with Mata
   `cat()`, match ID names on `_`-aware word boundaries, write literal `$`/`"`).

5. **Verify — fail-loud, to one workbook.** Copy and adapt
   `scripts/verify_scramble.do` (a template — the datasets/keys/composite keys are
   package-specific). It runs, per id map, the 1-to-1 / monotonic / new-range-disjoint
   checks, plus a **whole-dataset diff over ALL variables** (not a pre-selected
   subset) that *shows* the only changes are the renamed ids plus any intended
   redaction, and catches silent corruption (e.g. a stray `_merge`). For that diff,
   first merge the idmap into the original so both share the scrambled key, and
   **align by that key, never by row position** — merges re-sort, so `_n`-alignment
   reports false mismatches. It writes ONE workbook (`verify_review.xlsx`: sheets
   `idmap_checks`, `dataset_diffs`, `summary` with a `result` cell) and, on failure,
   drops a `verify_FAILED.flag` sentinel. **Detection contract:** check the sentinel /
   the `result` cell — **not** the process exit code, because Stata batch returns 0
   even on `exit 459` (that `exit` still halts an in-Stata do-file chain).

6. **Smoke-test the run.** Run the updated package end-to-end once
   (`stata-se -b do <master>.do`) to confirm it still executes after the ID swap.
   Concurrent code usually runs unchanged; in the rare case a run halts on a Stata
   version issue, the modernization catalogue lives in the **`deidentify:compare-code-results`**
   skill. This is an "it runs" check; the numeric proof is `compare-code-results`.

## Output convention
Every export is systematic: the full ID-reference review sheet and the full
`verify_results` (one row per check) **plus** a summary (checks passed/failed,
maps built, datasets touched).
