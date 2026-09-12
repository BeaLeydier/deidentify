# The ID inventory — what the user tells the skills before any scan runs

Which variables identify people, households, places or units, and how the datasets
fit together, is knowledge the data owners have and a scan can only guess at.
Every skill in this plugin therefore starts from an **inventory supplied by the
user** and treats what it finds in the data as *candidates* to add to that
inventory, never as a replacement for it.

## Ask first

Before the first scan, ask the user for (and record in `id_inventory.csv` at the
top level of the deliverable):

| Column | Meaning |
|---|---|
| `family` | the entity the id names — one word per entity (e.g. `person`, `household`, `village`, `school`, `cluster`) |
| `variable` | the variable name as it appears in the data |
| `dataset` | file(s) holding it (`*` = every file that has the name) |
| `role` | `key` (identifies the entity), `part` (one part of a composite key), `derived` (built from other ids by a rule), `cluster`, `panel`, `time`, `merge` (used only to link files) |
| `level` | unit of observation the variable identifies (one row per …) |
| `derived_rule` | for `derived`: the formula (e.g. `hhid*100 + memberid`) |
| `same_as` | another variable that is the same kind of id from a different source (the two share one map) |
| `cutoffs` | values the code compares the id against (for example, `> 154`), if any |
| `notes` | anything else: known gaps, ids that change over time, ids of dropped units quoted in notes |

and, as free text, the **data structure**: unit of observation of each dataset,
panel and time variables, which keys link which files, and which ids appear in
more than one file.

If the user cannot answer some of it, say so in the report and mark those rows
`source = inferred`; run the scans, show the candidates, and ask again.

## Precedence

1. **The inventory is authoritative.** A variable the user lists is an identifier
   for every skill, whatever its name, type or number of distinct values.
2. **Scans add candidates, never remove entries.** Name heuristics (`*id`, `*code`,
   family words), `isid`, uniqueness of id-named sets and keyword matches produce a
   separate list of *unlisted candidates* for the user to accept or reject. A
   candidate the user rejects is recorded as rejected, with the reason.
3. **Conflicts go to the user.** If a scan suggests that two listed ids share a
   universe (identical value sets), that a listed id is a 0/1 indicator, or that a
   listed `derived` rule does not hold in the data, report it and ask; do not act on
   the scan's reading.
4. **Only without an inventory** do the heuristics decide on their own, and then
   every such decision is labelled `inferred` in the outputs and the report.

## How each skill consumes it

- `audit-pii`: `idkeys()` of `pii_classify` and `idvars()` of `list_pii_surfaces`
  are the inventory's variable names (globs allowed); `id_leak_tests.do` reads
  `$IDFAMS` (the families) and `$IDVARS_<family>` (the listed variables) and
  reports unlisted candidates separately.
- `scramble-ids`: the families, the same-universe pairs, the union across files,
  the composite and derived rules and the cutoffs all come from the inventory; the
  order-dependence scan runs on the listed variables.
- `minimize-variables`: `alwayskeep()` is the inventory's `key`, `part`, `merge`,
  `panel`, `time` and `cluster` variables, so keys are never dropped as "unused".
- `strip-pii`: nothing in the inventory is a PII field to strip; ids are scrambled,
  not redacted.
