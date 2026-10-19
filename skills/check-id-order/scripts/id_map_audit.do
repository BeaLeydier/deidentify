* id_map_audit.do -- TEMPLATE: how much of the original id order does each old -> new map keep?
* Run it on the correspondence tables (crosswalks) of a scrambled release, or on a candidate
* map before it is applied. Read-only.
* ADAPT: set in the project's config.do (or above this line):
*   $XWALK      folder holding the maps
*   $IDFAMS     "fam1 fam2 ..."; per family $XW_fam1 "<map file> <old column> <new column>"
*   optional $CUTS_fam1 "c1 c2 ..."  cutoffs the code applies to the id (banded maps): the
*               rank correlation is also reported WITHIN each band
*   $WORKBOOK   the review workbook; this writes its tab `id_maps`
* Per map: n, whether it is 1-to-1, Spearman rho between old and new (about 0 for a random
* relabel, 1 for an order-preserving map, which anyone holding the original ids reverses with
* one sort), Pearson r, the ranges of old and new, how many old ids are also legal new ids
* (overlap: then a single value cannot be told apart as old or new), and how many new ids keep
* the old id's number of digits (a width-preserving map keeps coarse magnitude).
tempname P
tempfile res
postfile `P' str32 family str20 band double n byte one_to_one double spearman pearson ///
    old_min old_max new_min new_max n_old_also_new share_same_digits str60 verdict using `res', replace
foreach fam of global IDFAMS {
    local spec : word 1 of ${XW_`fam'}
    local ocol : word 2 of ${XW_`fam'}
    local ncol : word 3 of ${XW_`fam'}
    use `ocol' `ncol' using "$XWALK/`spec'", clear
    rename (`ocol' `ncol') (old new)
    drop if missing(old) | missing(new)
    duplicates drop
    quietly count
    local n = r(N)
    quietly duplicates report old
    local u1 = r(unique_value)
    quietly duplicates report new
    local u2 = r(unique_value)
    local oto = (`u1'==`n' & `u2'==`n')
    * old ids that are also legal new ids
    preserve
        keep new
        rename new old
        tempfile nw
        quietly save `nw'
    restore
    preserve
        keep old
        quietly merge 1:1 old using `nw', keep(match) nogen
        local nover = _N
    restore
    gen byte samedig = strlen(string(abs(old), "%20.0f")) == strlen(string(abs(new), "%20.0f"))
    quietly summarize samedig
    local sdig = r(mean)
    * bands: 0 = whole map; then one band per interval between the cutoffs
    gen int band = 0
    local cuts "${CUTS_`fam'}"
    local k = 0
    foreach c of local cuts {
        local ++k
        quietly replace band = `k' if old > `c'
    }
    local blist "all"
    if `k' > 0 {
        forvalues b = 0/`k' {
            local blist "`blist' `b'"
        }
    }
    foreach b of local blist {
        preserve
            if "`b'" != "all" quietly keep if band == `b'
            quietly count
            local nb = r(N)
            local rho = .
            local r = .
            if `nb' > 2 {
                quietly spearman old new
                local rho = r(rho)
                quietly correlate old new
                local r = r(rho)
            }
            quietly summarize old
            local omin = r(min)
            local omax = r(max)
            quietly summarize new
            local nmin = r(min)
            local nmax = r(max)
            * "no order" = within sampling noise of 0 (3 SE, SE ~ 1/sqrt(n-1)) or below 0.1
            local thr = max(0.1, 3/sqrt(max(`nb'-1,1)))
            local v = cond(abs(`rho')<`thr', "no order retained", cond(abs(`rho')<0.9, "partial order retained", "ORDER PRESERVED: reversible by one sort"))
            if !`oto' local v "NOT 1-to-1"
            post `P' ("`fam'") ("`b'") (`nb') (`oto') (`rho') (`r') (`omin') (`omax') (`nmin') (`nmax') (`nover') (`sdig') ("`v'")
        restore
    }
}
postclose `P'
use `res', clear
export excel using "$WORKBOOK", sheet("id_maps") sheetreplace firstrow(variables)
list family band n one_to_one spearman n_old_also_new share_same_digits verdict, clean noobs
