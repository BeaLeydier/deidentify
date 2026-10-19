* drop_unused.do -- TEMPLATE: apply the minimisation to a RUN COPY (never the release) in ONE
* round; the proof is the re-run of the package that follows (every output identical).
* ADAPT: set these globals in the project's config.do (or above this line):
*   $RELEASE   the audited package (read-only; source of type/label for the manifest)
*   $RUNCOPY   the working copy whose datasets are modified
*   $VARUSAGE  varusage_review.xlsx written by find_used_variables (the `dataset` column holds
*              the dataset path relative to the package root, as listed in its datasets() file)
*   $DROP_STRUCTURAL  1 = also drop class "structural-only" (named only in keep/order/rename/
*              label/...). Those lines must then be edited in the run copy's do-files too --
*              that is project-specific: write it as its own script and list every changed line.
* Drops class "drop?" (referenced by no do-file) and "wildcard-only-droppable" (reached only
* through wildcards/ranges that also match other variables, never used in a calculation).
* Writes the manifest as sheet `dropped` of $VARUSAGE (one row per dropped variable).
import excel using "$VARUSAGE", sheet("variables") firstrow clear allstring
gen byte todrop = inlist(class, "drop?", "wildcard-only-droppable")
* a pattern anchor (the last member of a wildcard family, kept so `keep x*` still matches) stays:
* removing the pattern from the code would also change what it does to variables the code creates
if "$DROP_STRUCTURAL"=="1" replace todrop = 1 if class=="structural-only" & !strpos(how, "pattern anchor")
keep if todrop
keep dataset variable class how referenced_in
sort dataset variable
frame put *, into(__W)
levelsof dataset, local(paths)
local np = 0
foreach p of local paths {
    local ++np
    quietly levelsof variable if dataset=="`p'", local(VS`np')
    local P`np' "`p'"
}
* type and label come from the RELEASE, where every variable still exists
frame __W {
    gen type = ""
    gen label = ""
}
forvalues i = 1/`np' {
    local p "`P`i''"
    local vs "`VS`i''"
    quietly use "$RELEASE/`p'", clear
    foreach v of local vs {
        local ty : type `v'
        local lab : variable label `v'
        mata: st_local("lab", subinstr(st_local("lab"), char(96), "'"))
        frame __W: quietly replace type = "`ty'" if dataset=="`p'" & variable=="`v'"
        frame __W: quietly replace label = `"`lab'"' if dataset=="`p'" & variable=="`v'"
    }
    quietly use "$RUNCOPY/`p'", clear
    local todrop ""
    foreach v of local vs {
        capture confirm variable `v'
        if _rc==0 local todrop "`todrop' `v'"
    }
    if "`todrop'"!="" {
        drop `todrop'
        quietly save "$RUNCOPY/`p'", replace
    }
    di as txt "`p': `: word count `todrop'' dropped"
}
frame __W {
    gen byte is_string = substr(type, 1, 3)=="str"
    * Excel refuses invalid UTF-8 and control characters (old Latin-1 labels): clean them
    foreach s in label referenced_in how {
        replace `s' = ustrregexra(ustrfix(`s', "?"), "[\x00-\x1F]", " ")
    }
    order dataset variable class type is_string label how referenced_in
    export excel using "$VARUSAGE", sheet("dropped") sheetreplace firstrow(variables)
    quietly count
    di as txt "dropped `r(N)' variables -> sheet dropped of $VARUSAGE"
}
frame drop __W
