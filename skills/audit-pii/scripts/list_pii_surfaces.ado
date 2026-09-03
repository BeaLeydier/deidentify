*! list_pii_surfaces -- enumerate PII surfaces in the dataset in memory (read-only).
* Results go to FILES (not the screen): a per-variable table, a counts summary, and
* a text dump of the free-text surfaces. Put this dir on the adopath, then:
*     use "data.dta", clear
*     list_pii_surfaces, stub(surfaces) outdir(".")
* See references/pii-surfaces.md for the full checklist (A-D).
program define list_pii_surfaces, rclass
    syntax , STUB(string) [OUTdir(string)]
    if "`outdir'"=="" local outdir "."

    * --- free-text surfaces (documentation dump): B1 value labels, B4 notes+char, B2/B3 ---
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

    * --- per-variable table: A1 strings, A3 numerics, B2 labels ---
    tempname V
    file open `V' using "`outdir'/`stub'_variables.csv", write replace
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

    * --- counts summary to a CSV (do NOT make the user read the log) ---
    quietly describe
    local nvars = r(k)
    local nobs  = r(N)
    quietly label dir
    local nlabdefs : word count `r(names)'
    quietly notes
    tempname S
    file open `S' using "`outdir'/`stub'_summary.csv", write replace
    file write `S' "metric,value" _n
    file write `S' "n_variables,`nvars'" _n
    file write `S' "n_observations,`nobs'" _n
    file write `S' "n_string_variables,`nstr'" _n
    file write `S' "n_numeric_variables,`=`nvars'-`nstr''" _n
    file write `S' "n_variables_with_value_label,`nlab'" _n
    file write `S' "n_value_labels_defined,`nlabdefs'" _n
    file write `S' "n_variables_with_var_label,`nvarlab'" _n
    file close `S'

    return scalar n_string = `nstr'
    return scalar n_value_labels = `nlabdefs'
    return scalar n_variables = `nvars'
end
