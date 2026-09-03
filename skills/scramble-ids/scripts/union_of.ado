*! union_of -- load the UNION of an id's distinct values across several files.
* Leaves them in memory as `oldval`, ready for `scramble_id`. Use for any id that
* appears in more than one dataset, so the same entity maps consistently.
*   union_of <varname> "file1.dta" ["file2.dta" ...]
program define union_of
    gettoken v files : 0
    clear
    tempfile acc
    save `acc', emptyok replace
    foreach f of local files {
        use `v' using `f', clear
        append using `acc'
        save `acc', replace
    }
    rename `v' oldval
end
