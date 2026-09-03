*! list_pii_surfaces -- enumerate PII surfaces in the dataset in memory (read-only).
* Writes ONE review workbook (<stub>_review.xlsx: sheets `summary`, `variables`)
* plus a free-text dump (<stub>_dump.txt). The `variables` sheet has empty `is_pii`
* and `action` columns for the reviewer to fill. Put this dir on the adopath, then:
*     use "data.dta", clear
*     list_pii_surfaces, stub(surfaces) outdir(".")
* See references/pii-surfaces.md for the full checklist (A-D).
program define list_pii_surfaces, rclass
    syntax , STUB(string) [OUTdir(string)]
    if "`outdir'"=="" local outdir "."

    * --- free-text surfaces dump (B1 value labels, B4 notes+char, B2/B3 keywords) ---
    quietly log using "`outdir'/`stub'_dump.txt", text replace name(surfdump)
    di "=== VALUE LABELS (B1) ==="
    label list
    di _n "=== NOTES (B4) ==="
    notes
    di _n "=== CHARACTERISTICS (B4) ==="
    char list
    di _n "=== KEYWORD HITS in names+labels (B2/B3) ==="
    lookfor name address phone email gps latitude longitude coord dob birth date ///
            id respondent enumerator interviewer village household consent
    quietly log close surfdump

    * --- per-variable table -> intermediate CSV (A1 strings, A3 numerics, B2 labels) ---
    tempfile vcsv
    tempname V
    file open `V' using "`vcsv'", write replace
    file write `V' "variable,type,is_string,value_label,variable_label" _n
    local nstr = 0
    local nlab = 0
    local nvarlab = 0
    foreach v of varlist _all {
        local ty : type `v'
        local isstr = cond(substr("`ty'",1,3)=="str",1,0)
        local vl : value label `v'
        local ll : variable label `v'
        local nstr = `nstr' + `isstr'
        if "`vl'" != "" local nlab = `nlab' + 1
        if "`ll'" != "" local nvarlab = `nvarlab' + 1
        file write `V' `"`v',`ty',`isstr',`vl',"`ll'""' _n
    }
    file close `V'

    quietly describe
    local nvars = r(k)
    local nobs  = r(N)
    quietly label dir
    local nlabdefs : word count `r(names)'

    * --- assemble ONE workbook: variables sheet (+ empty input cols) + summary ---
    import delimited using "`vcsv'", varnames(1) clear stringcols(_all)
    gen is_pii = ""          // reviewer input: yes/no
    gen action = ""          // reviewer input: drop / placeholder / keep
    export excel using "`outdir'/`stub'_review.xlsx", sheet("variables") sheetreplace firstrow(variables)

    clear
    set obs 7
    gen str32 metric = ""
    gen str32 value  = ""
    replace metric = "n_variables"                  in 1
    replace value  = "`nvars'"                       in 1
    replace metric = "n_observations"               in 2
    replace value  = "`nobs'"                        in 2
    replace metric = "n_string_variables"           in 3
    replace value  = "`nstr'"                        in 3
    replace metric = "n_numeric_variables"          in 4
    replace value  = "`=`nvars'-`nstr''"             in 4
    replace metric = "n_variables_with_value_label" in 5
    replace value  = "`nlab'"                        in 5
    replace metric = "n_value_labels_defined"       in 6
    replace value  = "`nlabdefs'"                    in 6
    replace metric = "n_variables_with_var_label"   in 7
    replace value  = "`nvarlab'"                     in 7
    export excel using "`outdir'/`stub'_review.xlsx", sheet("summary") sheetreplace firstrow(variables)

    return scalar n_string = `nstr'
    return scalar n_variables = `nvars'
end
