/* find_used_variables.do -- keep-list builder for the "minimize variables" step.
 *
 * Tokenizes EVERY dofile in the package (construction + analysis), then for each
 * dataset writes a CSV marking which variables appear in the code (by exact name
 * or via a `stub*` wildcard used in the code) and which are candidates to drop.
 *
 * It is intentionally CONSERVATIVE (when unsure, keep) and it is a PROPOSAL, not
 * a decision: it cannot see variables reached only through $global varlists that
 * are built dynamically, `ds`/wildcard logic, or `merge, keepusing()`. Review
 * the "candidate to drop" list with the user, drop from a COPY in the public
 * package only, and then prove it by re-running the whole package (stage 3).
 *
 * Adapt the two lists below.
 */
set more off

* ---- CONFIG: every dofile in the package, and every dataset to screen ----
local DOFILES : dir "orig" files "*.do"      // or list them explicitly
local DODIR   "orig"
local DATASETS "orig/children.dta orig/household.dta"   // paths to screen
local OUTDIR  "2-updatecode"                  // where CSVs are written

* always-keep, regardless of token match (ids, merge/sort/xtset keys, _pubrep)
local ALWAYSKEEP "personid hhid memberid clusterid round grade *_pubrep"

* ---- collect tokens from all dofiles via Mata cat (verbatim, see reference) ----
local paths ""
foreach f of local DOFILES {
    local paths `"`paths' "`DODIR'/`f'""'
}
mata:
    files = tokens(st_local("paths"))'
    allt  = J(0,1,"")
    for (f=1; f<=rows(files); f++) {
        if (fileexists(files[f])==0) continue
        L = cat(files[f])
        for (i=1; i<=rows(L); i++) {
            s = ustrregexra(L[i], "[^A-Za-z0-9_*]", " ")   // non-word -> space
            allt = allt \ tokens(s)'
        }
    }
    allt = uniqrows(strlower(allt))
    st_local("ntok", strofreal(rows(allt)))
    stata("clear")
    st_addobs(rows(allt))
    ci = st_addvar("str244","tok")
    for (i=1; i<=rows(allt); i++) st_sstore(i, ci, allt[i])
end
tempfile toks
save `toks', replace

* split tokens into exact words and wildcard stubs
gen byte isstub = strpos(tok,"*")>0
gen str244 stub = substr(tok,1,strpos(tok,"*")-1) if isstub
levelsof tok  if !isstub, local(EXACT)  clean
levelsof stub if isstub & stub!="", local(STUBS) clean

* ---- screen each dataset ----
foreach d of local DATASETS {
    use "`d'", clear
    quietly ds
    local vars `r(varlist)'
    clear
    local nv : word count `vars'
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
        * always-keep patterns
        foreach k of local ALWAYSKEEP {
            if strmatch("`lv'", strlower("`k'")) local u = 1
        }
        if `u'==1 local h = "always-keep"
        * exact token
        if `u'==0 & `: list lv in EXACT' local u = 1
        if `u'==1 & "`h'"=="drop?" local h = "exact"
        * wildcard stub prefix
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
    export delimited variable used how using "`OUTDIR'/varusage_`base'.csv", replace
    quietly count if used==0
    di as result "`base': " r(N) " of `nv' variables flagged as candidates to drop -> `OUTDIR'/varusage_`base'.csv"
}
