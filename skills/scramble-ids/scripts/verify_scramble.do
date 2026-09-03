/* verify_scramble.do -- ADAPTABLE verification template for an ID scramble.
 *
 * This is a reference template to COPY and edit per package (which id maps, which
 * datasets, which composite keys) -- not a black-box command. It writes ONE review
 * workbook (verify_review.xlsx: sheets idmap_checks, dataset_diffs, summary) and,
 * on any failure, drops a verify_FAILED.flag sentinel. Stata batch returns OS exit
 * 0 even on error, so detect failure via the sentinel / the summary `result` cell,
 * not the exit code (the `exit 459` below still halts an in-Stata do-file chain).
 *
 * Every check aligns by the scrambled KEY, never by row position (_n): merges
 * re-sort, so _n-alignment silently reports false mismatches.
 */
set more off
gl orig "orig"          // original datasets
gl deid "deid"          // de-identified datasets
gl keys "keys"          // folder with idmap_*.dta
gl out  "."             // where the workbook + sentinel go

* one line per id map: "<idname> <lo> <hi>" (lo/hi document intent)
local IDSPECS "myid 20000 99999" "hhid 300000 999999"

*==================================================================*
* A/B/C -- per correspondence table: 1-to-1, new-range-disjoint, monotonic
*==================================================================*
tempfile idres
postfile P str32 check str32 item str8 status str244 detail using "`idres'", replace
foreach spec of local IDSPECS {
    gettoken v rest : spec
    use "$keys/idmap_`v'.dta", clear
    quietly count
    local n = r(N)
    quietly duplicates report `v'
    local dold = r(unique_value)
    quietly duplicates report `v'_pubrep
    local dnew = r(unique_value)
    quietly summarize `v'
    local omin = r(min)
    local omax = r(max)
    quietly summarize `v'_pubrep
    local nmin = r(min)
    local nmax = r(max)
    local overlap = !(`nmax' < `omin' | `nmin' > `omax')
    sort `v'
    quietly gen byte _bad = `v'_pubrep <= `v'_pubrep[_n-1] if _n > 1
    quietly count if _bad==1
    local nonmono = r(N)
    post P ("1-to-1")     ("`v'") (cond(`dold'==`n' & `dnew'==`n',"OK","FAIL")) ("distinct old=`dold' new=`dnew' of N=`n'")
    post P ("no-overlap") ("`v'") (cond(`overlap'==0,"OK","FAIL"))              ("old[`omin',`omax'] new[`nmin',`nmax']")
    post P ("monotonic")  ("`v'") (cond(`nonmono'==0,"OK","FAIL"))              ("`nonmono' non-increasing step(s)")
}
postclose P

*==================================================================*
* G -- whole-dataset diff over ALL variables, aligned by the scrambled key.
*      For each output dataset: merge the idmap into the ORIGINAL so both share
*      the key, then compare every common variable. `allowdiff` lists the intended
*      value changes (the redacted PII field[s]). EDIT the loop for your datasets.
*==================================================================*
tempfile dres
postfile D str32 dataset str244 deid_only str244 orig_only str244 differing str244 unexpected long n_unmatched using "`dres'", replace
* --- per dataset (repeat/edit this block) -------------------------------------
* example: dataset "children", key "myid_pubrep", redacted var "namevar"
local DATASET  "children"
local KEY       "myid_pubrep"
local JOINID    "myid"
local ALLOWDIFF "namevar"
use "$orig/`DATASET'.dta", clear
merge m:1 `JOINID' using "$keys/idmap_`JOINID'.dta", keep(master match) nogen
quietly ds
local ovars `r(varlist)'
preserve
    use "$deid/`DATASET'.dta", clear
    quietly ds
    local dvars `r(varlist)'
restore
local deid_only : list dvars - ovars
local orig_only : list ovars - dvars
local common    : list ovars & dvars
local common    : list common - KEY
keep `KEY' `common'
foreach v of local common {
    rename `v' O_`v'
}
tempfile ogc
quietly save `ogc'
use "$deid/`DATASET'.dta", clear
keep `KEY' `common'
merge 1:1 `KEY' using `ogc', gen(_mm)
quietly count if _mm != 3
local nun = r(N)
local vdiff ""
foreach v of local common {
    quietly count if (`v' != O_`v') & !(missing(`v') & missing(O_`v')) & _mm==3
    if r(N) > 0 local vdiff `vdiff' `v'
}
local unexp ""
foreach v of local vdiff {
    local vv `v'
    if !(`: list vv in ALLOWDIFF') local unexp `unexp' `v'
}
post D ("`DATASET'") ("`deid_only'") ("`orig_only'") ("`vdiff'") ("`unexp'") (`nun')
* --- end per-dataset block ----------------------------------------------------
postclose D

*==================================================================*
* ASSEMBLE ONE REVIEW WORKBOOK + sentinel on failure
*==================================================================*
use "`idres'", clear
export excel using "$out/verify_review.xlsx", sheet("idmap_checks") sheetreplace firstrow(variables)
quietly count if status=="FAIL"
local nfail_id = r(N)

use "`dres'", clear
export excel using "$out/verify_review.xlsx", sheet("dataset_diffs") sheetreplace firstrow(variables)
quietly count if n_unmatched>0 | unexpected!=""
local nfail_ds = r(N)

local nfail = `nfail_id' + `nfail_ds'
clear
set obs 3
gen str24 metric = ""
gen str24 value  = ""
replace metric = "idmap_checks_failed" in 1
replace value  = "`nfail_id'"          in 1
replace metric = "dataset_diffs_failed" in 2
replace value  = "`nfail_ds'"           in 2
replace metric = "result"               in 3
replace value  = cond(`nfail'==0,"PASS","FAIL") in 3
export excel using "$out/verify_review.xlsx", sheet("summary") sheetreplace firstrow(variables)

capture erase "$out/verify_FAILED.flag"
if `nfail' > 0 {
    file open F using "$out/verify_FAILED.flag", write replace
    file write F "`nfail' verification check(s) FAILED; see verify_review.xlsx" _n
    file close F
    di as error "VERIFICATION FAILED (`nfail') -> verify_review.xlsx / verify_FAILED.flag"
    exit 459
}
di as result "verification PASSED -> verify_review.xlsx"
