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
* Macro-built names (s`i'_q`j'):
*   - filled in with the macro's values when the do-file spells them out: forvalues i = 1/12,
*     foreach i in a b c, foreach i of numlist 1/5, foreach i of local L, local L a b c
*     (several definitions of one name in a file are pooled);
*   - otherwise (values from the data: r(), levelsof, `: word', varlists, other files ...)
*     turned into a wildcard (s`i'_q`j' -> s*_q*).
* Two constructs prove nothing and are ignored: a wildcard without a letter in its literal
* part ("**12"), and `rename * *_suffix`, which renames whatever happens to be in memory.
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
            local exact = `: list v in EXACT'
            if `exact' {
                if `u'==0 local h = "exact"
                local u = 1
                if "`key'"=="" local key "`v'"
                if `: list v in EXACTCALC' {
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
            foreach s of local STUBS {
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
                    local n = 0
                    foreach w of local vars {
                        if "`w'"!="`v'" & strmatch("`w'","`s'") local ++n
                    }
                    if "`sib'"=="" | "`sib'"=="range-member" local sib "`n'"
                    else if "`sib'"!="endpoint" local sib = string(min(real("`sib'"), `n'))
                }
            }
            * names acquired through renames: rename old new, rename OLD* NEW* -> NEWprefix + suffix
            if `u'==1 & `calc'==0 {
                forvalues i = 1/`NREN' {
                    local ro "`RO`i''"
                    local rn "`RN`i''"
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

// record a literal value list for macro nm (pooled with earlier definitions)
void _fuv_addvals(transmorphic MV, string scalar nm, string rowvector vals)
{
    if (asarray_contains(MV, nm)) asarray(MV, nm, (asarray(MV, nm), vals))
    else asarray(MV, nm, vals)
}

// pass 1 on one line: macro definitions with literal values (MV) and non-literal ones (BAD)
void _fuv_defs(string scalar s, transmorphic MV, transmorphic BAD)
{
    string scalar st, nm, kind, lst, rest, BQ, Q
    string rowvector vals, w
    real scalar ok, i
    BQ = char(96); Q = char(39)
    st = ustrregexra(s, _fuv_pfx(), "")
    // macros filled by options or commands whose values come from the run
    rest = st
    while (ustrregexm(rest, "local[(]([A-Za-z_][A-Za-z0-9_]*)[)]")) {
        asarray(BAD, ustrregexs(1), 1)
        rest = subinstr(rest, ustrregexs(0), " ", 1)
    }
    if (ustrregexm(st, "^(gettoken|tempvar|tempname|tempfile|args|unab|tokenize)[ ]+(.*)$")) {
        w = tokens(ustrregexra(ustrregexs(2), "[^A-Za-z0-9_ ]", " "))
        for (i=1; i<=cols(w); i++) asarray(BAD, w[i], 1)
        return
    }
    if (ustrregexm(st, "^(forv|forva|forval|forvalu|forvalue|forvalues)[ ]+([A-Za-z_][A-Za-z0-9_]*)[ ]*=(.*)$")) {
        nm = ustrregexs(2)
        lst = strtrim(ustrregexra(ustrregexs(3), "[{][ ]*$", ""))
        vals = _fuv_numlist(lst, ok)
        if (ok & cols(vals)>0) _fuv_addvals(MV, nm, vals)
        else asarray(BAD, nm, 1)
        return
    }
    if (ustrregexm(st, "^foreach[ ]+([A-Za-z_][A-Za-z0-9_]*)[ ]+(in|of[ ]+[a-z]+)[ ]+(.*)$")) {
        nm = ustrregexs(1)                 // take every group before the next regex call
        kind = ustrregexs(2)
        lst = ustrregexs(3)
        kind = ustrregexra(kind, "[ ]+", " ")
        lst = strtrim(ustrregexra(lst, "[{][ ]*$", ""))
        if (kind == "in" & !strpos(lst, BQ) & !strpos(lst, char(36))) {
            vals = tokens(subinstr(lst, char(34), " "))
            if (cols(vals)>0) _fuv_addvals(MV, nm, vals)
            else asarray(BAD, nm, 1)
        }
        else if (kind == "of numlist") {
            vals = _fuv_numlist(lst, ok)
            if (ok & cols(vals)>0) _fuv_addvals(MV, nm, vals)
            else asarray(BAD, nm, 1)
        }
        else if (kind == "of local" & asarray_contains(MV, lst) & !asarray_contains(BAD, lst)) {
            _fuv_addvals(MV, nm, asarray(MV, lst))
        }
        else asarray(BAD, nm, 1)
        return
    }
    if (ustrregexm(st, "^(local|loc)[ ]+(\+\+|--)?([A-Za-z_][A-Za-z0-9_]*)(.*)$")) {
        nm = ustrregexs(3)
        rest = ustrregexs(4)
        if (ustrregexs(2) != "" | ustrregexm(rest, "^[ ]*[=:]")) {
            asarray(BAD, nm, 1)
            return
        }
        rest = subinstr(rest, BQ + nm + Q, " ")          // local L `L' a b  (self-append)
        if (strpos(rest, BQ) | strpos(rest, char(36))) {
            asarray(BAD, nm, 1)
            return
        }
        vals = tokens(subinstr(rest, char(34), " "))
        if (cols(vals)>0) _fuv_addvals(MV, nm, vals)
        else asarray(BAD, nm, 1)
    }
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

// pass 2 on one line: one copy per combination of the literal values of its macros
string colvector _fuv_expand(string scalar s, transmorphic MV, transmorphic BAD)
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
        if (asarray_contains(MV, nm) & !asarray_contains(BAD, nm)) {
            if (!anyof(names, nm)) names = names, nm
        }
        tmp = subinstr(tmp, ustrregexs(0), " ", 1)
    }
    if (cols(names) == 0) return(s)
    prod = 1
    for (i=1; i<=cols(names); i++) prod = prod * cols(asarray(MV, names[i]))
    if (prod > 2000) return(s)                         // too many combinations: keep the wildcard
    out = s
    for (i=1; i<=cols(names); i++) {
        vals = asarray(MV, names[i])
        nw = J(0, 1, "")
        for (j=1; j<=rows(out); j++) {
            for (k=1; k<=cols(vals); k++) nw = nw \ subinstr(out[j], char(96) + names[i] + char(39), vals[k])
        }
        out = nw
    }
    return(out)
}

// tokenize every do-file in the list into frame default: tok where cmd | rng | renold rennew
void _fuv_tokens(string scalar listfile, string scalar root)
{
    string colvector files, L, C, allt, allw, allc, allr, allro, allrn, t, lines
    string scalar s, r, head, tail, cmd, w1, w2, ku, wh
    string rowvector ws, g
    real colvector m
    real scalar f, i, k, p, q, ci, cw, cc, cr, cro, crn, nobs, e
    string matrix TW
    transmorphic MV, BAD, CREATED
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
        // ---- pass 1: literal macro values, and the macro-built names this file creates ----
        MV = asarray_create(); BAD = asarray_create(); CREATED = asarray_create()
        for (i=1; i<=rows(C); i++) {
            if (strtrim(C[i]) == "") continue
            _fuv_defs(C[i], MV, BAD)
            g = _fuv_gen(C[i])
            if (strpos(g[1], char(96))) asarray(CREATED, g[1], 1)
        }
        // ---- pass 2: tokens ----
        for (i=1; i<=rows(C); i++) {
            s = C[i]
            if (strtrim(s) == "") continue
            wh = pathbasename(files[f]) + ":" + strofreal(i)
            g = _fuv_gen(s)
            s = _fuv_dropcreated(g[2], CREATED)
            // the command word of the line (after qui/cap/noi/by ...: prefixes)
            cmd = strlower(strtrim(s))
            cmd = ustrregexra(cmd, "^(qui[a-z]*[ ]+|cap[a-z]*[ ]+|noi[a-z]*[ ]+|by[a-z]*[ ]+[^:]*:[ ]*|xi[ ]*:[ ]*|bys[a-z]*[ ]+[^:]*:[ ]*)+", "")
            cmd = ustrregexra(cmd, "^([a-z_]+).*", "$1")
            if (cmd == "quietly" | cmd == "capture" | cmd == "noisily") cmd = ""
            lines = _fuv_expand(s, MV, BAD)
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
