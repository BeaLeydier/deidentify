---
name: map-ids
description: >-
  Build the ID inventory of a code package or dataset before any audit, scrambling or
  minimisation: which variables identify people, households, places or units, in which
  files, how they link, which are composite or derived, which cutoffs the code applies to
  them. Starts from the user's own list or description of the ids; without one, scans the
  data for candidates (id-like names, variables that identify rows, variables holding the
  same set of values in two files) for the user to accept or reject. Run once, at set-up;
  every other skill of the plugin reads the result. Triggers: "which variables are ids",
  "map the identifiers", "id inventory", "id candidates", "what links these files".
  Read-only. Examples are in Stata (.do/.dta); the method is language-agnostic.
---

# Map the ids (the ID inventory)

Which variables are identifiers, and how the datasets fit together, is knowledge the data
owners have and a scan can only guess at. This skill settles it **once**, at set-up, in one
workbook (`id_inventory.xlsx`) that the other skills read: `audit-pii` (the ids are set
aside from the PII shortlist and tested by the leak tests), `check-id-order` and
`scramble-ids` (which ids, their relationships and cutoffs), `minimize-variables` (keys are
never dropped). Once settled, it is not revisited by the later steps.

Conventions (every step a script in the project's `code/`, paths from one config, one
workbook, loud failure): `shared/conventions.md`. The inventory's columns and the precedence
rules: `shared/id-inventory.md`.

## Steps

1. **Ask the user first**: do you have a list or a map of the ids? It can be a file, or a
   description in words. Collect, for each id: the entity it names, the variable(s) and
   files, its role (key, part of a composite key, derived by a rule, cluster, panel, time,
   merge key), same-kind ids from other sources, cutoffs the code applies to it. Collect the
   data structure as text too: unit of observation of each dataset, which keys link which
   files.
2. **Scan, as a check or as the starting point** — put `scripts/` on the adopath, list the
   study datasets one per line (`datasets.txt`, relative to the package root; example data
   inside third-party `ado/` folders is not study data) and run
   `scan_id_candidates, datasets(datasets.txt) root(<pkg>) workbook(id_inventory.xlsx)
   idvars("<the user's ids, if any>")`. Tabs:
   - `candidates`: every variable whose name looks like an id (`*id`, `*_id*`, `*code*`,
     `*key*`, `*uuid*`, `*serial*`) or that identifies its dataset's rows alone, with the
     other variables holding exactly the same set of values (`same_values_as`: a reason to
     *ask* whether two ids share a universe, never to merge them on that ground), and empty
     `family` / `role` / `decision` columns;
   - `datasets`: per dataset, whether the inventory's variables (and, apart, all id-like
     names) identify its rows — a listed key that does not is worth a question.
3. **Settle it with the user.** With a list: show the candidates the list does not cover,
   and the datasets whose rows the listed keys do not identify; ask. Without a list: go
   through the candidates with the user (most question codes named `*_code` are answers, not
   ids). Record each decision, with its reason, in `decision`.
4. **Write the inventory** — tab `inventory` of the same workbook, one row per id variable,
   columns as in `shared/id-inventory.md` (`family`, `variable`, `dataset`, `role`, `level`,
   `derived_rule`, `same_as`, `cutoffs`, `notes`, `source` = user / scan accepted), and the
   data-structure text in a tab `structure`. Put the lists the tools need in the project's
   config (`IDKEYS`: every key, merge, panel and time variable; `IDVARS_<family>`: the
   variables of each family; `IDFAMS`).

## Notes
- **The user's list is authoritative.** A scan adds candidates, never removes or
  reclassifies a listed variable; conflicts (two listed ids with identical values, a listed
  `derived` rule that fails in the data) go to the user.
- **No inventory, no id test.** Leak tests, order checks and scrambling need the listed
  variables; without them the other skills stop and point here.
