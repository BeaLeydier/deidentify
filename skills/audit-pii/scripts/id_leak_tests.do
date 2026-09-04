* id_leak_tests.do -- TEMPLATE: identifier leak tests against private crosswalks.
* Set the globals (or `do` a config file):
*   $DATADIR   folder with the RELEASE datasets     $DTALIST  text file, one dataset path per line
*   $OUTDIR    where the CSVs go                    $SCRATCH  PRIVATE folder for the watch lists (never shipped)
*   $XWALK     folder with the crosswalk .dta files
*   $IDFAMS    "fam1 fam2 ..."   and, per family,  $XW_fam1 "<crosswalk file> <old id column> <new id column>"
*   (the fourth family is treated as the teacher family in the name matching below; adapt the
*    name patterns in the `foreach v of local allv` block to the package's id vocabulary)
*
* Part A (from the crosswalks): ALL OLD, ALL NEW, OLD-ONLY (old minus new) per family, and a
*   size table -- the overlap says how informative the membership test is for that family.
* Part B, test 1 (per identifier variable, distinct values): n_outside_image (not a legal new
*   id) and n_in_old_only (provably an old id); expected_hits_if_unscrambled = n_distinct x
*   share_old_only, what an UNSCRAMBLED column would show.
*   Which variables are identifiers: a name that carries a family word is a CANDIDATE; it is
*   kept only if numeric with > 2 distinct values (0/1 indicators that merely mention the word
*   are listed as excluded). The kept list is exported (identifier_variables.csv).
* Test 2: digit-only string values >= 10,000 against every family's OLD-ONLY set.
* Test 3 (old id elsewhere in the row, column-wise): recover each row's OLD id through the
*   crosswalk (new -> old); for EVERY other column count rows equal to it; a column equal on
*   >= 99% of its non-missing rows and on >= 10 rows is an old-id column kept by mistake.
* ---------------------------------------------------------------------------------------------
* ---- Part A: watch lists ----
cap mkdir "$SCRATCH"
tempname S
file open `S' using "$OUTDIR/id_watchlist_sizes.csv", write replace
file write `S' "family,n_old_ids,n_new_ids,n_overlap_old_in_new,n_old_only,share_old_only,spearman_old_new,order_retained" _n
foreach fam of global IDFAMS {
    local spec : word 1 of ${XW_`fam'}
    local ocol : word 2 of ${XW_`fam'}
    local ncol : word 3 of ${XW_`fam'}
    * rank retention: Spearman correlation between old and new ids over the crosswalk itself.
    * ~0 = the map is a random relabel; |rho| near 1 = order preserved, i.e. anyone holding the
    * original ids re-identifies every row with one sort -- reported as a weakness.
    use "$XWALK/`spec'", clear
    quietly spearman `ocol' `ncol'
    local rho = r(rho)
    local ret = cond(abs(`rho')<0.1,"no",cond(abs(`rho')<0.9,"partial","YES (order-preserving)"))
    * ALL OLD
    use "$XWALK/`spec'", clear
    keep `ocol'
    rename `ocol' val
    drop if missing(val)
    duplicates drop
    sort val
    save "$SCRATCH/WL_old_`fam'.dta", replace
    local nold = _N
    * ALL NEW  (= the "image" set)
    use "$XWALK/`spec'", clear
    keep `ncol'
    rename `ncol' val
    drop if missing(val)
    duplicates drop
    sort val
    save "$SCRATCH/WL_image_`fam'.dta", replace
    local nnew = _N
    * OLD-ONLY = old ids that are not in the new set
    merge 1:1 val using "$SCRATCH/WL_old_`fam'.dta"
    keep if _merge==2
    keep val
    sort val
    save "$SCRATCH/WL_origonly_`fam'.dta", replace
    local noo = _N
    file write `S' "`fam',`nold',`nnew',`=`nold'-`noo'',`noo',`=round(`noo'/`nold',0.0001)',`=round(`rho',0.001)',`ret'" _n
    di as txt "`fam': old=`nold' new=`nnew' old-only=`noo' (share `=round(`noo'/`nold',0.001)') spearman=`=round(`rho',0.001)' order retained: `ret'"
}
file close `S'
* ---- Part B: tests ----
tempname ID T1 T2 T3
file open `ID' using "$OUTDIR/identifier_variables.csv", write replace
file write `ID' "dataset,variable,family,storage_type,n_nonmiss,n_distinct,kept_as_identifier,reason" _n
file open `T1' using "$OUTDIR/id_crossreference_numeric.csv", write replace
file write `T1' "dataset,variable,family,n_nonmiss,n_distinct,n_outside_image,n_in_old_only,share_old_only,expected_hits_if_unscrambled,min,max" _n
file open `T2' using "$OUTDIR/id_crossreference_string.csv", write replace
file write `T2' "dataset,variable,n_digit_values_ge_10000,family,n_outside_image,n_in_old_only" _n
file open `T3' using "$OUTDIR/id_mergeback_rowtest.csv", write replace
file write `T3' "dataset,id_variable,family,other_column,n_rows_with_old_id,n_rows_other_nonmiss,n_rows_equal,share_of_nonmiss,column_is_old_id" _n
import delimited using "$OUTDIR/id_watchlist_sizes.csv", clear varnames(1)
foreach fam of global IDFAMS {
    quietly levelsof share_old_only if family=="`fam'", local(sh)
    local SHARE_`fam' = `sh'
}
local TFAM : word 4 of $IDFAMS
file open IN using "$DTALIST", read text
file read IN line
while r(eof)==0 {
    local rel "`line'"
    quietly use "$DATADIR/`rel'", clear
    quietly ds
    local allv `r(varlist)'
    quietly ds, has(type string)
    local strv `r(varlist)'
    foreach v of local allv {
        local lv = strlower("`v'")
        local fam ""
        if strpos("`lv'","mauza") local fam "mauzaid"
        else if strpos("`lv'","childcode") | strpos("`lv'","uniqueid") local fam "childcode"
        else if strpos("`lv'","teacher") & (strpos("`lv'","code") | strpos("`lv'","_id") | strpos("`lv'","teacherid")) local fam "`TFAM'"
        else if strpos("`lv'","hhid") local fam "hhid"
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
            file write `ID' `""`rel'","`v'","`fam'","`ty'",`nnm',`nd',0,"string variable (covered by test 2)""' _n
            continue
        }
        if `nd'<=2 {
            file write `ID' `""`rel'","`v'","`fam'","`ty'",`nnm',`nd',0,"name mentions a family word but it is a 0/1 indicator, not an id""' _n
            continue
        }
        file write `ID' `""`rel'","`v'","`fam'","`ty'",`nnm',`nd',1,"identifier""' _n
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
            quietly merge m:1 val using "$SCRATCH/WL_image_`fam'.dta", keep(master match) gen(_mi)
            quietly count if _mi==1
            local outimg = r(N)
            drop _mi
            quietly merge m:1 val using "$SCRATCH/WL_origonly_`fam'.dta", keep(master match) gen(_mo)
            quietly count if _mo==3
            local inold = r(N)
            file write `T1' `""`rel'","`v'","`fam'",`nnm',`nd',`outimg',`inold',`SHARE_`fam'',`=round(`nd'*`SHARE_`fam'',1)',`mn',`mx'"' _n
        restore
        * ---- Test 3: old id recovered through the crosswalk, compared column by column ----
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
    * ---- Test 2: digit-only strings, values >= 10,000, against every family ----
    foreach v of local strv {
        preserve
            quietly keep `v'
            quietly gen double val = real(`v')
            quietly keep if !missing(val) & regexm(trim(`v'),"^[0-9]+$") & val>=10000
            if _N>0 {
                quietly keep val
                quietly duplicates drop
                local nv = _N
                foreach fam of global IDFAMS {
                    quietly merge m:1 val using "$SCRATCH/WL_image_`fam'.dta", keep(master match) gen(_mi)
                    quietly count if _mi==1
                    local outimg = r(N)
                    drop _mi
                    quietly merge m:1 val using "$SCRATCH/WL_origonly_`fam'.dta", keep(master match) gen(_mo)
                    quietly count if _mo==3
                    local inold = r(N)
                    drop _mo
                    if `inold'>0 file write `T2' `""`rel'","`v'",`nv',"`fam'",`outimg',`inold'"' _n
                }
            }
        restore
    }
    file read IN line
}
file close IN
file close `ID'
file close `T1'
file close `T2'
file close `T3'
di as txt "07b done"
