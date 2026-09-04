* drop_unused.do -- TEMPLATE: apply the minimisation to a RUN COPY (never the release), in two
* rounds, each proven by re-running the package afterwards.
* Set the globals (or `do` a config file):
*   $RELEASE  the audited package (read-only; variable types/labels for the manifest)
*   $RUNCOPY  the working copy whose datasets are modified
*   $VARUSAGE path of varusage_review.xlsx written by find_used_variables
*   $OUTDIR   where the manifests go
*   $ROUND    1 = drop class "drop?" (referenced by no do-file)
*             2 = drop class "wildcard-only-droppable" (reached only through a wildcard/range that
*                 also matches other variables, never used in a calculation, also after renames)
* Variables classed "structural-only" (named only in keep/keepusing/order/rename) are never
* dropped here: removing them would break those commands. Flag them for the authors instead.
* The dataset column of the workbook is the space-free link name written by make_links.sh;
* the block below maps it back to a path -- adapt it to the package's folder names.
import excel using "$VARUSAGE", sheet("variables") firstrow clear
if $ROUND==1 keep if class=="drop?"
else keep if class=="wildcard-only-droppable"
gen path = subinstr(dataset, "__", "/", .)
replace path = subinstr(path, "_", " ", 1) if substr(path,1,1)=="0" | substr(path,1,1)=="2"
replace path = subinstr(path, "raw_data", "raw data", 1)
replace path = subinstr(path, "other_data", "other data", 1)
replace path = path + ".dta"
sort path variable
tempname M
file open `M' using "$OUTDIR/dropped_variables_manifest_round$ROUND.csv", write replace
file write `M' "dataset_path,variable,type,storage_class,is_string,label,how,n_pattern_siblings,referenced_in" _n
* keep the workbook in its own frame so it survives the `use` calls below
frame put path variable how n_pattern_siblings referenced_in, into(__W)
levelsof path, local(paths)
local np = 0
foreach p of local paths {
    local ++np
    quietly levelsof variable if path=="`p'", local(VS`np')
    local P`np' "`p'"
}
forvalues i = 1/`np' {
    local p "`P`i''"
    local vs "`VS`i''"
    quietly use "$RELEASE/`p'", clear
    foreach v of local vs {
        local ty : type `v'
        local isstr = substr("`ty'",1,3)=="str"
        local sc = cond(`isstr',"string","`ty'")
        local lab : variable label `v'
        mata: st_local("lab", subinstr(subinstr(subinstr(subinstr(st_local("lab"), char(96), "'"), char(34), "'"), ",", ";"), char(39), uchar(8217)))
        frame __W: quietly levelsof how if path=="`p'" & variable=="`v'", local(hw) clean
        frame __W: quietly levelsof n_pattern_siblings if path=="`p'" & variable=="`v'", local(sb) clean
        frame __W: quietly levelsof referenced_in if path=="`p'" & variable=="`v'", local(rf) clean
        file write `M' `""`p'","`v'","`ty'","`sc'",`isstr',"`lab'","`hw'","`sb'","`rf'""' _n
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
    di as txt "`p': `: word count `vs'' wildcard-only, `: word count `todrop'' dropped now"
}
frame drop __W
file close `M'
di as txt "round $ROUND done -> $OUTDIR/dropped_variables_manifest_round$ROUND.csv"
