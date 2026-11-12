* id_leak_tests.do -- TEMPLATE: prove no original identifier survives in a release, using the
* private old -> new crosswalks. Copy into the project's code/ and set (in its config.do):
*   $DATADIR   folder with the RELEASE datasets     $DTALIST  text file, one dataset path per line
*   $XWALK     folder with the crosswalk .dta files (private, read-only)
*   $WATCH     PRIVATE folder for the watch lists (re-identification keys: never shipped)
*   $WORKBOOK  the review workbook; tabs id_watchlist_sizes, id_crossref_numeric (one row per
*              tested variable), id_mergeback_rowtest
*   $IDFAMS    "fam1 fam2 ..."   and, per family,  $XW_fam1 "<crosswalk file> <old col> <new col>"
*   $IDVARS_fam1 "var1 var2 ...": the user's ID inventory -- the variables of that family
*              (every dataset holding the name). Required: ask the user for it. Id-like
*              variables NOT listed are reported by pii_surfaces (tab id_candidates).
* Watch lists (from the crosswalks): ALL OLD, ALL NEW (the image) and OLD-ONLY (old ids that are
*   never a legal new value); their sizes and overlap say how informative test 1 is.
* Test 1 (per listed variable, distinct values): n_outside_image (not a legal new id) and
*   n_in_old_only (provably an old id); expected_hits_if_unscrambled = n_distinct x share old-only.
* Test 2: each row's OLD id recovered through the crosswalk; every other column equal to it on
*   >= 99% of its non-missing rows and >= 10 rows is an old-id column kept by mistake.
* How much ORDER each map keeps (rank correlation) is the check-id-order skill's job.
* ---------------------------------------------------------------------------------------------
* ---- Part A: watch lists ----
cap mkdir "$WATCH"
tempname S
tempfile WS
file open `S' using `WS', write replace
file write `S' "family,n_old_ids,n_new_ids,n_overlap_old_in_new,n_old_only,share_old_only" _n
foreach fam of global IDFAMS {
    local spec : word 1 of ${XW_`fam'}
    local ocol : word 2 of ${XW_`fam'}
    local ncol : word 3 of ${XW_`fam'}
    * ALL OLD
    use "$XWALK/`spec'", clear
    keep `ocol'
    rename `ocol' val
    drop if missing(val)
    duplicates drop
    sort val
    save "$WATCH/WL_old_`fam'.dta", replace
    local nold = _N
    * ALL NEW  (= the "image" set)
    use "$XWALK/`spec'", clear
    keep `ncol'
    rename `ncol' val
    drop if missing(val)
    duplicates drop
    sort val
    save "$WATCH/WL_image_`fam'.dta", replace
    local nnew = _N
    * OLD-ONLY = old ids that are not in the new set
    merge 1:1 val using "$WATCH/WL_old_`fam'.dta"
    keep if _merge==2
    keep val
    sort val
    save "$WATCH/WL_origonly_`fam'.dta", replace
    * a text copy for the text-file sweep (scan_text_files.py)
    quietly export delimited val using "$WATCH/WL_origonly_`fam'.txt", novarnames replace
    local noo = _N
    file write `S' "`fam',`nold',`nnew',`=`nold'-`noo'',`noo',`=round(`noo'/`nold',0.0001)'" _n
    di as txt "`fam': old=`nold' new=`nnew' old-only=`noo' (share `=round(`noo'/`nold',0.001)')"
}
file close `S'
* ---- Part B: tests ----
tempname T1 T3
tempfile F_id_crossreference_numeric F_id_mergeback_rowtest
* the inventory is required
foreach fam of global IDFAMS {
    if `"${IDVARS_`fam'}"' == "" {
        di as error "no \$IDVARS_`fam': the ID inventory is required (ask the user which variables hold `fam' ids)"
        exit 198
    }
}
file open `T1' using `F_id_crossreference_numeric', write replace
file write `T1' "dataset,variable,family,n_nonmiss,n_distinct,n_outside_image,n_in_old_only,share_old_only,expected_hits_if_unscrambled,min,max" _n
file open `T3' using `F_id_mergeback_rowtest', write replace
file write `T3' "dataset,id_variable,family,other_column,n_rows_with_old_id,n_rows_other_nonmiss,n_rows_equal,share_of_nonmiss,column_is_old_id" _n
import delimited using `WS', clear varnames(1)
foreach fam of global IDFAMS {
    quietly levelsof share_old_only if family=="`fam'", local(sh)
    local SHARE_`fam' = `sh'
}
file open IN using "$DTALIST", read text
file read IN line
while r(eof)==0 {
    local rel "`line'"
    quietly use "$DATADIR/`rel'", clear
    quietly ds
    local allv `r(varlist)'
    foreach v of local allv {
        local lv = strlower("`v'")
        local fam ""
        local src ""
        * 1. the user's inventory: listed variables, by name, per family
        foreach f of global IDFAMS {
            foreach s of global IDVARS_`f' {
                if "`fam'"=="" & "`lv'"==strlower("`s'") {
                    local fam "`f'"
                    local src "inventory"
                }
            }
        }
        if "`fam'"=="" continue
        local ty : type `v'
        capture confirm numeric variable `v'
        local isnum = _rc==0
        quietly count if !missing(`v')
        local nnm = r(N)
        local nd = 0
        if `nnm'>0 {
            preserve
                quietly keep `v'
                quietly drop if missing(`v')
                quietly duplicates drop
                local nd = _N
            restore
        }
        if !`isnum' {
            continue
        }
        if `nnm'==0 continue
        * ---- Test 1 ----
        preserve
            quietly keep `v'
            quietly drop if missing(`v')
            quietly duplicates drop
            quietly summarize `v'
            local mn = r(min)
            local mx = r(max)
            rename `v' val
            quietly merge m:1 val using "$WATCH/WL_image_`fam'.dta", keep(master match) gen(_mi)
            quietly count if _mi==1
            local outimg = r(N)
            drop _mi
            quietly merge m:1 val using "$WATCH/WL_origonly_`fam'.dta", keep(master match) gen(_mo)
            quietly count if _mo==3
            local inold = r(N)
            file write `T1' `""`rel'","`v'","`fam'",`nnm',`nd',`outimg',`inold',`SHARE_`fam'',`=round(`nd'*`SHARE_`fam'',1)',`mn',`mx'"' _n
        restore
        * ---- Test 2: old id recovered through the crosswalk, compared column by column ----
        local spec : word 1 of ${XW_`fam'}
        local ocol : word 2 of ${XW_`fam'}
        local ncol : word 3 of ${XW_`fam'}
        preserve
            quietly gen double __new = `v'
            tempfile xw
            quietly {
                frame create __xw
                frame __xw: use "$XWALK/`spec'", clear
                frame __xw: keep `ocol' `ncol'
                frame __xw: rename (`ocol' `ncol') (__old __new)
                frame __xw: duplicates drop __new, force
                frame __xw: save `xw', replace
                frame drop __xw
                merge m:1 __new using `xw', keep(master match) keepusing(__old) nogen
            }
            quietly count if !missing(__old)
            local nold = r(N)
            if `nold'>0 {
                foreach w of local allv {
                    if "`w'"=="`v'" continue
                    capture confirm numeric variable `w'
                    if _rc==0 {
                        quietly count if !missing(`w') & !missing(__old)
                        local nnw = r(N)
                        quietly count if `w'==__old & !missing(__old)
                    }
                    else {
                        quietly count if `w'!="" & !missing(__old)
                        local nnw = r(N)
                        quietly count if `w'==string(__old, "%20.0g") & !missing(__old)
                    }
                    local eq = r(N)
                    if `eq'>0 {
                        local sh = `eq'/max(`nnw',1)
                        file write `T3' `""`rel'","`v'","`fam'","`w'",`nold',`nnw',`eq',`=round(`sh',0.001)',`=`sh'>=0.99 & `eq'>=10'"' _n
                    }
                }
            }
        restore
    }
    file read IN line
}
file close IN
file close `T1'
file close `T3'
* ---- write the tabs ----
import delimited using `WS', clear varnames(1) stringcols(1)
export excel using "$WORKBOOK", sheet("id_watchlist_sizes") sheetreplace firstrow(variables)
foreach t in id_crossreference_numeric id_mergeback_rowtest {
    import delimited using `F_`t'', clear varnames(1) stringcols(_all) bindquote(strict)
    if _N == 0 set obs 1
    local sh = subinstr("`t'", "crossreference", "crossref", 1)
    export excel using "$WORKBOOK", sheet("`sh'") sheetreplace firstrow(variables)
}
di as txt "id_leak_tests done -> $WORKBOOK"
