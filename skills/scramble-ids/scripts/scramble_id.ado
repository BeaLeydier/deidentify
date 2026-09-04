*! scramble_id -- build one seeded, RANDOM, 1-to-1 ID correspondence table, optionally banded.
* Put this dir on the adopath (`adopath + "<dir>"`), set the seed, then call the program.
*
*   scramble_id <newname> <lo> <hi> [, cuts(c1 c2 ...)]
*
* Input : data in memory holding the OLD id values (dups/missing ok) in `oldval`.
* Output: in memory, a 2-column table  <newname>  <newname>_pubrep  (old -> new, 1-to-1).
*
* The map is a random permutation: the new ids carry NO information about the order of the
* old ones (an order-preserving map lets anyone with the original ids re-identify every row
* with one sort, so it is not suitable for public release). When the analysis code needs a
* cutoff on the id (`if id > 154`), give the cutoff(s) in cuts(): old values in each band
* (<= c1, c1 < . <= c2, ..., > ck) are mapped into disjoint, ordered slices of [lo,hi], randomly
* WITHIN each band, so the cutoff survives (rewrite it once in the code to the slice boundary
* the program prints) while the order inside each band does not.
* Fails loud (exit 198) if the range is too tight to stay 1-to-1; warns above 2^24 (default
* float storage in the analysis code would round such ids).
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
    if (`hi' - `lo' + 1) < 3*`n' {
        di as error "scramble_id `newname': range [`lo',`hi'] too tight for `n' values (want width >= ~5-10x)."
        exit 198
    }
    if `hi' > 16777216 di as error "scramble_id `newname': ids above 2^24 are rounded by Stata's default float; keep hi <= 16777216 unless every id variable is long/double."
    * band index of each old value: 0 for <= c1, 1 for (c1,c2], ..., k for > ck
    gen int _band = 0
    local k = 0
    foreach c of numlist `cuts' {
        local ++k
        quietly replace _band = `k' if oldval > `c'
    }
    * disjoint slices of [lo,hi], one per band, proportional to the band's count
    tempname W
    quietly {
        gen double _u = runiform()
        sort _band _u
        by _band: gen long _r = _n
        by _band: gen long _N_b = _N
        gen long _new = .
        local start = `lo'
        forvalues b = 0/`k' {
            summarize _N_b if _band==`b', meanonly
            local nb = cond(r(N)>0, r(max), 0)
            local width = floor((`hi' - `lo' + 1) * `nb' / `n')
            if `nb' > 0 {
                * random 1-to-1 draw inside the slice: take nb distinct positions out of `width'
                gen double _v = runiform() if _band==`b'
                sort _band _v
                by _band: replace _new = `start' + floor((_n - 1) * `width' / `nb') + floor(runiform() * (`width' / `nb')) if _band==`b'
                drop _v
                di as txt "  band `b': `nb' ids -> [`start', `=`start'+`width'-1']"
                local start = `start' + `width'
            }
        }
    }
    isid _new
    assert _new >= `lo' & _new <= `hi'
    quietly spearman oldval _new
    di as txt "  rank correlation old vs new (Spearman) = " %6.3f r(rho) cond("`cuts'"=="", " (should be ~0)", " (bands preserve the cutoff order only)")
    rename oldval `newname'
    rename _new   `newname'_pubrep
    keep `newname' `newname'_pubrep
    sort `newname'
    label variable `newname'_pubrep "scrambled `newname' (public release)"
end
