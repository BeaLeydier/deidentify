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

Conventions (every step a script in the project's `code/`, one workbook, loud failure):
`shared/conventions.md`. `scripts/scramble_id.ado` is a standalone command
(`adopath + "<scripts>"`, then call it); `scripts/verify_scramble.do` is a **template**
you copy and adapt per package. This skill assumes the data are for **public release**:
the map is random. An order-preserving ("monotone") map is trivially reversible by anyone
holding the original ids (one sort and a rank merge) and is not an option here.

Everything starts from the **ID inventory** (`id_inventory.xlsx`, built once at set-up by
the **map-ids** skill; without one, run map-ids first): which
variables are ids, of which entity, in which files, which are parts of a composite key or
derived by a rule, which pairs are the same kind of id from two sources, and which cutoffs
the code applies. Ask for it before touching the data. The data can suggest additions (a
variable that uniquely identifies rows, two variables with identical value sets) — put
them to the user; a scan never decides on its own what an id is or that two ids share a
universe.

0. **Decide the method with `check-id-order` first.** It scans the code for uses of an
   id's value or order (cutoffs, numbering by rank, picks by position) and runs the
   empirical test (random relabel on a copy, run, compare every output). Identical
   outputs → fully random maps. Otherwise it names the fixes: a banded map for a cutoff
   (`scramble_id …, cuts()` below), a shipped indicator, explicit numbering, a tie-break.
   Apply the code fixes in the release copy and record them in the private notes.

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

2. **Respect ID relationships (this is where correctness lives)** — as declared
   in the inventory, confirmed with the user:
   - **Same-universe IDs share one map** — if two variables are the same kind of
     id from different sources (the inventory's `same_as`), map both through one
     table so an entity gets the same new id in both. Identical value sets in the
     data are a reason to *ask* whether two variables share a universe, not a
     reason to merge their maps.
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

5. **Verify — to one workbook.** Copy and adapt `scripts/verify_scramble.do` (a
   template — the datasets, keys and composite keys are package-specific). Per id map:
   1-to-1, new range disjoint from the old, inside the intended range; then a
   **whole-dataset diff over ALL variables** (not a pre-selected subset) that shows the
   only changes are the renamed ids plus any intended redaction, and catches silent
   corruption (e.g. a stray `_merge`). For that diff, merge the idmap into the original
   so both share the scrambled key and align by that key, never by row position. Tabs
   `idmap_checks`, `dataset_diffs`, `summary` (with the `result` cell). Then run
   `check-id-order` in audit mode on the maps: the rank correlation of each map, the
   overlap of old and new values.

6. **Run the package once** after the swap to confirm it executes; the numeric proof
   (every output identical to the original's) is `compare-code-results`.
