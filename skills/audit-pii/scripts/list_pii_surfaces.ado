*! list_pii_surfaces -- enumerate PII surfaces in the dataset in memory (read-only).
* Writes ONE review workbook (<stub>_review.xlsx: sheets `summary`, `variables`, `identifiers`)
* plus a free-text dump (<stub>_dump.txt). The `variables` sheet has empty `is_pii`
* and `action` columns for the reviewer to fill. idvars() takes the user's ID inventory
* (variable names or globs): those are reported as user-listed identifiers; id-like names and
* row-unique variables that are NOT listed are reported as candidates for the user to accept
* or reject (they never reclassify a listed variable). Put this dir on the adopath, then:
*     use "data.dta", clear
*     list_pii_surfaces, stub(surfaces) outdir(".") idvars("personid hhid *_pubrep")
* See references/pii-surfaces.md for the full checklist (A-D).
program define list_pii_surfaces, rclass
    syntax , STUB(string) [OUTdir(string) IDVars(string)]
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
        * labels may contain a backtick or double quote (e.g. an unexpanded
        * macro reference left in the label). Referencing such a label inside a
        * compound-quoted `file write' breaks Stata's parser (rc=198) and the file
        * is silently skipped. Neutralised via mata, which reads the macro value
        * without sending it back through the macro parser.
        mata: st_local("ll", subinstr(subinstr(st_local("ll"), char(96), "'"), char(34), "'"))
        mata: st_local("vl", subinstr(subinstr(st_local("vl"), char(96), "'"), char(34), "'"))
        local nstr = `nstr' + `isstr'
        if "`vl'" != "" local nlab = `nlab' + 1
        if "`ll'" != "" local nvarlab = `nvarlab' + 1
        file write `V' `"`v',`ty',`isstr',`vl',"`ll'""' _n
    }
    file close `V'

    * --- identifier / linkage FYI: id/code-named vars + vars that uniquely identify
    *     rows (alone, or the id-named set jointly). Not a flag -- for human review of
    *     whether these keys belong here / risk being merged with an external source. ---
    tempfile icsv
    tempname I
    file open `I' using "`icsv'", write replace
    file write `I' "variable,user_listed,name_looks_like_id,uniquely_ids_alone,is_scrambled_pubrep,status,note" _n
    local idnamed ""
    foreach v of varlist _all {
        local lv = strlower("`v'")
        local ul = 0
        foreach k of local idvars {
            if strmatch("`lv'", strlower("`k'")) local ul = 1
        }
        local nm = 0
        if strmatch("`lv'","*id") | strmatch("`lv'","*_id*") | strmatch("`lv'","*code*") ///
           | strmatch("`lv'","*key*") | strmatch("`lv'","*uuid*") | strmatch("`lv'","*serial*") local nm = 1
        capture isid `v'
        local uq = (_rc==0)
        local pr = strmatch("`lv'","*_pubrep")
        if `ul' | `nm' | `uq' {
            if `ul' | `nm' local idnamed "`idnamed' `v'"
            local st = cond(`ul', "identifier (user inventory)", "candidate (not in the user inventory: accept or reject)")
            local note = cond(`pr',"scrambled release id", ///
                cond(`nm' & `uq',"id-name AND unique", cond(`uq',"uniquely identifies rows","id-like name")))
            file write `I' "`v',`ul',`nm',`uq',`pr',`st',`note'" _n
        }
    }
    local jointnote "n/a (no listed or id-named vars)"
    if "`idnamed'" != "" {
        capture isid `idnamed'
        local jointnote = cond(_rc==0,"YES: listed + id-named vars jointly identify rows","no")
    }
    file write `I' "(joint key),,,,,,`jointnote'" _n
    file close `I'

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

    import delimited using "`icsv'", varnames(1) clear stringcols(_all)
    export excel using "`outdir'/`stub'_review.xlsx", sheet("identifiers") sheetreplace firstrow(variables)

    return scalar n_string = `nstr'
    return scalar n_variables = `nvars'
end
