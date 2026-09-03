*! scramble_id -- build one seeded, monotonic, 1-to-1 ID correspondence table.
* Put this dir on the adopath (`adopath + "<dir>"`), then call the program.
*
* Input : data in memory holding the OLD id values (dups/missing ok) in `oldval`.
* Output: in memory, a 2-column table  <newname>  <newname>_pubrep.
* Fails loud (exit 198) if the target range is too tight to stay 1-to-1.
program define scramble_id
    args newname lo hi
    drop if missing(oldval)
    duplicates drop
    quietly count
    local n = r(N)
    if (`hi' - `lo' + 1) < 3*`n' {
        di as error "scramble_id `newname': range [`lo',`hi'] too tight for `n' values (want width >= ~5-10x)."
        exit 198
    }
    sort oldval
    gen double _u   = runiform()
    gen double _cum = sum(_u)
    quietly summarize _cum
    gen double _p   = `lo' + (`hi' - `lo') * _cum / r(max)
    gen long   _new = round(_p)                 // 'long', never 'byte'
    replace _new = _new[_n-1] + 1 if _n > 1 & _new <= _new[_n-1]
    assert _new >= `lo' & _new <= `hi'
    assert _new > _new[_n-1] if _n > 1
    rename oldval `newname'
    rename _new   `newname'_pubrep
    keep `newname' `newname'_pubrep
    label variable `newname'_pubrep "scrambled `newname' (public release)"
end
