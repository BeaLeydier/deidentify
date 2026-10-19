* id_order_test.do -- TEMPLATE: the empirical test of id-order dependence. On a COPY of the
* package, relabel every listed id with a random one-to-one permutation of its own values, so
* that order and rank are destroyed while the set of values (and so every type, width and
* range) stays the same. Then run the package's master on the copy and compare every output
* with a run of the untouched copy (shared/compare_before_after.py).
*   identical outputs  -> the code does not depend on id order: a random map is safe;
*   outputs differ     -> the differing tables name the do-files to fix (see SKILL.md for the
*                         fixes: banded map, shipped indicator, explicit numbering, tie-break).
* ADAPT: set in the project's config.do (or above this line):
*   $TESTCOPY   the copy to relabel (never the original or the release)
*   $DTALIST    text file, one dataset path per line, relative to $TESTCOPY
*   $IDFAMS     "fam1 fam2 ..."; per family $IDVARS_fam1 "var1 var2 ..." (the ID inventory:
*               every variable holding that family's id, in any dataset; same-universe ids
*               of two sources listed under one family share one permutation)
*   $SEED       any integer (the permutation is reproducible)
* Derived ids (e.g. personid = hhid*100 + member) must be rebuilt from the relabelled parts
* after this runs, with the rule the inventory gives -- add that block at the end.
set seed $SEED
foreach fam of global IDFAMS {
    * union of the family's values across every dataset that holds one of its variables
    clear
    tempfile u
    quietly save `u', emptyok
    file open IN using "$DTALIST", read text
    file read IN line
    while r(eof)==0 {
        if `"`line'"' != "" {
            quietly describe using "$TESTCOPY/`line'", varlist
            local here `r(varlist)'
            foreach v of global IDVARS_`fam' {
                if `: list v in here' {
                    use `v' using "$TESTCOPY/`line'", clear
                    rename `v' old
                    quietly drop if missing(old)
                    quietly append using `u'
                    quietly duplicates drop
                    quietly save `u', replace
                }
            }
        }
        file read IN line
    }
    file close IN
    use `u', clear
    * random permutation of the values: pair the k-th smallest value with the k-th value of
    * the same set in random order
    sort old
    gen long k = _n
    preserve
        gen double r = runiform()
        sort r
        replace k = _n
        rename old new
        keep k new
        tempfile perm
        quietly save `perm'
    restore
    quietly merge 1:1 k using `perm', nogen
    drop k
    quietly spearman old new
    di as txt "`fam': " _N " values permuted; Spearman old vs new = " %6.3f r(rho)
    tempfile map
    quietly save `map'
    * apply to every listed variable in every dataset of the copy
    file open IN using "$DTALIST", read text
    file read IN line
    while r(eof)==0 {
        if `"`line'"' != "" {
            quietly describe using "$TESTCOPY/`line'", varlist
            local here `r(varlist)'
            local touched = 0
            use "$TESTCOPY/`line'", clear
            foreach v of global IDVARS_`fam' {
                if `: list v in here' {
                    rename `v' old
                    quietly merge m:1 old using `map', keep(master match) keepusing(new) nogen
                    quietly replace old = new if !missing(old)
                    drop new
                    rename old `v'
                    local touched = 1
                }
            }
            if `touched' quietly save "$TESTCOPY/`line'", replace
        }
        file read IN line
    }
    file close IN
}
di as txt "relabelled; now run the package's master on $TESTCOPY and compare its outputs"
