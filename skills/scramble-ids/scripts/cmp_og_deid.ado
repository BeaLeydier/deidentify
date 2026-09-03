*! cmp_og_deid -- whole-dataset diff of an ORIGINAL vs DE-IDENTIFIED dataset over
* ALL variables (nothing pre-selected), aligned by the scrambled KEY. Confirms the
* only changes are the ids (renamed) plus any intended redaction. Writes a diff CSV
* + summary and EXITS NONZERO (459) on any unmatched row or UNEXPECTED value diff.
*
* Contract: `orig` must already contain the same key variable(s) as `deid` (merge
* the idmap into the original first). Put this dir on the adopath, then:
*     cmp_og_deid, orig("tmp_orig_with_key.dta") deid("deid/x.dta") ///
*         key("myid_pubrep") allowdiff("namevar") tag("x") outdir(".")
program define cmp_og_deid
    syntax , ORIG(string) DEID(string) KEY(string) [ALLOWdiff(string) TAG(string) OUTdir(string)]
    if "`outdir'"=="" local outdir "."
    if "`tag'"==""    local tag "dataset"

    use "`orig'", clear
    quietly ds
    local ovars `r(varlist)'
    preserve
        use "`deid'", clear
        quietly ds
        local dvars `r(varlist)'
    restore
    local deid_only : list dvars - ovars
    local orig_only : list ovars - dvars
    local common    : list ovars & dvars
    local common    : list common - key

    keep `key' `common'
    foreach v of local common {
        rename `v' O_`v'
    }
    tempfile ogc
    quietly save `ogc'
    use "`deid'", clear
    keep `key' `common'
    merge 1:1 `key' using `ogc', gen(_mm)
    quietly count if _mm != 3
    local nunmatched = r(N)
    local vdiff ""
    foreach v of local common {
        quietly count if (`v' != O_`v') & !(missing(`v') & missing(O_`v')) & _mm==3
        if r(N) > 0 local vdiff `vdiff' `v'
    }
    * unexpected = differing common var not in allowdiff
    local unexp ""
    foreach v of local vdiff {
        local vv `v'
        if !(`: list vv in allowdiff') local unexp `unexp' `v'
    }

    * ---- write diff detail + summary ----
    tempname D
    file open `D' using "`outdir'/cmp_`tag'.csv", write replace
    file write `D' "field,value" _n
    file write `D' `"deid_only_vars,"`deid_only'""' _n
    file write `D' `"orig_only_vars,"`orig_only'""' _n
    file write `D' `"differing_common_vars,"`vdiff'""' _n
    file write `D' `"unexpected_diffs,"`unexp'""' _n
    file write `D' "n_unmatched_rows,`nunmatched'" _n
    file close `D'

    local fail = cond(`nunmatched'>0 | "`unexp'"!="", 1, 0)
    tempname S
    file open `S' using "`outdir'/cmp_`tag'_summary.csv", write replace
    file write `S' "metric,value" _n
    file write `S' "n_deid_only_vars,`: word count `deid_only''" _n
    file write `S' "n_orig_only_vars,`: word count `orig_only''" _n
    file write `S' "n_differing_common_vars,`: word count `vdiff''" _n
    file write `S' "n_unexpected_diffs,`: word count `unexp''" _n
    file write `S' "n_unmatched_rows,`nunmatched'" _n
    local resword = cond(`fail'==0,"PASS","FAIL")
    file write `S' "result,`resword'" _n
    file close `S'
    if `fail' {
        * Stata batch returns OS exit 0, so drop a sentinel the caller can test for.
        tempname F
        file open `F' using "`outdir'/cmp_`tag'_FAILED.flag", write replace
        file write `F' "unmatched=`nunmatched'; unexpected diffs:`unexp'; see cmp_`tag'.csv" _n
        file close `F'
        di as error "cmp_og_deid `tag': FAIL (unmatched=`nunmatched' unexpected:`unexp') -> cmp_`tag'.csv"
        exit 459
    }
    capture erase "`outdir'/cmp_`tag'_FAILED.flag"
end
