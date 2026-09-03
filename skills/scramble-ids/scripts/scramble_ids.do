/* scramble_ids.do -- reusable engine for building ID correspondence tables.
 *
 * Drop this program into your stage-1 dofile, then build one map per ID var.
 * The map is a strict 1-to-1, seeded, MONOTONIC (order-preserving) remap into a
 * new range that does NOT overlap the old range. See SKILL.md for why each
 * property matters.
 *
 * Copy + adapt the paths/variable names below to your package.
 */

*------------------------------------------------------------------*
* The engine.
* Expects: in memory, a one-column dataset whose values (possibly with
*          duplicates / missings) are the OLD id values, in a variable `oldval`.
* Produces: in memory, a 2-column table (<newname>, <newname>_pubrep).
*------------------------------------------------------------------*
capture program drop scramble_id
program define scramble_id
    args newname lo hi
    * distinct, non-missing old values only
    drop if missing(oldval)
    duplicates drop
    * range sanity: the monotonic uniqueness-nudge needs headroom, or it runs
    * off the top of [lo,hi]. Require width >= 3x the number of values and stop
    * loudly if not -- widen the range rather than fight it.
    quietly count
    local n = r(N)
    if (`hi' - `lo' + 1) < 3*`n' {
        di as error "scramble_id `newname': range [`lo',`hi'] too tight for `n' values."
        di as error "  widen it (aim for width >= ~5-10x the value count)."
        exit 198
    }
    sort oldval
    * monotone random spacing: cumulative sum of uniforms, scaled into [lo,hi]
    gen double _u   = runiform()
    gen double _cum = sum(_u)
    quietly summarize _cum
    gen double _p   = `lo' + (`hi' - `lo') * _cum / r(max)
    gen long   _new = round(_p)      // 'long', never 'byte' (byte maxes at 100)
    * enforce strictly increasing & unique while staying monotone and in range
    replace _new = _new[_n-1] + 1 if _n > 1 & _new <= _new[_n-1]
    assert _new >= `lo' & _new <= `hi'
    assert _new > _new[_n-1] if _n > 1
    rename oldval `newname'
    rename _new   `newname'_pubrep
    keep `newname' `newname'_pubrep
    label variable `newname'_pubrep "scrambled `newname' (public release)"
end

*------------------------------------------------------------------*
* Helper: build the UNION of an id's distinct values across several files,
* leaving them in memory as `oldval`. Use this for any id that appears in more
* than one dataset, so the same entity maps consistently everywhere.
*------------------------------------------------------------------*
capture program drop union_of
program define union_of
    * args: varname  file1 [file2 ...]
    gettoken v files : 0
    clear
    tempfile acc
    save `acc', emptyok replace
    foreach f of local files {
        use `v' using "`f'", clear
        append using `acc'
        save `acc', replace
    }
    rename `v' oldval
end

*==================================================================*
* TEMPLATE -- adapt everything below to your package.
*==================================================================*
* set seed 20260706          // pick a fixed seed; keep it recorded in the readme
*
* * simple case: id lives in one file
* use myid using "orig/data.dta", clear
* rename myid oldval
* scramble_id myid 20000 99999
* save "keys/idmap_myid.dta", replace
*
* * shared-universe case: two vars, one mapping (map, then rename a copy)
* union_of villageid "orig/children.dta"
* * also fold in the second-source values so the mapping covers both:
* preserve
*     use hh_villageid using "orig/children.dta", clear
*     rename hh_villageid oldval
*     tempfile b
*     save `b'
* restore
* append using `b'
* scramble_id villageid 300 999
* save "keys/idmap_villageid.dta", replace
* rename (villageid villageid_pubrep) (hh_villageid hh_villageid_pubrep)
* save "keys/idmap_hh_villageid.dta", replace   // same mapping, renamed
*
* * union case: id spans many files
* union_of hhid ///
*     "orig/children.dta" "aux/hh1.dta" "aux/hh2.dta" "aux/hh3.dta"
* scramble_id hhid 300000 999999
* save "keys/idmap_hhid.dta", replace
*
* * apply to a dataset: merge in new ids, drop originals
* use "orig/children.dta", clear
* merge m:1 myid using "keys/idmap_myid.dta", keep(master match) nogen
* merge m:1 hhid using "keys/idmap_hhid.dta", keep(master match) nogen
* drop myid hhid
* xtset <panelid>_pubrep <timevar>          // if the data was xtset
* save "deid/children.dta", replace
*==================================================================*
