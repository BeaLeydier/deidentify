/* redact_and_clean.do -- remove PII with a CLEAN overwrite (no ghost tail).
 *
 * A fixed-width string keeps the bytes after its \0 terminator, so `replace
 * name = "REDACTED"` on a wider field leaves the original tail on disk. Use one
 * of the three safe methods below. Adapt variable names to your confirmed list.
 *
 * Not Stata? The principle is identical: to erase residue you must drop the
 * column or rewrite the entire fixed-width slot -- overwriting only the value is
 * not enough.
 */
local data "PATH/TO/release_copy.dta"     // the PUBLIC copy, never a source
use "`data'", clear

*========================================================================*
* METHOD 1 -- DROP the field (no bytes remain). Best when code doesn't need it.
*========================================================================*
drop pii_freetext_var

*========================================================================*
* METHOD 2 -- PLACEHOLDER, full width (no terminator => no tail).
*   Set every cell to a constant, then shrink storage to that exact length.
*   "REDACTED" is 8 chars -> str8 has no room for a tail.
*========================================================================*
replace pii_name = "REDACTED"
recast str8 pii_name, force            // exact placeholder length => zero slack

*========================================================================*
* METHOD 3 -- keep VARYING values but clear residue: rebuild on zeroed memory.
*   `gen new = ""` gives zero-initialised slots; `replace new = old` copies only
*   the logical value, leaving zero tails. (A one-step `gen new = old` would copy
*   the whole slot, garbage included -- must be the two-step form.)
*========================================================================*
gen str`=length("REDACTED")' _tmp = ""     // or any width you need
replace _tmp = pii_keepvarying              // logical values copied; tails stay 0
drop pii_keepvarying
rename _tmp pii_keepvarying

*========================================================================*
* NON-VALUE surfaces: metadata carries PII too.
*========================================================================*
* numeric PII (national id / phone / GPS / exact date): drop or blank + unlabel
drop pii_numeric_id
* identifying value labels
capture label drop lbl_village
* identifying variable labels / notes / characteristics
label variable somevar ""
note drop _dta
* variable NAME that encodes PII
rename income_johnsmith income_r001

save "`data'", replace

/* THEN re-run audit-pii on this file:
     python3 scan_string_tails.py "PATH/TO/release_copy.dta" OUT   // must exit 0
   and confirm the detector is clear and no original identifier value is found.  */
