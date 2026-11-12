*! find_used_variables -- keep-list builder for the "minimize variables" step (static read).
* Reads every do-file (comments removed: // ..., * ... lines, /* ... */ blocks across lines)
* without running anything, then per dataset marks which variables the code uses and HOW:
*   exact           the name appears as a token
*   wildcard <pat>  the name matches a glob pattern in the code (prefix r1_*, suffix *_va,
*                   infix x*_q1, a reshape stub, or a macro-built name it could not fill in)
*   range a-b       the name lies inside an a-b variable range (always counted as used:
*                   dropping a member would change what the range covers)
*   always-keep     matches alwayskeep()
* Matching is CASE-SENSITIVE, like Stata's variable names.
*
* Macro-built names (s`i'_q`j') are filled with the value the macro holds AT THAT LINE (the
* do-file is read top to bottom, like Stata runs it):
*   - a loop macro takes its literal list (forvalues i = 1/12, foreach i in a b c, foreach i
*     of numlist 1/5, foreach i of local L) for the lines that follow;
*   - local y = 8 sets y to 8 until the next definition of y; local y = `x' + 2 is worked out
*     from the values of x in force (arithmetic on numbers only); local L a b c and
*     local L `L' d are lists;
*   - a macro a loop redefines from itself (a counter) or whose value comes from the run
*     (r(), levelsof, `: word', args, varlists ...) is unknown from the loop header on: the
*     name becomes a wildcard (s`i'_q`j' -> s*_q*).
* A line continued with /// belongs to the command that started it (the variables of a
* multi-line keep or rename are named by keep or rename).
* Three constructs prove nothing and are ignored: a wildcard without a letter in its literal
* part ("**12"); `rename * *_suffix`, which renames whatever happens to be in memory; and a
* pattern renamed to one fixed name (rename gs*_s*q6 fans, the macros unknown) when it matches
* several variables of a dataset -- only one of them can be meant, and the run says which.
* Names the code CREATES: the target of gen/egen is never an existing variable (gen fails
* if it exists), so it matches nothing in the data. A macro-built target (gen s`x' = ...)
* is treated as created everywhere the same macro-built name appears in that do-file (e.g. a
* `local list `list' s`x'' collecting the new dummies). Literal names and literal wildcards
* (sum s*) on other lines still count.
*
* For the reviewer, in which command CONTEXT each reference occurs:
*   calc_context    the variable (or the name it acquires through a rename, exact or A* B*)
*                   is referenced by a command that computes with it (gen, replace, egen,
*                   regressions, summarize, collapse, ...) or in an if-condition of any
*                   command (keep if age >= 6), as opposed to a purely structural use
*                   (keep, drop, order, rename, merge/keepusing, sort, ...)
*   n_pattern_siblings  for a wildcard/range match: how many OTHER variables of the same
*                   dataset the same pattern also matches (0 = dropping it would break the
*                   command); for a range: "endpoint" if it is one of the two endpoints
*   class           used-calc | structural-only | wildcard-only-droppable | always-keep | drop?
*       structural-only          : referenced by name, but only by structural commands
*                                  (dropping it means editing those lines too)
*       wildcard-only-droppable  : reached only through wildcards/ranges that have siblings,
*                                  never in a calculation (also after renames)
*       drop?                    : referenced nowhere
* Writes ONE review workbook (varusage_review.xlsx: sheets `variables`, `summary`).
* Conservative and a PROPOSAL: drop on a copy and prove it by re-running the package.
*
*   find_used_variables, dofiles(<list file>) datasets(<list file>) [root(<dir>)] ///
*       outdir(<dir>) alwayskeep("personid hhid *_pubrep")
* dofiles() / datasets(): text files, one path per line (spaces allowed). Relative paths are
* taken relative to root(). The `dataset` column of the workbook is the path as listed.
program define find_used_variables
    syntax , DOfiles(string) DATAsets(string) [ROOT(string) OUTdir(string) ALWAYSkeep(string)]
    if "`outdir'"=="" local outdir "."
    if "`root'"!="" & substr("`root'", -1, 1)!="/" local root "`root'/"
    set more off
    * structural commands: they select, arrange or label variables but do not compute with
    * them. Everything else -- reshape (consumes the stub family), merge/sort keys, duplicates,
    * collapse, egen, regressions, ... -- counts as a calculation context.
    local STRUCT "keep drop order rename ren keepusing format label compress describe des ds unab save use saveold append tostring destring recast note notes char"

    * ---- read the dataset list (one path per line)
    tempname FH
    local nds = 0
    file open `FH' using "`datasets'", read text
    file read `FH' line
    while r(eof)==0 {
        local line = strtrim(`"`line'"')
        if `"`line'"' != "" {
            local ++nds
            local DS`nds' `"`line'"'
        }
        file read `FH' line
    }
    file close `FH'

    * ---- tokenize (Mata) -> frame default: tok where cmd | rng | renold rennew
    mata: _fuv_tokens(st_local("dofiles"), st_local("root"))
    tempname TOK
    frame copy default `TOK'
    frame `TOK' {
        gen byte iswild = strpos(tok,"*")>0
        gen str244 lit  = ustrregexra(tok, "[^A-Za-z0-9]", "")
        gen byte simpleprefix = ustrregexm(tok, "^[A-Za-z0-9_]+\*$")
        * a wildcard needs a literal stem with a letter (x*, *_va, s*_q*); "**12" would match
        * almost anything and proves nothing
        gen byte usable = tok!="" & (!iswild | ((strlen(lit)>=2 | simpleprefix) & ustrregexm(lit, "[A-Za-z]")))
        * a reference counts as a calculation unless the line's command is structural
        gen byte iscalc = usable & cmd!=""
        foreach c of local STRUCT {
            replace iscalc = 0 if cmd=="`c'"
        }
    }
    frame `TOK': levelsof tok if usable & !iswild, local(EXACT) clean
    frame `TOK': levelsof tok if usable & iswild,  local(STUBS) clean
    frame `TOK': levelsof tok if usable & !iswild & iscalc, local(EXACTCALC) clean
    frame `TOK': levelsof tok if usable & iswild & iscalc,  local(STUBSCALC) clean
    frame `TOK': levelsof rng if rng!="", local(RANGES) clean
    * rename pairs (exact or wildcard): oldpat newpat
    local NREN = 0
    frame `TOK' {
        quietly count if renold!=""
        local NREN = r(N)
        forvalues i = 1/`NREN' {
            local RO`i' = renold[`i']
            local RN`i' = rennew[`i']
        }
    }
    * one location string per distinct token/pattern (first 20 places)
    tempname LOC
    frame `TOK' {
        frame put tok where if usable, into(`LOC')
    }
    frame `LOC' {
        bysort tok (where): gen n = _n
        keep if n <= 20
        by tok: gen locs = where if _n==1
        by tok: replace locs = locs[_n-1] + "; " + where if _n>1
        by tok: keep if _n==_N
        keep tok locs
        rename tok key
    }

    tempfile vcsv scsv
    tempname V S
    file open `V' using "`vcsv'", write replace
    file write `V' "dataset,variable,used,how,class,calc_context,calc_via,n_pattern_siblings,referenced_in" _n
    file open `S' using "`scsv'", write replace
    file write `S' "dataset,n_variables,n_keep,n_used_calc,n_structural_only,n_wildcard_only_droppable,n_candidates_drop" _n

    forvalues di = 1/`nds' {
        local base `"`DS`di''"'
        local d `"`base'"'
        if !ustrregexm(`"`d'"', "^(/|[A-Za-z]:)") local d `"`root'`d'"'
        use `"`d'"', clear
        quietly ds
        local vars `r(varlist)'
        local nv : word count `vars'
        local ndrop = 0
        local ncalc = 0
        local nstruct = 0
        local nwild = 0
        * expand a-b ranges whose endpoints both exist here; remember endpoints
        local INRANGE ""
        local ENDPTS ""
        foreach rg of local RANGES {
            local a = substr("`rg'", 1, strpos("`rg'","-")-1)
            local b = substr("`rg'", strpos("`rg'","-")+1, .)
            capture unab RV : `a'-`b'
            if _rc==0 {
                local INRANGE "`INRANGE' `RV'"
                local ENDPTS "`ENDPTS' `a' `b'"
            }
        }
        * only what can concern this dataset: exact names it holds, patterns and rename pairs
        * matching at least one of its variables
        local EXACT_D : list vars & EXACT
        local EXACTCALC_D : list vars & EXACTCALC
        mata: _fuv_relevant(`NREN')
        local nstub : word count `STUBS_D'
        local iv = 0
        foreach v of local vars {
            local u = 0
            local h = "drop?"
            local key ""
            local calc = 0
            local via = ""
            local sib = ""
            foreach k of local alwayskeep {
                if strmatch("`v'", "`k'") local u = 1
            }
            if `u'==1 local h = "always-keep"
            * exact reference
            local exact = `: list v in EXACT_D'
            if `exact' {
                if `u'==0 local h = "exact"
                local u = 1
                if "`key'"=="" local key "`v'"
                if `: list v in EXACTCALC_D' {
                    local calc = 1
                    local via "exact"
                }
            }
            * range
            local inrng = `: list v in INRANGE'
            if `inrng' {
                if "`h'"=="drop?" local h = "range a-b"
                local u = 1
                * a range is resolved on the dataset's variable ORDER: dropping a member changes
                * what the range covers, so every member counts as used (conservative)
                local calc = 1
                if "`via'"=="" local via "range"
                if `: list v in ENDPTS' local sib "endpoint"
                else if "`sib'"=="" local sib "range-member"
            }
            * wildcard patterns
            local matched ""
            forvalues si = 1/`nstub' {
                local s : word `si' of `STUBS_D'
                if strmatch("`v'","`s'") {
                    local u = 1
                    if "`h'"=="drop?" local h = "wildcard `s'"
                    if "`key'"=="" local key "`s'"
                    local matched "`matched' `s'"
                    if `: list s in STUBSCALC' {
                        local calc = 1
                        if "`via'"=="" local via "pattern `s'"
                    }
                    * siblings: other variables here matching the same pattern
                    local n = `: word `si' of `STUBN_D'' - 1
                    if "`sib'"=="" | "`sib'"=="range-member" local sib "`n'"
                    else if "`sib'"!="endpoint" local sib = string(min(real("`sib'"), `n'))
                }
            }
            * names acquired through renames: rename old new, rename OLD* NEW* -> NEWprefix + suffix
            if `u'==1 & `calc'==0 {
                foreach i of local RENIDX {
                    local ro "`RO`i''"
                    local rn "`RN`i''"
                    * a pattern renamed to ONE fixed name (a macro-built old name whose value the
                    * read could not fill) can rename only one of the variables it matches, and the
                    * read cannot tell which: it proves nothing for any of them (the run does)
                    if strpos("`ro'","*") & !strpos("`rn'","*") & `RENN_`i'' > 1 continue
                    if strmatch("`v'","`ro'") {
                        if strpos("`rn'","*") {
                            local pre = substr("`ro'",1,strpos("`ro'","*")-1)
                            local suf = substr("`v'", strlen("`pre'")+1, .)
                            local newname = subinstr("`rn'","*","`suf'",1)
                        }
                        else local newname "`rn'"
                        if `: list newname in EXACTCALC' {
                            local calc = 1
                            if "`via'"=="" local via "renamed to `newname'"
                        }
                        foreach s of local STUBSCALC {
                            if strmatch("`newname'","`s'") {
                                local calc = 1
                                if "`via'"=="" local via "renamed to `newname' via pattern `s'"
                            }
                        }
                    }
                }
            }
            * class
            if "`h'"=="always-keep" local cls "always-keep"
            else if `u'==0 local cls "drop?"
            else if `calc' local cls "used-calc"
            else if `exact' local cls "structural-only"
            else {
                * wildcard/range only, never in a calculation: droppable if every pattern has
                * siblings and the variable is not a range endpoint
                if "`sib'"=="endpoint" | "`sib'"=="0" local cls "structural-only"
                else local cls "wildcard-only-droppable"
            }
            local ++iv
            local R_v`iv' "`v'"
            local R_u`iv' "`u'"
            local R_h`iv' "`h'"
            local R_c`iv' "`cls'"
            local R_k`iv' "`calc'"
            local R_via`iv' "`via'"
            local R_s`iv' "`sib'"
            local R_key`iv' "`key'"
            local R_pat`iv' "`matched'"
        }
        * a wildcard pattern whose matching variables are ALL droppable would become empty
        * (keep A2* would fail): keep the first match as a "pattern anchor"
        forvalues i = 1/`iv' {
            if "`R_c`i''"!="wildcard-only-droppable" continue
            foreach s of local R_pat`i' {
                local allgone = 1
                local first = 0
                forvalues j = 1/`iv' {
                    if strmatch("`R_v`j''","`s'") {
                        if `first'==0 local first = `j'
                        if "`R_c`j''"!="wildcard-only-droppable" local allgone = 0
                    }
                }
                if `allgone' & `first'>0 {
                    local R_c`first' "structural-only"
                    local R_h`first' "wildcard `s' (pattern anchor: only remaining match)"
                }
            }
        }
        forvalues i = 1/`iv' {
            if "`R_u`i''"=="0" local ++ndrop
            if "`R_c`i''"=="used-calc" local ++ncalc
            if "`R_c`i''"=="structural-only" local ++nstruct
            if "`R_c`i''"=="wildcard-only-droppable" local ++nwild
            local where ""
            if "`R_key`i''"!="" {
                frame `LOC': capture levelsof locs if key=="`R_key`i''", local(where) clean
            }
            file write `V' `""`base'",`R_v`i'',`R_u`i'',`R_h`i'',`R_c`i'',`R_k`i'',`R_via`i'',`R_s`i'',"`where'""' _n
        }
        file write `S' `""`base'",`nv',`=`nv'-`ndrop'',`ncalc',`nstruct',`nwild',`ndrop'"' _n
    }
    file close `V'
    file close `S'
    import delimited using "`vcsv'", varnames(1) clear stringcols(_all) bindquote(strict)
    gen decision = ""        // reviewer input: keep / drop
    export excel using "`outdir'/varusage_review.xlsx", sheet("variables") sheetreplace firstrow(variables)
    import delimited using "`scsv'", varnames(1) clear stringcols(_all) bindquote(strict)
    export excel using "`outdir'/varusage_review.xlsx", sheet("summary") sheetreplace firstrow(variables)
end

* ---- Mata helpers --------------------------------------------------------------------------
* Backtick, dollar and double quote are written as char(96), char(36), char(34) so that Stata
* never expands them while loading this file.
mata:

// comment-stripped copy of a do-file's lines ("" for comment/blank lines), tabs -> spaces
string colvector _fuv_clean(string colvector L)
{
    string colvector C
    string scalar s
    real scalar i, inblock, p, q
    C = J(rows(L), 1, "")
    inblock = 0
    for (i=1; i<=rows(L); i++) {
        s = subinstr(L[i], char(9), " ")
        if (inblock) {
            q = strpos(s, "*/")
            if (q == 0) continue
            s = substr(s, q+2, .)
            inblock = 0
        }
        while ((p = strpos(s, "/*")) > 0) {
            q = strpos(substr(s, p+2, .), "*/")
            if (q == 0) {
                s = substr(s, 1, p-1)
                inblock = 1
                break
            }
            s = substr(s, 1, p-1) + " " + substr(s, p+2+q+1, .)
        }
        s = ustrregexra(s, "//.*", "")
        if (ustrregexm(s, "^[ ]*\*")) continue
        C[i] = s
    }
    return(C)
}

// the qui/cap/noi/by ...: prefixes at the start of a line
string scalar _fuv_pfx()
{
    return("^[ ]*((qui[a-z]*|cap[a-z]*|noi[a-z]*)[ ]+|(by|bys|byso|bysor|bysort)[ ]+[^:]*:[ ]*)*")
}

// expand a literal numlist / forvalues range ("1/5", "2(2)10", "1 3 7"); ok = 0 if not literal
string rowvector _fuv_numlist(string scalar t, real scalar ok)
{
    string rowvector parts, out
    real scalar i, a, b, st, v
    ok = 1
    out = J(1, 0, "")
    if (strpos(t, char(96)) | strpos(t, char(36))) {
        ok = 0
        return(out)
    }
    parts = tokens(t)
    for (i=1; i<=cols(parts); i++) {
        if (ustrregexm(parts[i], "^(-?[0-9.]+)/(-?[0-9.]+)$")) {
            a = strtoreal(ustrregexs(1)); b = strtoreal(ustrregexs(2)); st = 1
        }
        else if (ustrregexm(parts[i], "^(-?[0-9.]+)[(](-?[0-9.]+)[)](-?[0-9.]+)$")) {
            a = strtoreal(ustrregexs(1)); st = strtoreal(ustrregexs(2)); b = strtoreal(ustrregexs(3))
        }
        else if (ustrregexm(parts[i], "^-?[0-9.]+$")) {
            a = strtoreal(parts[i]); b = a; st = 1
        }
        else {
            ok = 0
            return(out)
        }
        if (a>=. | b>=. | st>=. | st==0 | (b-a)/st > 5000) {
            ok = 0
            return(out)
        }
        for (v=a; (st>0 ? v<=b+1e-9 : v>=b-1e-9); v=v+st) out = out, strofreal(v, "%18.0g")
    }
    return(out)
}

// ---- macro values IN FORCE at each line (sequential read of the do-file) ---------------------
// CUR: macro -> the values it can hold at this line; UNK: macros whose value comes from the run
void _fuv_set(transmorphic CUR, transmorphic UNK, string scalar nm, string rowvector vals)
{
    if (cols(vals) == 0) {
        if (asarray_contains(CUR, nm)) asarray_remove(CUR, nm)
    }
    else asarray(CUR, nm, uniqrows(vals')')
    if (asarray_contains(UNK, nm)) asarray_remove(UNK, nm)
}

void _fuv_unk(transmorphic CUR, transmorphic UNK, string scalar nm)
{
    if (asarray_contains(CUR, nm)) asarray_remove(CUR, nm)
    asarray(UNK, nm, 1)
}

// 1 if the text still holds a macro reference
real scalar _fuv_hasref(string scalar s)
{
    return(strpos(s, char(96)) > 0 | strpos(s, char(36)) > 0)
}

// value of a literal expression: a quoted string, or arithmetic on numbers (`x' + 2 once `x'
// is filled); ok = 0 otherwise
string scalar _fuv_eval(string scalar e, real scalar ok)
{
    real scalar v
    ok = 1
    e = strtrim(e)
    if (ustrregexm(e, "^" + char(34) + "([^" + char(34) + "]*)" + char(34) + "$")) return(ustrregexs(1))
    if (!ustrregexm(e, "^[-+*/(). 0-9]+$") | !ustrregexm(e, "[0-9]")) {
        ok = 0
        return("")
    }
    if (_stata("scalar __fuv_e = " + e, 1)) {
        ok = 0
        return("")
    }
    v = st_numscalar("__fuv_e")
    if (v >= .) {
        ok = 0
        return("")
    }
    return(strofreal(v, "%18.0g"))
}

// the words of a list, each macro-built word filled with the values in force; ok = 0 if a
// word keeps a reference no value is known for
string rowvector _fuv_words(string scalar lst, transmorphic CUR, real scalar ok)
{
    string rowvector w, out
    string colvector e
    real scalar i, j
    ok = 1
    out = J(1, 0, "")
    w = tokens(subinstr(lst, char(34), " "))
    for (i=1; i<=cols(w); i++) {
        e = _fuv_expand(w[i], CUR)
        for (j=1; j<=rows(e); j++) {
            if (_fuv_hasref(e[j])) {
                ok = 0
                return(J(1, 0, ""))
            }
            out = out, e[j]
        }
    }
    return(out)
}

// a line that defines macros: update the values in force
void _fuv_defs(string scalar s, transmorphic CUR, transmorphic UNK)
{
    string scalar st, nm, inc, rest, BQ, Q, v
    string rowvector vals, w, base
    string colvector e
    real scalar ok, i
    BQ = char(96); Q = char(39)
    st = ustrregexra(s, _fuv_pfx(), "")
    // macros filled by options or commands whose values come from the run
    rest = st
    while (ustrregexm(rest, "local[(]([A-Za-z_][A-Za-z0-9_]*)[)]")) {
        nm = ustrregexs(1)
        rest = subinstr(rest, ustrregexs(0), " ", 1)
        _fuv_unk(CUR, UNK, nm)
    }
    if (ustrregexm(st, "^(gettoken|tempvar|tempname|tempfile|args|unab|tokenize)[ ]+(.*)$")) {
        w = tokens(ustrregexra(ustrregexs(2), "[^A-Za-z0-9_ ]", " "))
        for (i=1; i<=cols(w); i++) _fuv_unk(CUR, UNK, w[i])
        return
    }
    if (!ustrregexm(st, "^(local|loc)[ ]+(\+\+|--)?([A-Za-z_][A-Za-z0-9_]*)(.*)$")) return
    inc = ustrregexs(2)                    // take every group before the next regex call
    nm = ustrregexs(3)
    rest = ustrregexs(4)
    if (inc != "") {                       // local ++i
        if (asarray_contains(CUR, nm)) {
            vals = asarray(CUR, nm)
            if (cols(vals) == 1 & strtoreal(vals[1]) < .) {
                _fuv_set(CUR, UNK, nm, strofreal(strtoreal(vals[1]) + (inc == "++" ? 1 : -1), "%18.0g"))
                return
            }
        }
        _fuv_unk(CUR, UNK, nm)
        return
    }
    if (ustrregexm(rest, "^[ ]*=(.*)$")) {  // local y = 8 | local y = `x' + 2 | local s = "abc"
        e = _fuv_expand(strtrim(ustrregexs(1)), CUR)
        vals = J(1, 0, "")
        for (i=1; i<=rows(e); i++) {
            v = _fuv_eval(e[i], ok)
            if (!ok) {
                _fuv_unk(CUR, UNK, nm)
                return
            }
            vals = vals, tokens(v)
        }
        _fuv_set(CUR, UNK, nm, vals)
        return
    }
    if (ustrregexm(rest, "^[ ]*:")) {       // local n : word count ...
        _fuv_unk(CUR, UNK, nm)
        return
    }
    base = J(1, 0, "")
    if (strpos(rest, BQ + nm + Q)) {        // local L `L' a b  (self-append)
        if (asarray_contains(UNK, nm)) return
        if (asarray_contains(CUR, nm)) base = asarray(CUR, nm)
        rest = subinstr(rest, BQ + nm + Q, " ")
    }
    vals = _fuv_words(rest, CUR, ok)
    if (!ok) {
        _fuv_unk(CUR, UNK, nm)
        return
    }
    _fuv_set(CUR, UNK, nm, (base, vals))
}

// a loop header (forvalues / foreach / while ... {): macros the body redefines from the run or
// from themselves (a counter) are unknown from here on, until a line sets them again; the
// loop macro takes its literal list. Returns 1 if the line is a loop header.
real scalar _fuv_loop(string colvector C, real scalar i, transmorphic CUR, transmorphic UNK)
{
    string scalar st, nm, kind, lst, t, b
    string rowvector vals, w
    string colvector e
    real scalar isfv, isfe, ok, k, j, depth, q
    st = ustrregexra(C[i], _fuv_pfx(), "")
    isfv = ustrregexm(st, "^(forv|forva|forval|forvalu|forvalue|forvalues)[ ]+[A-Za-z_][A-Za-z0-9_]*[ ]*=")
    isfe = ustrregexm(st, "^foreach[ ]+[A-Za-z_][A-Za-z0-9_]*[ ]+(in|of[ ]+[a-z]+)[ ]")
    if (!isfv & !isfe & !ustrregexm(st, "^while[ (]")) return(0)
    // the body: up to the closing brace
    depth = 0
    j = i
    for (k=i; k<=rows(C); k++) {
        t = ustrregexra(C[k], char(36) + "[{][^}]*[}]", " ")
        depth = depth + (strlen(t) - strlen(subinstr(t, "{", ""))) - (strlen(t) - strlen(subinstr(t, "}", "")))
        j = k
        if (depth <= 0) break
    }
    for (k=i+1; k<j; k++) {
        b = ustrregexra(C[k], _fuv_pfx(), "")
        t = b
        while (ustrregexm(t, "local[(]([A-Za-z_][A-Za-z0-9_]*)[)]")) {
            nm = ustrregexs(1)
            t = subinstr(t, ustrregexs(0), " ", 1)
            _fuv_unk(CUR, UNK, nm)
        }
        if (ustrregexm(b, "^(local|loc)[ ]+(\+\+|--)[ ]*([A-Za-z_][A-Za-z0-9_]*)")) _fuv_unk(CUR, UNK, ustrregexs(3))
        else if (ustrregexm(b, "^(local|loc)[ ]+([A-Za-z_][A-Za-z0-9_]*)[ ]*[=:]")) _fuv_unk(CUR, UNK, ustrregexs(2))
    }
    if (isfv) {
        q = ustrregexm(st, "^[a-z]+[ ]+([A-Za-z_][A-Za-z0-9_]*)[ ]*=(.*)$")
        nm = ustrregexs(1)
        lst = strtrim(ustrregexra(ustrregexs(2), "[{].*$", ""))
        e = _fuv_expand(lst, CUR)
        ok = 0
        if (rows(e) == 1) vals = _fuv_numlist(e[1], ok)
        if (ok & cols(vals) > 0) _fuv_set(CUR, UNK, nm, vals)
        else _fuv_unk(CUR, UNK, nm)
    }
    else if (isfe) {
        q = ustrregexm(st, "^foreach[ ]+([A-Za-z_][A-Za-z0-9_]*)[ ]+(in|of[ ]+[a-z]+)[ ]+(.*)$")
        nm = ustrregexs(1)
        kind = ustrregexs(2)
        lst = ustrregexs(3)
        kind = ustrregexra(kind, "[ ]+", " ")
        lst = strtrim(ustrregexra(lst, "[{][ ]*$", ""))
        ok = 0
        vals = J(1, 0, "")
        if (kind == "in") vals = _fuv_words(lst, CUR, ok)
        else if (kind == "of numlist") {
            e = _fuv_expand(lst, CUR)
            if (rows(e) == 1) vals = _fuv_numlist(e[1], ok)
        }
        else if (kind == "of local") {
            if (asarray_contains(CUR, lst)) {
                vals = asarray(CUR, lst)
                ok = 1
            }
        }
        if (ok & cols(vals) > 0) _fuv_set(CUR, UNK, nm, vals)
        else _fuv_unk(CUR, UNK, nm)
    }
    return(1)
}

// gen/egen target of a line: returns (target, line with the target removed); ("", line) if none
string rowvector _fuv_gen(string scalar s)
{
    string scalar rest, pre, head, rest2, tgt, GEN, NAME
    rest = ustrregexra(s, _fuv_pfx(), "")
    pre = substr(s, 1, strlen(s) - strlen(rest))
    GEN = "^(g|ge|gen|gene|gener|genera|generat|generate|egen)[ ]+((byte|int|long|float|double|strL|str[0-9]+)[ ]+)?"
    NAME = "([A-Za-z_" + char(96) + "][A-Za-z0-9_" + char(96) + char(39) + "]*)"
    if (!ustrregexm(rest, GEN + NAME + "[ ]*=")) return(("", s))
    tgt = ustrregexs(4)
    if (!ustrregexm(rest, GEN)) return(("", s))
    head = ustrregexs(0)
    rest2 = substr(rest, strlen(head)+1, .)
    return((tgt, pre + head + " " + substr(rest2, strlen(tgt)+1, .)))
}

// remove every whole-token occurrence of a macro-built created name from a line
string scalar _fuv_dropcreated(string scalar s, transmorphic CREATED)
{
    string colvector K
    string scalar out, NB
    real scalar i
    K = asarray_keys(CREATED)
    if (rows(K) == 0) return(s)
    NB = "A-Za-z0-9_" + char(96) + char(39)
    out = s
    for (i=1; i<=rows(K); i++) {
        if (!strpos(out, K[i])) continue
        // created names hold only letters, digits, _, backtick and quote: no regex escaping needed
        out = ustrregexra(out, "(?<![" + NB + "])" + K[i] + "(?![" + NB + "])", " ")
    }
    return(out)
}

// one copy of the text per combination of the values in force of its macros (a macro with no
// known value is left as it is: the caller turns it into a wildcard)
string colvector _fuv_expand(string scalar s, transmorphic CUR)
{
    string scalar tmp, nm, REF
    string rowvector names, vals
    string colvector out, nw
    real scalar i, j, k, prod
    REF = char(96) + "([A-Za-z_][A-Za-z0-9_]*)" + char(39)
    names = J(1, 0, "")
    tmp = s
    while (ustrregexm(tmp, REF)) {
        nm = ustrregexs(1)
        tmp = subinstr(tmp, ustrregexs(0), " ", 1)
        if (asarray_contains(CUR, nm)) {
            if (!anyof(names, nm)) names = names, nm
        }
    }
    if (cols(names) == 0) return(s)
    prod = 1
    for (i=1; i<=cols(names); i++) prod = prod * cols(asarray(CUR, names[i]))
    if (prod > 2000) return(s)                         // too many combinations: keep the wildcard
    out = s
    for (i=1; i<=cols(names); i++) {
        vals = asarray(CUR, names[i])
        nw = J(0, 1, "")
        for (j=1; j<=rows(out); j++) {
            for (k=1; k<=cols(vals); k++) nw = nw \ subinstr(out[j], char(96) + names[i] + char(39), vals[k])
        }
        out = nw
    }
    return(out)
}

// per dataset: the wildcard patterns that match at least one of its variables (and how many),
// and the rename pairs whose old name or pattern does -> locals STUBS_D STUBN_D RENIDX RENN_<i>
void _fuv_relevant(real scalar nren)
{
    string colvector v
    string rowvector s
    string scalar outs, outn, idx
    real scalar i, n
    v = tokens(st_local("vars"))'
    s = tokens(st_local("STUBS"))
    outs = ""; outn = ""; idx = ""
    for (i=1; i<=cols(s); i++) {
        n = sum(strmatch(v, s[i]))
        if (n > 0) {
            outs = outs + " " + s[i]
            outn = outn + " " + strofreal(n)
        }
    }
    for (i=1; i<=nren; i++) {
        n = sum(strmatch(v, st_local("RO" + strofreal(i))))
        if (n > 0) {
            idx = idx + " " + strofreal(i)
            st_local("RENN_" + strofreal(i), strofreal(n))
        }
    }
    st_local("STUBS_D", outs); st_local("STUBN_D", outn); st_local("RENIDX", idx)
}

// tokenize every do-file in the list into frame default: tok where cmd | rng | renold rennew
void _fuv_tokens(string scalar listfile, string scalar root)
{
    string colvector files, L, C, allt, allw, allc, allr, allro, allrn, t, lines
    string scalar s, r, head, tail, cmd, prevcmd, w1, w2, ku, wh
    string rowvector ws, g
    real colvector m
    real scalar f, i, k, p, q, ci, cw, cc, cr, cro, crn, nobs, e, cont
    string matrix TW
    transmorphic CUR, UNK, CREATED
    files = cat(listfile)
    files = select(files, strtrim(files) :!= "")
    for (f=1; f<=rows(files); f++) {
        files[f] = strtrim(files[f])
        if (!ustrregexm(files[f], "^(/|[A-Za-z]:)")) files[f] = root + files[f]
    }
    allt = J(0,1,""); allw = J(0,1,""); allc = J(0,1,""); allr = J(0,1,""); allro = J(0,1,""); allrn = J(0,1,"")
    for (f=1; f<=rows(files); f++) {
        if (fileexists(files[f])==0) {
            printf("{txt}  find_used_variables: not found, skipped: %s\n", files[f])
            continue
        }
        L = cat(files[f])
        C = _fuv_clean(L)
        // ---- pass 1: the macro-built names this file creates ----
        CUR = asarray_create(); UNK = asarray_create(); CREATED = asarray_create()
        for (i=1; i<=rows(C); i++) {
            if (strtrim(C[i]) == "") continue
            g = _fuv_gen(C[i])
            if (strpos(g[1], char(96))) asarray(CREATED, g[1], 1)
        }
        // ---- pass 2: tokens, each line read with the macro values in force at that line ----
        cont = 0; prevcmd = ""
        for (i=1; i<=rows(C); i++) {
            s = C[i]
            if (strtrim(s) == "") {
                if (!strpos(L[i], "///")) cont = 0
                continue
            }
            wh = pathbasename(files[f]) + ":" + strofreal(i)
            g = _fuv_gen(s)
            s = _fuv_dropcreated(g[2], CREATED)
            // the command word of the line (after qui/cap/noi/by ...: prefixes)
            cmd = strlower(strtrim(s))
            cmd = ustrregexra(cmd, "^(qui[a-z]*[ ]+|cap[a-z]*[ ]+|noi[a-z]*[ ]+|by[a-z]*[ ]+[^:]*:[ ]*|xi[ ]*:[ ]*|bys[a-z]*[ ]+[^:]*:[ ]*)+", "")
            cmd = ustrregexra(cmd, "^([a-z_]+).*", "$1")
            if (cmd == "quietly" | cmd == "capture" | cmd == "noisily") cmd = ""
            // a continuation line (the line above ends in ///) belongs to the command above:
            // the variables of `keep a b ///` + `c d` are named by keep, not by a command "c"
            if (cont) cmd = prevcmd
            prevcmd = cmd
            cont = strpos(L[i], "///") > 0
            lines = _fuv_expand(s, CUR)
            for (e=1; e<=rows(lines); e++) {
                s = lines[e]
                // ---- remaining macro-built names -> wildcard; globals dropped; reshape stubs; renames ----
                s = ustrregexra(s, char(96) + "[^" + char(96) + "']*'", "*")
                s = ustrregexra(s, char(36) + "[{][^}]*[}]", " ")
                s = ustrregexra(s, char(36) + "[A-Za-z_][A-Za-z0-9_]*", " ")
                s = subinstr(s, "@", "*")
                if (ustrregexm(s, "^[ ]*(qui[a-z]*[ ]+|cap[a-z]*[ ]+|noi[a-z]*[ ]+)*reshape[ ]+(long|wide)[ ]")) {
                    k = strpos(s, ",")
                    if (k > 0) {
                        head = substr(s, 1, k-1)
                        tail = substr(s, k, .)
                    }
                    else {
                        head = s
                        tail = ""
                    }
                    head = ustrregexra(head, "(reshape|long|wide)", " ")
                    head = ustrregexra(head, "([A-Za-z0-9_*]+)", char(36) + "1*")
                    head = subinstr(head, "**", "*")
                    s = head + " " + tail
                }
                if (cmd == "merge" | cmd == "mmerge" | cmd == "joinby") {
                    p = strpos(strlower(s), "keepusing(")
                    if (p > 0) {
                        q = strpos(substr(s, p, .), ")")
                        if (q > 0) {
                            ku = substr(s, p+10, q-11)
                            s  = substr(s, 1, p-1) + " " + substr(s, p+q, .)
                            t = tokens(ustrregexra(ku, "[^A-Za-z0-9_*]", " "))'
                            if (rows(t) > 0) {
                                allt = allt \ t; allw = allw \ J(rows(t),1, wh); allc = allc \ J(rows(t),1,"keepusing")
                            }
                        }
                    }
                }
                if (cmd == "rename" | cmd == "ren") {
                    // every variable matching OLD is mapped to the name it carries afterwards,
                    // so a use of the new name counts as a use of the old one:
                    //   rename old new | rename OLD* NEW* (family) | rename OLD*pat newname
                    //   (a macro-built name renamed to a fixed name in a loop) | rename (a b) (c d)
                    if (ustrregexm(s, "ren[a-z]*[ ]*[(]([^)]*)[)][ ]*[(]([^)]*)[)]")) {
                        w1 = ustrregexs(1)
                        w2 = ustrregexs(2)
                        ws = tokens(ustrregexra(w1, "[^A-Za-z0-9_*]", " "))
                        g = tokens(ustrregexra(w2, "[^A-Za-z0-9_*]", " "))
                        if (cols(ws) == cols(g) & cols(ws) > 0) {
                            allro = allro \ ws'
                            allrn = allrn \ g'
                        }
                    }
                    else {
                        ws = tokens(ustrregexra(s, "[^A-Za-z0-9_*]", " "))
                        // rename * *_suffix renames whatever is in memory at that line, which a
                        // static read cannot know: it maps nothing (the re-run is the check)
                        if (cols(ws) >= 3) {
                            if (ws[2] != "*") {
                                allro = allro \ ws[2]
                                allrn = allrn \ ws[3]
                            }
                        }
                    }
                }
                if (cmd == "renpfix") {
                    s = ustrregexra(s, "renpfix", " ")
                    s = ustrregexra(s, "([A-Za-z0-9_]+)", char(36) + "1*")
                }
                // ---- ranges a-b ----
                r = ustrregexra(s, "[^A-Za-z0-9_*-]", " ")
                t = tokens(r)'
                if (rows(t) > 0) {
                    m = ustrregexm(t, "^[A-Za-z_][A-Za-z0-9_]*-[A-Za-z_][A-Za-z0-9_]*" + char(36))
                    if (sum(m) > 0) allr = allr \ select(t, m)
                }
                // ---- an if-condition computes with its variables, whatever the command
                //      (keep if age >= 6): its tokens are recorded under the command "if" ----
                q = 0
                if (ustrregexm(s, "(^|[ ,])if[ (]")) {
                    q = strpos(ustrregexra(s, "(^|[ ,])if[ (]", char(1)), char(1))
                }
                if (q > 0) {
                    r = ustrregexra(substr(s, q, .), "[^A-Za-z0-9_*]", " ")
                    r = ustrregexra(r, "^ *if ", " ")
                    s = substr(s, 1, q-1)
                    t = tokens(r)'
                    if (rows(t) > 0) {
                        allt = allt \ t; allw = allw \ J(rows(t),1, wh); allc = allc \ J(rows(t),1,"if")
                    }
                }
                // ---- tokens (and the literal pieces of wildcard tokens: x*100 is multiplication) ----
                s = ustrregexra(s, "[^A-Za-z0-9_*]", " ")
                t = tokens(s)'
                if (rows(t) > 0) {
                    allt = allt \ t; allw = allw \ J(rows(t),1, wh); allc = allc \ J(rows(t),1,cmd)
                    r = subinstr(invtokens(t'), "*", " ")
                    t = tokens(r)'
                    if (rows(t) > 0) {
                        allt = allt \ t; allw = allw \ J(rows(t),1, wh); allc = allc \ J(rows(t),1,cmd)
                    }
                }
            }
            // the line read, update the macro values in force for the lines below
            if (!_fuv_loop(C, i, CUR, UNK)) _fuv_defs(C[i], CUR, UNK)
        }
    }
    if (rows(allt) == 0) {
        allt = ""; allw = ""; allc = ""
    }
    TW = uniqrows((allt, allw, allc))
    allr = uniqrows(allr)
    stata("clear")
    nobs = max((rows(TW), rows(allr), rows(allro), 1))
    st_addobs(nobs)
    ci = st_addvar("str244", "tok"); cw = st_addvar("str244", "where"); cc = st_addvar("str32", "cmd")
    cr = st_addvar("str244", "rng"); cro = st_addvar("str244", "renold"); crn = st_addvar("str244", "rennew")
    for (i=1; i<=rows(TW); i++) {
        st_sstore(i, ci, TW[i,1]); st_sstore(i, cw, TW[i,2]); st_sstore(i, cc, TW[i,3])
    }
    for (i=1; i<=rows(allr); i++) st_sstore(i, cr, allr[i])
    for (i=1; i<=rows(allro); i++) {
        st_sstore(i, cro, allro[i]); st_sstore(i, crn, allrn[i])
    }
}
end
