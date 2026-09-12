---
name: scramble-ids
description: >-
  Replace identifier variables in a dataset with scrambled substitutes via seeded
  one-to-one correspondence tables, keep those tables private, update the analysis
  code to the new IDs, and verify the scramble fail-loud. Use when someone wants
  to anonymize / scramble / pseudonymize ID variables (household, person, school,
  village, cluster codes) for PUBLIC release, build a crosswalk between old and new
  IDs, or make a package shareable without exposing real identifiers while keeping
  every result identical. Starts by diagnosing whether the code depends on id order
  or magnitude (cutoffs, order-derived numbering, position picks) and fixes that in
  the code or with banded scrambling. A strict 1-to-1 relabel leaves every regression, cluster, panel, and
  group statistic unchanged, so the scrambled data must reproduce the original's
  output exactly. Examples are in Stata (.do/.dta); the method is language-agnostic.
---

# Scramble IDs and update the code

A strict one-to-one relabel of an identifier is a bijection: clustering on a
renamed id gives identical SEs, an `xtset` on a renamed id is the same panel. So
if the map is a clean bijection, **every result is unchanged** — that is the
correctness guarantee you verify at the end. This may not be the case if the code uses
ID values, or ID orders, to make some operations. This skill first diagnoses this and updates
the code, so that a scrambling of the ID order does not affect the results. 

## Steps

`scripts/scramble_id.ado` is a standalone command (`adopath + "<scripts>"`, then
call it); `scripts/scan_id_order_dependence.py` is the diagnostic that comes
first; `scripts/verify_scramble.do` is an adaptable **template** you copy and
edit per package. This skill assumes the data are for **public release**: the map
is random. An order-preserving ("monotone") map would be trivially reversible by anyone
holding the original ids (one sort and a rank merge) and is not an option here.

0. **Diagnose whether the code depends on id order — before designing the map.**
   Run `scripts/scan_id_order_dependence.py OUT.csv "<id vars>" <reachable do-files>`
   (reachable = the files the master actually runs; see `minimize-variables`).
   It strips comments and classes every hit:
   - **A magnitude** — the id's value is compared or binned (e.g. `if regionid > 154`,
     `inrange(id,…)`, `recode id`). A random map breaks this.
   - **B numbering** — numbers derived from the id's sort order feed the code
     (`egen group(id)`, `tab id, gen()`, `encode`, `levelsof` with a counter) and
     the code then names them (e.g. `D_regionid_84`): dummy k is "the k-th smallest
     id", not an entity.
   - **C position** — a row is picked by position after sorting on the id (`sort id`
     then `_n`, `[1]`, `duplicates drop`, `collapse (first)`, `keep in`, `sample`).
   - **D invariant** — `bysort id:` sums, `xtset`, merge keys, `cluster(id)`,
     `i.id`: a 1-to-1 relabel cannot change these (listed for completeness).
   Most B/C hits are benign in practice; the scan says where to look, the
   **arbiter is empirical**: apply a random map to a copy, run the package, and
   compare every output with the pre-scramble run (`compare-code-results`,
   `compare_before_after.py`). Identical outputs = no dependence, done. Otherwise
   the differing tables name the do-files, and the fixes are, weakest first:
   - **banded scrambling** for a cutoff: with a cutoff at 154, say,
     `scramble_id … , cuts(154)` maps old values ≤ 154 and > 154 into two disjoint
     slices, randomly *within* each; rewrite the cutoff once to the slice boundary
     the program prints (e.g. `> 16000`). The cutoff survives; the order inside each
     band does not;
   - **ship the indicator instead of the rule**: replace the condition (`if id > 154`)
     or the numbered dummy (`D_regionid_84`) by a variable (e.g. `treated_region`,
     `cutoff_group`) built once from the original ids and shipped; rewrite the line
     to use it;
   - **rewrite order-derived numbering**: dummies by value from an explicit list
     (`gen d_x = id==<mapped value>`), loops over the mapped values;
   - **fix tie-breaking, not the map**: for example, an explicit rule instead of `duplicates drop`.
   Record which hits were found, which fix was applied, and the arbiter's result in
   the private processing readme. The public readme says nothing about the method.

1. **Build one correspondence table per ID — seeded, random, 1-to-1, new
   range.** Load the id's old values into a variable `oldval` (for an id spanning
   files, union them first: `clear; tempfile a; save `a', emptyok; foreach f in
   f1 f2 { use <id> using "`f'", clear; append using `a'; save `a', replace };
   rename <id> oldval`), `set seed N`, then call `scramble_id <newname> <lo> <hi>
   [, cuts(c1 c2 …)]` — it produces the `<id>,<id>_pubrep` table (a uniform random
   draw in the range, collisions redrawn), prints the Spearman rank correlation
   between old and new with its sampling SE (≈ 0 without bands) and errors if the
   range is too tight to stay 1-to-1. Each property has a reason:
   - **Seeded** (`set seed N`) — replicable.
   - **1-to-1** — a bijection; anything else changes counts/merges.
   - **Random, not order-preserving** — see step 0; bands only where a cutoff
     must survive.
   - **New range disjoint from the old if possible given the range of IDs**, so old and new can never be confused; store the new id as a wide integer type.
   - **Scramble composites and derived ids too.** A code built arithmetically from
     other ids (for example `region*10000 + unit*100 + seq`) reproduces those ids —
     scramble it through its own map. A derived id (for example one defined as
     `personid = hhid*100 + memberid`) can either be mapped or **reconstructed from
     the scrambled parts**: ask the user for each case, then record the decision.
   - **Keep the universe files** (every id value observed in the raw data, per
     family) next to the maps: they make the mapping reproducible and auditable.

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
   before rewriting. Then apply the renames into the release copy. Also apply any updates identified necessary in step 0. See
   `references/editing-dofiles.md` for the mechanics (read verbatim with Mata
   `cat()`, match ID names on `_`-aware word boundaries, write literal `$`/`"`).

5. **Verify — fail-loud, to one workbook.** Copy and adapt
   `scripts/verify_scramble.do` (a template — the datasets/keys/composite keys are
   package-specific). It runs, per id map, the 1-to-1 / new-range-disjoint checks
   and the **rank-retention** check (Spearman ρ between old and new; ≈ 0 expected,
   a high |ρ| means order was preserved and is reported as a weakness), plus a **whole-dataset diff over ALL variables** (not a pre-selected
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
