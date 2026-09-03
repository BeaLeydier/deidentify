*! find_used_variables -- keep-list builder for the "minimize variables" step.
* Tokenizes every dofile (verbatim, via Mata cat), then per dataset marks which
* variables the code uses vs candidates to drop. Writes ONE review workbook
* (varusage_review.xlsx: sheets `summary`, `variables` with an empty `decision`
* input column). Conservative (when unsure, keeps) and a PROPOSAL -- review before
* dropping, prove by re-running. Put this dir on the adopath, then:
*     find_used_variables, dofiles("code/a.do code/b.do") ///
*         datasets("orig/x.dta orig/y.dta") outdir(".") ///
*         alwayskeep("personid hhid *_pubrep")
program define find_used_variables
    syntax , DOfiles(string) DATAsets(string) [OUTdir(string) ALWAYSkeep(string)]
    if "`outdir'"=="" local outdir "."
    set more off

    * tokenize all dofiles into a variable `tok` (Mata fn -- a multi-line mata block
    * cannot live inside program..end, so the work is in _fuv_tokens below)
    mata: _fuv_tokens("`dofiles'")
    gen byte isstub = strpos(tok,"*")>0
    gen str244 stub = substr(tok,1,strpos(tok,"*")-1) if isstub
    levelsof tok  if !isstub, local(EXACT)  clean
    levelsof stub if isstub & stub!="", local(STUBS) clean

    tempfile vcsv scsv
    tempname V S
    file open `V' using "`vcsv'", write replace
    file write `V' "dataset,variable,used,how" _n
    file open `S' using "`scsv'", write replace
    file write `S' "dataset,n_variables,n_keep,n_candidates_drop" _n

    foreach d of local datasets {
        use "`d'", clear
        quietly ds
        local vars `r(varlist)'
        local nv : word count `vars'
        local base = ustrregexra("`d'", "^.*/", "")
        local base = ustrregexra("`base'", "\.dta$", "")
        local ndrop = 0
        foreach v of local vars {
            local lv = strlower("`v'")
            local u = 0
            local h = "drop?"
            foreach k of local alwayskeep {
                if strmatch("`lv'", strlower("`k'")) local u = 1
            }
            if `u'==1 local h = "always-keep"
            if `u'==0 & `: list lv in EXACT' local u = 1
            if `u'==1 & "`h'"=="drop?" local h = "exact"
            if `u'==0 {
                foreach s of local STUBS {
                    if substr("`lv'",1,strlen("`s'"))=="`s'" {
                        local u = 1
                        local h = "wildcard `s'*"
                    }
                }
            }
            if `u'==0 local ++ndrop
            file write `V' "`base',`v',`u',`h'" _n
        }
        file write `S' "`base',`nv',`=`nv'-`ndrop'',`ndrop'" _n
    }
    file close `V'
    file close `S'

    import delimited using "`vcsv'", varnames(1) clear stringcols(_all)
    gen decision = ""        // reviewer input: keep / drop
    export excel using "`outdir'/varusage_review.xlsx", sheet("variables") sheetreplace firstrow(variables)
    import delimited using "`scsv'", varnames(1) clear stringcols(_all)
    export excel using "`outdir'/varusage_review.xlsx", sheet("summary") sheetreplace firstrow(variables)
end

* ---- Mata helper: tokenize dofiles (verbatim) into a str variable `tok` ----
mata:
void _fuv_tokens(string scalar dofiles)
{
    string colvector files, L, allt
    string scalar s
    real scalar f, i, ci
    files = tokens(dofiles)'
    allt  = J(0,1,"")
    for (f=1; f<=rows(files); f++) {
        if (fileexists(files[f])==0) continue
        L = cat(files[f])
        for (i=1; i<=rows(L); i++) {
            s = ustrregexra(L[i], "[^A-Za-z0-9_*]", " ")
            allt = allt \ tokens(s)'
        }
    }
    allt = uniqrows(strlower(allt))
    stata("clear")
    st_addobs(rows(allt))
    ci = st_addvar("str244", "tok")
    for (i=1; i<=rows(allt); i++) st_sstore(i, ci, allt[i])
}
end
