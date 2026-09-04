*! find_used_variables -- keep-list builder for the "minimize variables" step (v3).
* Tokenizes every dofile (comments removed: // ..., * ... lines, /* ... */ blocks across
* lines), then per dataset marks which variables the code uses and HOW:
*   exact           the name appears as a token
*   wildcard <pat>  the name matches a glob pattern in the code (prefix hf*, suffix *_va,
*                   infix x*_q1, a macro-built name hf`i'_s5q`j' -> hf*_s5q*, a reshape stub)
*   range a-b       the name lies inside an a-b variable range
*   always-keep     matches alwayskeep()
* and, for the reviewer, in which command CONTEXT each reference occurs:
*   calc_context    the variable (or the name it acquires through a wildcard rename A* B*)
*                   is referenced by a command that computes with it (gen, replace, egen,
*                   regressions, summarize, collapse, ...), as opposed to a purely structural
*                   command (keep, drop, order, rename, merge/keepusing, sort, reshape, ...)
*   n_pattern_siblings  for a wildcard/range match: how many OTHER variables of the same
*                   dataset the same pattern also matches (0 = this variable is the only one,
*                   dropping it would break the command); for a range: "endpoint" if the
*                   variable is one of the two range endpoints
*   class           used-calc | structural-only | wildcard-only-droppable | always-keep | drop?
*       structural-only          : referenced by name, but only by structural commands
*       wildcard-only-droppable  : reached only through wildcards/ranges that have siblings,
*                                  never in a calculation (also after renames) -> can be
*                                  dropped without breaking the code (verify by re-running)
* Writes ONE review workbook (varusage_review.xlsx: sheets `summary`, `variables` with an
* empty `decision` input column). Conservative and a PROPOSAL -- review, prove by re-running.
*     find_used_variables, dofiles("code/a.do code/b.do") ///
*         datasets("orig/x.dta orig/y.dta") outdir(".") alwayskeep("personid hhid *_pubrep")
program define find_used_variables
    syntax , DOfiles(string) DATAsets(string) [OUTdir(string) ALWAYSkeep(string)]
    if "`outdir'"=="" local outdir "."
    set more off
    * structural commands: they select, arrange or label variables but do not compute with
    * them. Everything else -- reshape (consumes the stub family), merge/sort keys, duplicates,
    * collapse, egen, regressions, ... -- counts as a calculation context.
    local STRUCT "keep drop order rename ren keepusing format label compress describe des ds unab save use saveold append tostring destring recast note notes char"

    * ---- tokenize (Mata) -> frame TOK: tok where cmd iswild ; frame RNG: rng ; frame REN: oldpat newpat
    mata: _fuv_tokens("`dofiles'")
    tempname TOK
    frame copy default `TOK'
    frame `TOK' {
        gen byte iswild = strpos(tok,"*")>0
        gen str244 lit  = ustrregexra(tok, "[^A-Za-z0-9]", "")
        gen byte simpleprefix = ustrregexm(tok, "^[A-Za-z0-9_]+\*$")
        gen byte usable = tok!="" & (!iswild | strlen(lit)>=2 | simpleprefix)
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
    * rename A* B* pairs (both wildcards): oldpat newpat
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

    foreach d of local datasets {
        use "`d'", clear
        quietly ds
        local vars `r(varlist)'
        local nv : word count `vars'
        local base = ustrregexra("`d'", "^.*/", "")
        local base = ustrregexra("`base'", "\.dta$", "")
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
        local INRANGE = strlower("`INRANGE'")
        local ENDPTS  = strlower("`ENDPTS'")
        * number of variables in this dataset matching each wildcard pattern
        local LVARS = strlower("`vars'")
        local iv = 0
        foreach v of local vars {
            local lv = strlower("`v'")
            local u = 0
            local h = "drop?"
            local key ""
            local calc = 0
            local via = ""
            local sib = ""
            foreach k of local alwayskeep {
                if strmatch("`lv'", strlower("`k'")) local u = 1
            }
            if `u'==1 local h = "always-keep"
            * exact reference
            local exact = `: list lv in EXACT'
            if `exact' {
                if `u'==0 local h = "exact"
                local u = 1
                if "`key'"=="" local key "`lv'"
                if `: list lv in EXACTCALC' {
                    local calc = 1
                    local via "exact"
                }
            }
            * range
            local inrng = `: list lv in INRANGE'
            if `inrng' {
                if "`h'"=="drop?" local h = "range a-b"
                local u = 1
                if `: list lv in ENDPTS' local sib "endpoint"
                else if "`sib'"=="" local sib "range-member"
            }
            * wildcard patterns
            local matched ""
            foreach s of local STUBS {
                if strmatch("`lv'","`s'") {
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
                    foreach w of local LVARS {
                        if "`w'"!="`lv'" & strmatch("`w'","`s'") local ++n
                    }
                    if "`sib'"=="" | "`sib'"=="range-member" local sib "`n'"
                    else if "`sib'"!="endpoint" local sib = string(min(real("`sib'"), `n'))
                }
            }
            * names acquired through wildcard renames: rename OLD* NEW* -> NEWprefix + suffix
            if `u'==1 & `calc'==0 {
                forvalues i = 1/`NREN' {
                    local ro "`RO`i''"
                    local rn "`RN`i''"
                    if strmatch("`lv'","`ro'") {
                        if strpos("`rn'","*") {
                            local pre = substr("`ro'",1,strpos("`ro'","*")-1)
                            local suf = substr("`lv'", strlen("`pre'")+1, .)
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
                    if strmatch(strlower("`R_v`j''"),"`s'") {
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
            file write `V' `"`base',`R_v`i'',`R_u`i'',`R_h`i'',`R_c`i'',`R_k`i'',`R_via`i'',`R_s`i'',"`where'""' _n
        }
        file write `S' "`base',`nv',`=`nv'-`ndrop'',`ncalc',`nstruct',`nwild',`ndrop'" _n
    }
    file close `V'
    file close `S'

    import delimited using "`vcsv'", varnames(1) clear stringcols(_all)
    gen decision = ""        // reviewer input: keep / drop
    export excel using "`outdir'/varusage_review.xlsx", sheet("variables") sheetreplace firstrow(variables)
    import delimited using "`scsv'", varnames(1) clear stringcols(_all)
    export excel using "`outdir'/varusage_review.xlsx", sheet("summary") sheetreplace firstrow(variables)
end

* ---- Mata helper: tokenize dofiles (comments removed) into frame `default':
*      tok where cmd | rng | renold rennew
mata:
void _fuv_tokens(string scalar dofiles)
{
    string colvector files, L, allt, allw, allc, allr, allro, allrn, t
    string scalar s, r, head, tail, cmd, w1, w2, ku
    string rowvector ws
    real colvector m
    real scalar f, i, k, inblock, p, q, ci, cw, cc, cr, cro, crn, nobs
    string matrix TW
    files = tokens(dofiles)'
    allt = J(0,1,""); allw = J(0,1,""); allc = J(0,1,""); allr = J(0,1,""); allro = J(0,1,""); allrn = J(0,1,"")
    for (f=1; f<=rows(files); f++) {
        if (fileexists(files[f])==0) continue
        L = cat(files[f])
        inblock = 0
        for (i=1; i<=rows(L); i++) {
            s = subinstr(L[i], char(9), " ")          // tabs -> spaces (strtrim only strips spaces)
            // ---- comments: /* ... */ blocks (may span lines), // to end of line, * lines ----
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
            if (ustrregexm(s, "^[ \t]*\*")) continue          // a * comment line
            if (strtrim(s) == "") continue
            // ---- the command word of the line (after qui/cap/noi/by ...: prefixes) ----
            cmd = strlower(strtrim(s))
            cmd = ustrregexra(cmd, "^(qui[a-z]*[ \t]+|cap[a-z]*[ \t]+|noi[a-z]*[ \t]+|by[a-z]*[ \t]+[^:]*:[ \t]*|xi[ \t]*:[ \t]*|bys[a-z]*[ \t]+[^:]*:[ \t]*)+", "")
            cmd = ustrregexra(cmd, "^([a-z_]+).*", "$1")
            if (cmd == "quietly" | cmd == "capture" | cmd == "noisily") cmd = ""
            // ---- macro-built names -> wildcard; globals dropped; reshape stubs; renames ----
            s = ustrregexra(s, char(96) + "[^" + char(96) + "']*'", "*")
            s = ustrregexra(s, char(36) + "[{][^}]*[}]", " ")
            s = ustrregexra(s, char(36) + "[A-Za-z_][A-Za-z0-9_]*", " ")
            s = subinstr(s, "@", "*")
            if (ustrregexm(s, "^[ \t]*(qui[a-z]*[ \t]+|cap[a-z]*[ \t]+|noi[a-z]*[ \t]+)*reshape[ \t]+(long|wide)[ \t]")) {
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
                            allt = allt \ t; allw = allw \ J(rows(t),1, pathbasename(files[f]) + ":" + strofreal(i)); allc = allc \ J(rows(t),1,"keepusing")
                        }
                    }
                }
            }
            if (cmd == "rename" | cmd == "ren") {
                ws = tokens(ustrregexra(s, "[^A-Za-z0-9_*]", " "))
                if (cols(ws) >= 3) {
                    w1 = strlower(ws[2]); w2 = strlower(ws[3])
                    // rename OLD* NEW* (family rename) or rename OLD*pattern newname (a macro-built
                    // name renamed to a fixed name inside a loop): every variable matching OLD is
                    // mapped to the name it carries afterwards
                    if (strpos(w1,"*")) {
                        allro = allro \ w1
                        allrn = allrn \ w2
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
            // ---- tokens (and the literal pieces of wildcard tokens: x*100 is multiplication) ----
            s = ustrregexra(s, "[^A-Za-z0-9_*]", " ")
            t = tokens(s)'
            if (rows(t) > 0) {
                allt = allt \ t; allw = allw \ J(rows(t),1, pathbasename(files[f]) + ":" + strofreal(i)); allc = allc \ J(rows(t),1,cmd)
                r = subinstr(invtokens(t'), "*", " ")
                t = tokens(r)'
                if (rows(t) > 0) {
                    allt = allt \ t; allw = allw \ J(rows(t),1, pathbasename(files[f]) + ":" + strofreal(i)); allc = allc \ J(rows(t),1,cmd)
                }
            }
        }
    }
    TW = uniqrows((strlower(allt), allw, allc))
    allr = uniqrows(strlower(allr))
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
