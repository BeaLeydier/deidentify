*! redact_clean -- remove one PII variable with a CLEAN overwrite (no ghost tail),
* and append the action to a report CSV. Put this dir on the adopath, then:
*     redact_clean pii_name, method(fullwidth) placeholder("REDACTED") report("redaction_report.csv")
*     redact_clean pii_free , method(drop)                              report("redaction_report.csv")
*     redact_clean pii_vary , method(rebuild)  newlen(20)               report("redaction_report.csv")
*
* Methods (all residue-free BY CONSTRUCTION -- a plain `replace` is not):
*   drop       : drop the variable (no bytes remain).
*   fullwidth  : set every cell to `placeholder`, recast to its exact length
*                (a full-width value has no terminator -> no tail).
*   rebuild    : copy varying values into a freshly zero-initialised str`newlen`
*                so the tails are zero, then drop the original.
* CONFIRM residue removal by re-running the tail scanner on the SAVED file
* (scan_string_tails.py) -- that is the fail-loud check.
program define redact_clean
    syntax varname, Method(string) [Placeholder(string) NEWlen(integer 0) REPORT(string)]
    local v `varlist'
    if !inlist("`method'","drop","fullwidth","rebuild") {
        di as error "redact_clean: method() must be drop | fullwidth | rebuild"
        exit 198
    }
    local note ""
    if "`method'"=="drop" {
        drop `v'
        local note "variable dropped"
    }
    if "`method'"=="fullwidth" {
        if "`placeholder'"=="" {
            di as error "redact_clean: fullwidth needs placeholder()"
            exit 198
        }
        local L = length("`placeholder'")
        replace `v' = "`placeholder'"
        recast str`L' `v', force
        local note "all cells set to placeholder in str`L' (full width, no tail)"
    }
    if "`method'"=="rebuild" {
        if `newlen' <= 0 {
            di as error "redact_clean: rebuild needs newlen()"
            exit 198
        }
        tempvar t
        gen str`newlen' `t' = ""          // zero-initialised slots
        replace `t' = `v'                 // logical values only; tails stay 0
        drop `v'
        rename `t' `v'
        local note "rebuilt on zeroed str`newlen' (tails zeroed)"
    }

    if "`report'" != "" {
        capture confirm file "`report'"
        tempname R
        if _rc {
            file open `R' using "`report'", write replace
            file write `R' "variable,method,placeholder,note" _n
        }
        else file open `R' using "`report'", write append
        file write `R' `"`v',`method',`placeholder',`note'"' _n
        file close `R'
    }
end
