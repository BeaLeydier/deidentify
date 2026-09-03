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

**Callable programs (put the scripts dir on the adopath, then call by name):**
`adopath + "<this skill>/scripts"` makes `scramble_id`, `union_of`, `verify_idmaps`,
and `cmp_og_deid` available.

1. **Build one correspondence table per ID — seeded, monotonic, 1-to-1, new
   range.** Load the id's old values into a variable `oldval` (use `union_of <id>
   "f1.dta" "f2.dta"` for an id spanning files), then call
   `scramble_id <newname> <lo> <hi>` — the engine that produces the `<id>,<id>_pubrep`
   table (it exits with an error if the range is too tight to stay 1-to-1). Each
   property has a reason:
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
   before rewriting. Match ID names on word boundaries treating `_` as a word
   char (so `groupid` doesn't match inside `sub_groupid`). Then apply the renames
   into the release copy, plus mechanical runnability fixes so old code runs on a
   current version — see `references/stata-runnability.md` (also covers two real
   traps when editing a dofile programmatically).

5. **Verify — fail-loud, to files.** Call `verify_idmaps, keys("<dir>")
   idspec("<id> <lo> <hi> ; <id2> <lo> <hi>")` for the per-map checks (1-to-1,
   monotonic, new range disjoint) and `cmp_og_deid, orig(<file>) deid(<file>)
   key(<key>) allowdiff(<redacted vars>)` for the **whole-dataset diff over ALL
   variables** (not a pre-selected subset) — which *shows* the only changes are the
   renamed ids plus any intended redaction, and catches silent corruption (e.g. a
   stray `_merge`). For the original↔deid diff, first merge the idmap into the
   original so both share the scrambled key; **align by that key, never by row
   position** — merges re-sort, so `_n`-alignment reports false mismatches. Also
   confirm no original id variable remains (`confirm variable X, exact`). Each
   program writes a per-check CSV **and** a `*_summary.csv` with a `result` column,
   and on failure drops a `*_FAILED.flag` sentinel. **Detection contract:** check
   the sentinel / the `result` column — **do not** rely on the process exit code,
   because Stata batch mode returns 0 even on `exit 459` (that `exit` still halts an
   in-Stata do-file chain). (Python steps elsewhere in the suite *do* exit nonzero.)

6. **Smoke-test the run.** Run the updated package end-to-end once to confirm it
   still executes after the ID swap (fix runnability halts via the reference).
   This is an "it runs" check; the numeric proof is `compare-code-results`.

## Output convention
Every export is systematic: the full ID-reference review sheet and the full
`verify_results` (one row per check) **plus** a summary (checks passed/failed,
maps built, datasets touched).
