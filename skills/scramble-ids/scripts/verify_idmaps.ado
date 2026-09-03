*! verify_idmaps -- FAIL-LOUD checks on ID correspondence tables (idmap_<v>.dta).
* For each id map, checks 1-to-1, monotonic, and new-range-disjoint-from-old.
* Writes per-check + summary CSVs and EXITS NONZERO (459) if any check fails.
* Put this dir on the adopath, then:
*     verify_idmaps, keys("keys") idspec("myid 20000 99999 ; hhid 300000 999999") outdir(".")
program define verify_idmaps
    syntax , KEYS(string) IDSpec(string) [OUTdir(string)]
    if "`outdir'"=="" local outdir "."
    tempfile res
    postfile P str32 check str32 item str8 status str244 detail using "`res'", replace

    * idspec = semicolon-separated "v lo hi" triples
    local specs `"`idspec'"'
    while `"`specs'"' != "" {
        gettoken one specs : specs, parse(";")
        if `"`one'"'==";" continue
        gettoken v rest : one
        gettoken lo hi  : rest
        capture use "`keys'/idmap_`v'.dta", clear
        if _rc {
            post P ("LOAD") ("`v'") ("FAIL") ("cannot open `keys'/idmap_`v'.dta")
            continue
        }
        quietly count
        local n = r(N)
        quietly duplicates report `v'
        local dold = r(unique_value)
        quietly duplicates report `v'_pubrep
        local dnew = r(unique_value)
        quietly summarize `v'
        local omin = r(min)
        local omax = r(max)
        quietly summarize `v'_pubrep
        local nmin = r(min)
        local nmax = r(max)
        local overlap = !(`nmax' < `omin' | `nmin' > `omax')
        sort `v'
        quietly gen byte _bad = `v'_pubrep <= `v'_pubrep[_n-1] if _n > 1
        quietly count if _bad==1
        local nonmono = r(N)
        post P ("1-to-1")     ("`v'") (cond(`dold'==`n' & `dnew'==`n',"OK","FAIL")) ("distinct old=`dold' new=`dnew' of N=`n'")
        post P ("no-overlap") ("`v'") (cond(`overlap'==0,"OK","FAIL"))              ("old[`omin',`omax'] new[`nmin',`nmax']")
        post P ("monotonic")  ("`v'") (cond(`nonmono'==0,"OK","FAIL"))              ("`nonmono' non-increasing step(s)")
    }
    postclose P

    use "`res'", clear
    export delimited using "`outdir'/verify_idmaps_results.csv", replace
    quietly count
    local ntot = r(N)
    quietly count if status=="FAIL"
    local nfail = r(N)
    tempname S
    file open `S' using "`outdir'/verify_idmaps_summary.csv", write replace
    file write `S' "metric,value" _n
    file write `S' "checks_total,`ntot'" _n
    file write `S' "checks_passed,`=`ntot'-`nfail''" _n
    file write `S' "checks_failed,`nfail'" _n
    local resword = cond(`nfail'==0,"PASS","FAIL")
    file write `S' "result,`resword'" _n
    file close `S'
    if `nfail' > 0 {
        * Stata batch always returns OS exit 0, so drop a sentinel file the caller
        * can test for. `exit 459` still halts an in-Stata do-file chain.
        tempname F
        file open `F' using "`outdir'/verify_idmaps_FAILED.flag", write replace
        file write `F' "`nfail' of `ntot' idmap checks FAILED; see verify_idmaps_results.csv" _n
        file close `F'
        di as error "verify_idmaps: `nfail' of `ntot' check(s) FAILED -> verify_idmaps_results.csv"
        exit 459
    }
    * success: remove any stale sentinel
    capture erase "`outdir'/verify_idmaps_FAILED.flag"
end
