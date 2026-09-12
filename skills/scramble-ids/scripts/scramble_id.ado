*! scramble_id -- build one seeded, RANDOM, 1-to-1 ID correspondence table, optionally banded.
* Put this dir on the adopath (`adopath + "<dir>"`), set the seed, then call the program.
*
*   scramble_id <newname> <lo> <hi> [, cuts(c1 c2 ...)]
*
* Input : data in memory holding the OLD id values (dups/missing ok) in `oldval`.
* Output: in memory, a 2-column table  <newname>  <newname>_pubrep  (old -> new, 1-to-1).
*
* The map is a uniformly random injection: every old value gets an independent uniform integer
* in [lo,hi], and any collision is redrawn until all new ids are distinct (rejection sampling).
* The new ids therefore carry NO information about the order or magnitude of the old ones: the
* Spearman rank correlation between old and new is ~0 up to sampling noise (SE ~ 1/sqrt(n-1));
* the program prints both. An order-preserving map lets anyone with the original ids
* re-identify every row with one sort, so it is not suitable for public release.
* When the analysis code needs a cutoff on the id (e.g. `if id > 154`), give the cutoff(s) in cuts():
* old values in each band (<= c1, c1 < . <= c2, ..., > ck) are mapped into disjoint, ordered
* slices of [lo,hi] (width proportional to the band's count), randomly WITHIN each band, so the
* cutoff survives (rewrite it once in the code to the slice boundary the program prints) while
* the order inside each band does not.
* Seeded, so a given seed reproduces the same table. Fails loud (exit 198) if the range is too
* tight to stay 1-to-1 (width < 3n overall, or a band slice narrower than 2x its count). Ids
* above 2^24 get a note: keep every id variable long/double, since Stata's default float rounds
* them (the table stores the new id as double).
program define scramble_id
    syntax anything(name=args) [, CUTS(numlist sort)]
    tokenize `args'
    local newname `1'
    local lo `2'
    local hi `3'
    drop if missing(oldval)
    duplicates drop
    quietly count
    local n = r(N)
    local W = `hi' - `lo' + 1
    if `W' < 3*`n' {
        di as error "scramble_id `newname': range [`lo',`hi'] too tight for `n' values (want width >= ~5-10x)."
        exit 198
    }
    if `hi' > 16777216 di as txt "  note: ids above 2^24 -- keep every id variable long/double (the default float rounds them)"
    * band index of each old value: 0 for <= c1, 1 for (c1,c2], ..., k for > ck (no cuts: one band)
    gen int _band = 0
    local k = 0
    if "`cuts'" != "" {
        foreach c of numlist `cuts' {
            local ++k
            quietly replace _band = `k' if oldval > `c'
        }
    }
    sort _band oldval
    * disjoint slices of [lo,hi], one per band, proportional to the band's count; the last band
    * takes the remainder so the slices tile the whole range
    gen double _new = .
    local start = `lo'
    forvalues b = 0/`k' {
        quietly count if _band == `b'
        local nb = r(N)
        if `nb' == 0 continue
        if `b' < `k' local width = floor(`W' * `nb' / `n')
        else         local width = `hi' - `start' + 1
        if `width' < 2*`nb' {
            di as error "scramble_id `newname': band `b' has `nb' ids but only `width' slots -- widen [lo,hi]."
            exit 198
        }
        if `k' > 0 di as txt "  band `b': `nb' ids -> [`start', `=`start'+`width'-1']"
        local S`b' = `start'
        local L`b' = `width'
        local start = `start' + `width'
    }
    * uniform draw inside each band's slice; redraw collisions until every new id is distinct
    forvalues b = 0/`k' {
        if "`S`b''" != "" quietly replace _new = `S`b'' + floor(runiform() * `L`b'') if _band == `b'
    }
    local iter = 0
    quietly duplicates tag _new, gen(_dup)
    quietly count if _dup > 0
    while r(N) > 0 {
        local ++iter
        forvalues b = 0/`k' {
            if "`S`b''" != "" quietly replace _new = `S`b'' + floor(runiform() * `L`b'') if _dup > 0 & _band == `b'
        }
        drop _dup
        quietly duplicates tag _new, gen(_dup)
        quietly count if _dup > 0
    }
    drop _dup _band
    isid _new
    assert _new >= `lo' & _new <= `hi'
    quietly spearman oldval _new
    di as txt "  `newname': `n' ids, `iter' redraw round(s); rank correlation old vs new (Spearman) = " ///
        %6.3f r(rho) " (SE ~ " %5.3f 1/sqrt(max(`n'-1,1)) ")" cond("`cuts'"=="", " -- should be ~0", " -- bands preserve the cutoff order only")
    rename oldval `newname'
    rename _new   `newname'_pubrep
    keep `newname' `newname'_pubrep
    sort `newname'
    label variable `newname'_pubrep "scrambled `newname' (public release)"
end
