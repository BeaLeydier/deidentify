*! scan_id_candidates -- propose identifier candidates for the ID inventory (read-only).
* One call for the whole package; writes two tabs of the inventory workbook:
*   candidates  one row per variable that looks like an identifier: its name looks like an id
*               (*id, *_id*, *code*, *key*, *uuid*, *serial*), or it identifies the rows of its
*               dataset on its own; with its type, distinct values, whether it is already in the
*               inventory, and the other variables (any dataset) holding exactly the same set of
*               values -- a reason to ASK whether the two are the same kind of id (same_as).
*               Empty columns family / role / decision for the user to fill.
*   datasets    one row per dataset: observations, variables, and whether the inventory's
*               variables (and, apart, all id-like names) jointly identify its rows.
* A scan only proposes: what is an id, and which ids share a universe, is the user's call.
*
*   scan_id_candidates, datasets(<list file>) [root(<dir>)] workbook(<xlsx>) ///
*       [idvars("<names / globs already in the inventory>")]
* List file: one dataset path per line (spaces allowed), relative to root() unless absolute.
program define scan_id_candidates
    version 16
    syntax , DATAsets(string) WORKbook(string) [ROOT(string) IDVars(string)]
    if "`root'"!="" & substr("`root'", -1, 1)!="/" local root "`root'/"
    tempfile C D
    tempname FC FD IN
    file open `FC' using `C', write replace
    file write `FC' "dataset,variable,type,n_nonmiss,n_distinct,name_looks_like_id,uniquely_ids_rows,in_inventory,signature" _n
    file open `FD' using `D', write replace
    file write `FD' "dataset,n_obs,n_variables,inventory_variables,inventory_identifies_rows,id_like_variables,id_like_identify_rows" _n
    file open `IN' using "`datasets'", read text
    file read `IN' line
    while r(eof)==0 {
        local rel = strtrim(`"`line'"')
        if `"`rel'"' == "" {
            file read `IN' line
            continue
        }
        local d `"`rel'"'
        if !ustrregexm(`"`d'"', "^(/|[A-Za-z]:)") local d `"`root'`d'"'
        quietly use `"`d'"', clear
        quietly ds
        local allv `r(varlist)'
        local idlike ""
        local inv ""
        foreach v of local allv {
            local listed = 0
            foreach k of local idvars {
                if strmatch("`v'", "`k'") local listed = 1
            }
            local lv = strlower("`v'")
            local nm = strmatch("`lv'","*id") | strmatch("`lv'","*_id*") | strmatch("`lv'","*code*") ///
                | strmatch("`lv'","*key*") | strmatch("`lv'","*uuid*") | strmatch("`lv'","*serial*")
            capture isid `v'
            local uq = (_rc==0) & _N > 1
            if !(`nm' | `uq' | `listed') continue
            if `nm' local idlike "`idlike' `v'"
            if `listed' local inv "`inv' `v'"
            local ty : type `v'
            quietly count if !missing(`v')
            local nnm = r(N)
            * signature of the value set: distinct count, min, max and sum of the distinct values
            * (numeric) -- equal signatures across variables suggest the same set of values
            local sig ""
            preserve
                quietly keep `v'
                quietly drop if missing(`v')
                if _N > 0 quietly duplicates drop
                local nd = _N
                capture confirm numeric variable `v'
                if _rc==0 & `nd' > 1 {
                    quietly summarize `v'
                    local sig = "n" + string(`nd') + "_" + string(r(min), "%20.0g") + "_" + string(r(max), "%20.0g") + "_" + string(r(sum), "%24.0g")
                }
            restore
            file write `FC' `""`rel'","`v'","`ty'",`nnm',`nd',`nm',`uq',`listed',"`sig'""' _n
        }
        * do the inventory's variables (and, apart, all id-like names) identify the rows?
        local jinv "n/a"
        if "`inv'" != "" {
            capture isid `inv', missok
            local jinv = cond(_rc==0, "yes", "no")
        }
        local joint "n/a"
        if "`idlike'" != "" {
            capture isid `idlike', missok
            local joint = cond(_rc==0, "yes", "no")
        }
        file write `FD' `""`rel'",`=_N',`: word count `allv'',"`=strtrim("`inv'")'","`jinv'","`=strtrim("`idlike'")'","`joint'""' _n
        file read `IN' line
    }
    file close `IN'
    file close `FC'
    file close `FD'
    * same_as: the other variables holding exactly the same set of values
    import delimited using `C', varnames(1) clear stringcols(_all) bindquote(strict)
    gen same_values_as = ""
    if _N > 0 {
        gen long _row = _n
        tempfile all
        quietly save `all'
        keep if signature != ""
        keep _row signature dataset variable
        rename (_row dataset variable) (_row2 ds2 v2)
        tempfile sig
        quietly save `sig'
        use `all', clear
        quietly joinby signature using `sig', unmatched(master)
        quietly drop if _row == _row2 | missing(_row2)
        quietly gen pair = v2 + " (" + ds2 + ")"
        quietly bysort _row (pair): gen same = pair if _n==1
        quietly by _row: replace same = same[_n-1] + "; " + pair if _n>1
        quietly by _row: keep if _n==_N
        keep _row same
        tempfile same
        quietly save `same'
        use `all', clear
        quietly merge 1:1 _row using `same', nogen
        quietly replace same_values_as = substr(same, 1, 2000) if !missing(same)
        drop same _row
    }
    drop signature
    gen family = ""          // user input: the entity the id names (person, household, village, ...)
    gen role = ""            // user input: key / part / derived / cluster / panel / time / merge
    gen decision = ""        // user input: accept / reject (and why)
    gsort -in_inventory -name_looks_like_id dataset variable
    if _N == 0 set obs 1
    export excel using "`workbook'", sheet("candidates") sheetreplace firstrow(variables)
    import delimited using `D', varnames(1) clear stringcols(_all) bindquote(strict)
    export excel using "`workbook'", sheet("datasets") sheetreplace firstrow(variables)
    di as txt "scan_id_candidates -> `workbook' (tabs candidates, datasets)"
end
