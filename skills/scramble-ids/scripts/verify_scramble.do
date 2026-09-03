/* verify_scramble.do -- FAIL-LOUD verification template for the ID scramble.

   Every check writes OK/FAIL to verify_results.csv (one row per check), and the
   dofile EXITS NONZERO if anything failed -- a problem cannot slip by unnoticed.
   The whole-dataset diff (check G) compares ALL variables and reports what
   differs, rather than pre-selecting columns, so it also catches accidental
   changes to analysis variables (e.g. a stray _merge from a `merge` missing
   `nogen`). Every check aligns by the scrambled KEY, never by row position (_n)
   -- merges re-sort, so _n-alignment silently breaks.

   Adapt the CONFIG block to your package: the id variables + intended ranges,
   the output datasets and their keys, any composite keys, and the redacted PII
   field(s).
*/
set more off
gl orig "orig"          // original datasets
gl deid "deid"          // de-identified datasets
gl keys "keys"          // folder with idmap_*.dta

* ---- CONFIG -----------------------------------------------------------------
* one line per id map: "<idname> <lo> <hi>"  (the intended new range)
local IDSPECS ///
    "myid   20000 99999" ///
    "hhid  300000 999999"
* output datasets to screen, with their unique key(s) and the id vars they hold
* (edit the two foreach blocks in checks D/F/G to match your datasets)
* -----------------------------------------------------------------------------

tempfile resfile repfile
postfile respf str32 check str40 item str8 status str244 detail using "`resfile'", replace
postfile reppf str32 dataset str2045 new_id_vars str2045 removed_or_dropped_vars ///
    str244 common_vars_differing long n_obs_unmatched using "`repfile'", replace

*==================================================================*
* A / B / C -- per correspondence table (1-to-1, non-overlap, monotonic)
*==================================================================*
foreach spec of local IDSPECS {
    gettoken v spec : spec
    gettoken lo hi  : spec       // lo/hi document intent; the check uses observed ranges
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
    quietly count if _bad == 1
    local nonmono = r(N)
    post respf ("A: 1-to-1")           ("`v'") (cond(`dold'==`n' & `dnew'==`n',"OK","FAIL")) ("distinct old=`dold' new=`dnew' of N=`n'")
    post respf ("B: no range overlap") ("`v'") (cond(`overlap'==0,"OK","FAIL"))             ("old[`omin',`omax'] new[`nmin',`nmax']")
    post respf ("C: monotonic")        ("`v'") (cond(`nonmono'==0,"OK","FAIL"))             ("`nonmono' non-increasing step(s)")
}

*==================================================================*
* D -- each id maps to the right OUTPUT row (KEY-BASED, never _n)
*     Map the original row's id through the idmap to (id_pubrep, <key>) and
*     confirm it matches exactly one output row. Edit datasets/keys below.
*==================================================================*
foreach f in dataset1 dataset2 {
    use myid <keyvar> using "$orig/`f'.dta", clear
    merge m:1 myid using "$keys/idmap_myid.dta", keep(master match) nogen
    merge 1:1 myid_pubrep <keyvar> using "$deid/`f'.dta", keepusing(myid_pubrep) gen(_dm)
    quietly count if _dm != 3
    local nd = r(N)
    post respf ("D: id mapping") ("`f'") (cond(`nd'==0,"OK","FAIL")) ("`nd' original row(s) with no output match")
}

*==================================================================*
* E -- composite keys stay consistent (bijection => pair counts unchanged)
*     Align original and output on the scrambled key, then #distinct(old pair)
*     == #distinct(new pair) == #distinct(joint). Edit the pair vars.
*==================================================================*
* use <keyvar> hhid memberid using "$orig/dataset1.dta", clear
* merge m:1 myid ... (bring in myid_pubrep for the join) ...
* keep if !missing(hhid) & !missing(memberid)
* egen long _o = group(hhid memberid)
* egen long _n2 = group(hhid_pubrep mid_pubrep)
* egen long _c = group(_o _n2)
* summarize _o
* local go = r(max)
* ... local gn, gj ...
* post respf ("E: member pairs") ("hhid+memberid") (cond(`go'==`gn' & `gn'==`gj',"OK","FAIL")) ("old=`go' new=`gn' joint=`gj'")

*==================================================================*
* F -- output datasets contain NO original id variable (use ,exact)
*==================================================================*
foreach f in dataset1 dataset2 {
    use "$deid/`f'.dta", clear
    local badlist ""
    foreach old in myid hhid memberid {
        capture confirm variable `old', exact
        if _rc==0 local badlist `badlist' `old'
    }
    post respf ("F: originals removed") ("`f'") (cond("`badlist'"=="","OK","FAIL")) ///
        (cond("`badlist'"=="","no original id vars present","still present:`badlist'"))
}

*==================================================================*
* G -- whole-dataset diff: og vs deid differ ONLY on ids (+ redacted name).
*     Compares ALL variables (nothing pre-selected). Var-set diff is against the
*     TRUE original varlist ($OGORIG, captured before adding the _pubrep key),
*     so the new _pubrep ids show up as "new"; value diff is aligned on the key.
*==================================================================*
capture program drop cmp_og_deid
program define cmp_og_deid
    syntax , Tag(string) Deidfile(string) Key(string) [Allowdiff(string)]
    local ogorig $OGORIG
    quietly ds
    local ogmem `r(varlist)'
    preserve
        use "`deidfile'", clear
        quietly ds
        local deidvars `r(varlist)'
    restore
    local new_only     : list deidvars - ogorig
    local removed_only : list ogorig   - deidvars
    local common       : list ogmem    & deidvars
    local common       : list common   - key
    preserve
        keep `key' `common'
        foreach v of local common {
            rename `v' O_`v'
        }
        tempfile ogc
        save `ogc'
        use "`deidfile'", clear
        keep `key' `common'
        merge 1:1 `key' using `ogc', gen(_mm)
        quietly count if _mm != 3
        local nunmatched = r(N)
        local vdiff ""
        foreach v of local common {
            quietly count if (`v' != O_`v') & !(missing(`v') & missing(O_`v')) & _mm==3
            if r(N) > 0 local vdiff `vdiff' `v'
        }
    restore
    post reppf ("`tag'") (substr("`new_only'",1,2040)) (substr("`removed_only'",1,2040)) ///
        (substr("`vdiff'",1,240)) (`nunmatched')
    local nbad = `nunmatched'
    local unexp ""
    foreach v of local vdiff {
        local vv `v'
        if !(`: list vv in allowdiff') {
            local ++nbad
            local unexp `unexp' `v'
        }
    }
    local det "new_ids=`: word count `new_only'' removed/dropped=`: word count `removed_only'' unmatched=`nunmatched'"
    if "`unexp'" != "" local det "`det' UNEXPECTED:`unexp'"
    post respf ("G: og==deid except ids") ("`tag'") (cond(`nbad'==0,"OK","FAIL")) ("`det'")
end

* one call per dataset: capture the ORIGINAL varlist, add the _pubrep key, compare.
* allowdiff() lists the intended value changes (the redacted PII field(s)).
use "$orig/dataset1.dta", clear
quietly ds
global OGORIG `r(varlist)'
merge m:1 myid using "$keys/idmap_myid.dta", keep(master match) nogen
cmp_og_deid, tag(dataset1) deidfile("$deid/dataset1.dta") key(myid_pubrep <keyvar>) allowdiff(namevar)

*==================================================================*
* FINALIZE -- export both files; fail loudly if any check failed
*==================================================================*
postclose respf
postclose reppf
use "`repfile'", clear
export delimited using "$keys/cf_og_vs_deid.csv", replace
use "`resfile'", clear
export delimited using "$keys/verify_results.csv", replace
list check item status detail, noobs sepby(check)
quietly count if status == "FAIL"
local nfail = r(N)
if `nfail' > 0 {
    di as error _n "==== VERIFICATION FAILED: `nfail' of `=_N' check(s) failed ===="
    exit 459
}
di as result _n "==== ALL `=_N' CHECKS PASSED ===="
