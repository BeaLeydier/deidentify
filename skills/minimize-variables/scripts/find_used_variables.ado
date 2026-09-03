*! find_used_variables -- keep-list builder for the "minimize variables" step.
* Tokenizes every dofile (verbatim, via Mata cat), then per dataset writes which
* variables the code uses vs candidates to drop. Results go to FILES. Conservative
* (when unsure, keeps) and a PROPOSAL -- review before dropping, prove by re-running.
* Put this dir on the adopath, then:
*     find_used_variables, dofiles("code/a.do code/b.do") ///
*         datasets("orig/x.dta orig/y.dta") outdir(".") ///
*         alwayskeep("personid hhid *_pubrep")
program define find_used_variables
    syntax , DOfiles(string) DATAsets(string) [OUTdir(string) ALWAYSkeep(string)]
    if "`outdir'"=="" local outdir "."
    set more off

    * ---- collect tokens from all dofiles (verbatim) ----
    mata:
        files = tokens(st_local("dofiles"))'
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
        ci = st_addvar("str244","tok")
        for (i=1; i<=rows(allt); i++) st_sstore(i, ci, allt[i])
    end
    gen byte isstub = strpos(tok,"*")>0
    gen str244 stub = substr(tok,1,strpos(tok,"*")-1) if isstub
    levelsof tok  if !isstub, local(EXACT)  clean
    levelsof stub if isstub & stub!="", local(STUBS) clean

    * ---- summary accumulator ----
    tempname SM
    file open `SM' using "`outdir'/varusage_summary.csv", write replace
    file write `SM' "dataset,n_variables,n_keep,n_candidates_drop" _n

    foreach d of local datasets {
        use "`d'", clear
        quietly ds
        local vars `r(varlist)'
        local nv : word count `vars'
        clear
        set obs `nv'
        gen strL variable = ""
        gen byte used = 0
        gen str20 how = ""
        local i = 0
        foreach v of local vars {
            local ++i
            quietly replace variable = "`v'" in `i'
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
            quietly replace used = `u' in `i'
            quietly replace how  = "`h'" in `i'
        }
        local base = ustrregexra("`d'", "^.*/", "")
        local base = ustrregexra("`base'", "\.dta$", "")
        export delimited variable used how using "`outdir'/varusage_`base'.csv", replace
        quietly count if used==0
        local ndrop = r(N)
        file write `SM' "`base',`nv',`=`nv'-`ndrop'',`ndrop'" _n
    }
    file close `SM'
end
