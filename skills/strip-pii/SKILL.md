---
name: strip-pii
description: >-
  Remove confirmed direct PII from a dataset by dropping the field or overwriting
  it with a placeholder -- and clear the underlying bytes so no residue remains.
  Use when someone wants to redact / remove / anonymize specific identifying
  variables (names, address, phone, GPS, IDs, free text), replace values with a
  placeholder like "REDACTED", or scrub personal info a scan flagged. Handles the
  trap that a plain overwrite leaves the original bytes readable after the string
  terminator (a ghost tail); this skill overwrites cleanly. Pairs with audit-pii
  (which produces the confirmed field list and re-confirms afterward). Examples
  are in Stata (.do/.dta); the method is language-agnostic.
---

# Strip confirmed PII (clean overwrite)

Takes the confirmed PII list (from `audit-pii`) and removes it. The one subtlety
that makes this non-trivial: a fixed-width string keeps the bytes after its `\0`
terminator, so a plain `replace name = "REDACTED"` on a wider field leaves the
tail of the original value **still on disk** (invisible to normal reads). You must
either drop the field or overwrite the whole slot.

## Steps

1. **Confirm the placeholder and the per-field action with the user.** For each
   confirmed field, the choice is theirs: **drop** the variable, or **overwrite**
   with a placeholder (keeps the column/shape). If overwriting, confirm the
   placeholder string (e.g. `"REDACTED"`, `"NON-PII"`, or empty `""`). Sensible
   default to propose: drop free-text/rare fields; overwrite where a column must
   stay for the code or structure.

2. **Apply with a clean overwrite (no ghost tail).** Put `scripts/` on the adopath
   and call the `redact_clean` program — `redact_clean <var>,
   method(drop|fullwidth|rebuild) [placeholder() newlen()] report(<csv>)` — which
   applies one of the safe methods and appends the action to a report CSV:
   - **`drop`** the variable — no bytes remain. Simplest and safest when the column
     is not needed by the code.
   - **`fullwidth`** — set every cell to a placeholder and recast storage to its
     exact length, so there is no terminator and no tail.
   - **`rebuild`** — when values must vary, copy into a freshly created
     (zero-initialised) `str` variable and drop the original, so tails are zero.
   All three are residue-free by construction. A bare `replace` is NOT — it leaves
   residue (as do `compress`, `recast`, `strtrim`, and copy-into-an-existing-var).

3. **Strip the non-value surfaces too.** PII also lives in metadata (see
   audit-pii): drop identifying **value labels** (`label drop`), clear identifying
   **variable labels** and **notes**/**characteristics**, and rename **variable
   names** that encode PII. For a **numeric** PII field (national ID, phone, GPS,
   exact date), drop it or set it to missing/placeholder, and drop any attached
   value label.

4. **Re-run audit to confirm.** Run `audit-pii` again on the output: the tail
   scanner must return clean (exit 0), the detector clear, and no original
   identifier value found anywhere. Do not consider a field stripped until the
   confirm pass is clean.

5. **Report what changed (systematic).** Emit a redaction report: full row-level
   list (field, action = drop/placeholder/rebuild, placeholder used, surfaces
   cleared) **and** a summary (# fields dropped, # overwritten, # metadata items
   cleared). Record it in the private processing readme, never the public one.

## Notes

- **Overwrite ≠ scrub.** The residue point is the whole reason this skill is
  separate from "just replace the values" — always finish with the confirm pass.
- **Sources only in the public copy.** Redact in the release copy; never edit the
  original/source files in place.
