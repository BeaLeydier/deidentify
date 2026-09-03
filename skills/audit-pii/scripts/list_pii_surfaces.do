/* list_pii_surfaces.do -- enumerate PII surfaces in one Stata dataset (read-only).
 * Writes a variable-level CSV + a text dump of the free-text surfaces to review.
 * Usage: edit the two locals, then  stata-se -b do list_pii_surfaces.do
 * Not Stata? Reproduce each block with your tool: list string columns; dump value
 * labels; dump variable labels; dump dataset notes/metadata; keyword-search
 * variable names + labels. See references/pii-surfaces.md for the full checklist.
 */
local data "PATH/TO/dataset.dta"
local stub "surfaces"           // output prefix

use "`data'", clear

* --- free-text surfaces (best eyeballed): B1 value labels, B4 notes + char, B2/B3 ---
log using "`stub'_dump.txt", text replace
di "=== VALUE LABELS (B1: numeric code -> possibly identifying text) ==="
label list
di _n "=== DATASET + VARIABLE NOTES (B4: free text, may name people) ==="
notes
di _n "=== CHARACTERISTICS (B4: may embed file paths / usernames / id var names) ==="
char list
di _n "=== KEYWORD HITS in names + labels (B2/B3) ==="
lookfor name address phone email gps latitude longitude coord dob birth date ///
        id respondent enumerator interviewer village household consent
log close

* --- variable-level surfaces to a CSV: A1 strings, A3 numerics to review, B2 labels ---
file open R using "`stub'_report.csv", write replace
file write R "variable,type,is_string,value_label,variable_label" _n
foreach v of varlist _all {
    local ty : type `v'
    local isstr = cond(substr("`ty'",1,3)=="str",1,0)
    local vl : value label `v'
    local ll : variable label `v'
    file write R `"`v',`ty',`isstr',`vl',"`ll'""' _n
}
file close R

* --- summary to screen ---
qui ds, has(type string)
local strs `r(varlist)'
di as result _n "surfaces: report -> `stub'_report.csv ; free-text dump -> `stub'_dump.txt"
di as result "A1 string variables (scan values AND run the tail scanner): `strs'"
di as result "NEXT: review the dump for B1/B4 PII, and judge A3 numeric ids/GPS/dates by hand."
