---
name: check-id-order
description: >-
  Check whether a code package depends on the ORDER or MAGNITUDE of its identifier
  variables, and how much of the original order an old-to-new id map keeps. Use before
  scrambling ids, to choose the method (fully random, banded around a cutoff, or a code
  fix), and on an already-scrambled release, to audit the scramble when both the old and
  the new ids are available (crosswalks). Triggers: "does the code depend on id order",
  "can we scramble ids at random", "is the scramble reversible", "rank correlation between
  old and new ids", "audit the id scrambling", "order-preserving map". Read-only on the
  original data. Examples are in Stata (.do/.dta); the method is language-agnostic.
---

# Check id-order dependence and order retention

Relabelling an id with a strict one-to-one map leaves every regression, cluster, panel
and group statistic unchanged — **unless the code uses the id's value or order**. And a
map that keeps the original order (old and new ranks correlated) is reversible by anyone
holding the original ids: one sort and a rank merge. This skill answers both questions,
in two modes. Its tabs (`code_scan`, `id_maps`, `relabel_test`) go in the audit workbook
(audit-pii, *Which audit, which workbook*): the code scan alone for a dataset whose ids are
not scrambled yet; the code scan and the id maps for a scrambled one.

Conventions (reproducible scripts in the project's `code/`, one workbook, loud failure):
`shared/conventions.md`. The ids to check come from the user's ID inventory
(`shared/id-inventory.md`): ask for it first; a scan never decides what an id is.

## Mode 1 — before scrambling: which method?

1. **Static scan of the code.** List the do-files the master runs
   (`shared/reachable_dofiles.py <package> <master.do> > dofiles.txt`), then
   `scripts/scan_id_order_dependence.py <workbook> "<inventory id vars>" dofiles.txt`.
   Comments are stripped; every hit is classed (tab `code_scan`):
   - **A magnitude** — the value is compared or binned (`if regionid > 154`,
     `inrange(id,…)`, `recode id`): a random map breaks it;
   - **B numbering** — numbers derived from the id's sort order feed the code
     (`egen group(id)`, `tab id, gen()`, `encode`, `levelsof` + a counter), and the code
     names them (`D_regionid_84` is "the 84th smallest id", not an entity);
   - **C position** — a row picked by position after sorting on the id (`sort id` then
     `_n`/`[1]`, `duplicates drop`, `collapse (first)`, `keep in`, `sample`);
   - **D invariant** — `bysort id:`, `xtset`, merge keys, `cluster(id)`, `i.id`: a 1-to-1
     relabel cannot change these (listed for completeness);
   - **H hardcoded** — a literal id value (`if hhid==149`): recoded through the map.
2. **Empirical test — the arbiter.** Most B/C hits are benign. Copy the package, run
   its master once (snapshot the outputs), apply `scripts/id_order_test.do` (template: a
   random permutation of each id's own values, so type and range are unchanged), run
   again and compare every output with `shared/compare_before_after.py` (tab
   `relabel_test`). Identical outputs = no dependence: a fully random map is safe.
3. **If outputs differ, fix — weakest intervention first**, and record which:
   - **banded map** for a cutoff: old values on each side of the cutoff map into disjoint
     slices of the new range, randomly *within* each band; rewrite the cutoff once to the
     slice boundary. The cutoff survives, the order inside each band does not;
   - **ship the indicator instead of the rule**: build `treated_region` (or the numbered
     dummies) once from the original ids, ship it, and rewrite the line to use it;
   - **explicit numbering** (class B): code that numbers entities by the *rank* of their id
     and then names one by its number. `tab mauzaid, gen(MAU_)` makes `MAU_1 … MAU_k` in
     ascending id order, so `MAU_84` means "the 84th smallest village id"; after a random
     relabel it is another village. A full set of such dummies used as fixed effects is
     harmless (the set is the same); only a *named* one is a problem. Name the entity by its
     value instead — `gen MAU_v = (mauzaid == 15960745)`, the literal being the scrambled id,
     recoded through the map like any hardcoded id value — and loop over values, not
     positions: `levelsof mauzaid, local(vs)` then `foreach v of local vs`, instead of
     `forvalues i = 1/194` paired with ids by rank. The scrambled literal reveals nothing;
   - **fix the tie-break, not the map** (class C): `sort id` then `duplicates drop`, `[1]`,
     `collapse (first)` keep whichever row comes first among rows tied on the key, and that
     depends on the id order. Make the choice a rule about the data, not about row order:
     keep the latest interview, the most complete record, the row with the larger value of a
     substantive variable (`gsort key -survey_date`, then keep the first). Where no
     substantive rule exists, break ties by the *scrambled* id or by a random variable drawn
     once with a fixed seed and shipped: both are deterministic and reveal nothing about the
     original ids. **Never** break ties by anything that encodes the original order — a
     shipped "original row number", the original id, or a variable sorted by it: on data
     that were sorted by id it is the original rank, and reverses the scramble as surely as
     an order-preserving map. The original pick was arbitrary, so no honest fix reproduces
     it: expect the affected numbers to move a little, and document it (as a correction).
   An order-preserving map is never the fix for a public release.

## Mode 2 — on a scrambled release: how reversible is it?

With the maps (old, new) per family, `scripts/id_map_audit.do` (template; globals for the
map folder, families, columns and any cutoffs) writes tab `id_maps`, one row per map
(and per band when cutoffs are given):
- **Spearman ρ** old vs new: ≈ 0 for a random relabel; |ρ| near 1 = order preserved,
  reversible with one sort — report it as a weakness of the release, not a pass;
- 1-to-1, the ranges of old and new, **old ids that are also legal new ids** (the overlap
  that makes a single value ambiguous) and the **share of new ids keeping the old id's
  number of digits** (a width-preserving map keeps the coarse magnitude);
- re-run the static scan on the *release's* code: A/B/C hits still present show where the
  release relies on order (e.g. rank-numbered dummies kept valid by an order-preserving map).

## Report

State, per id family: the hits by class, the empirical result, the method chosen (or the
map's ρ and overlap in mode 2) and why. Record the decisions in the private processing
notes; the public readme says nothing about the method.
