*! pii_classify -- classify every variable of the dataset in memory for direct-PII risk.
*! Writes/appends one CSV row per variable. Replaces pii_scan: same keyword idea, but
*! with the typing rules agreed for this project, so the output is a short shortlist
*! (category likely_pii) plus everything else (other_variables), identifiers kept apart.
*
*  syntax: pii_classify, out(<csv path>) dataset(<label>) [idkeys(<glob list>)] [append]
*
*  category  : identifier | likely_pii | other
*  RULES (applied in this order)
*   1. identifier key (name matches idkeys())           -> identifier   (reported in its own tab)
*   2. direct-id term in name or label                  -> likely_pii   (name, dob/birth, address,
*      phone/contact/mobile, national id / cnic, gps/latitude/longitude/coord, email, caste)
*      or a lat/lon PAIR of adjacent variables          -> likely_pii
*      or value labels that look like free text (many, long labels) / contain a direct term
*   3. byte variables                                   -> other
*   4. numeric variables (int/long/float/double)        -> other
*   5. strings that are numbers in disguise (>=95% of non-blank values parse as numbers) -> other
*   6. strings that are time slots (>=80% look like hh:mm)                              -> other
*   7. strings whose label says count/amount/score ("how many", "number of", "amount",
*      "how much", "score", "rupee", "rs.", "price", "cost", "fee", "age", "years") -> other
*   8. remaining strings WITH content (not empty / placeholder / missing-code only)   -> likely_pii
*      ("other (specify)" fields are just strings: flagged only if they carry content)
*   9. remaining strings without content                                             -> other
*  keyword_hit : pii_scan's broad keyword list matched in name/label (informational; the
*                other_variables tab is sorted so these come first)
program define pii_classify
    version 16
    syntax , OUT(string) DATAset(string) [IDKeys(string) APPend]
    local DIRECT  "name dob birth address phone contact mobile cnic national email caste gps latitude longitude coord"
    local KEYWORD "address bday beneficiary birth block cell census city compound coord district email fax gender gps landline latitude location longitude municipality name network panchayat parish phone precinct sex social street subcountry territory village zip child community country daughter father husband house mother spouse wife url son dob loc"
    local COUNT   "how many|number of|no\. of|amount|how much|score|rupee|rs\.|price|cost|fee|age\b|years|hours|minutes|kg\b|cm\b|percent|weight|height|total|index"
    local PLACEH  "PII|REDACT|PUBLIC VERSION|ANONYM|DEIDENT|DE-IDENT|REMOVED|WITHHELD|MASKED|CONFIDENTIAL|SUPPRESS|NOT AVAILABLE|NOT RELEASED"
    tempname H
    if "`append'"=="" {
        file open `H' using "`out'", write replace
        file write `H' "dataset,variable,type,storage_class,label,value_label,n_nonmiss,n_distinct,uniq_ratio,is_identifier_key,direct_id_term,latlon_pair,vlabel_flag,keyword_hit,other_specify,numeric_in_disguise,time_like,count_label,redaction_status,sample1,sample2,category,reason" _n
    }
    else file open `H' using "`out'", write append
    quietly count
    local N = r(N)
    quietly ds
    local allvars `r(varlist)'
    * ---- lat/lon pair detection: a lat-named and a lon-named variable that are adjacent ----
    local prev ""
    local pairvars ""
    foreach v of local allvars {
        local lv = strlower("`v'")
        local isl = regexm("`lv'","(^|_)(lat|latitude)(_|$)")
        local iso = regexm("`lv'","(^|_)(lon|long|longitude)(_|$)")
        if "`prev'"!="" {
            local lp = strlower("`prev'")
            local pl = regexm("`lp'","(^|_)(lat|latitude)(_|$)")
            local po = regexm("`lp'","(^|_)(lon|long|longitude)(_|$)")
            if (`isl' & `po') | (`iso' & `pl') local pairvars "`pairvars' `prev' `v'"
        }
        local prev "`v'"
    }
    foreach v of local allvars {
        local ty : type `v'
        local isstr = substr("`ty'",1,3)=="str"
        local sc = cond(`isstr',"string",cond("`ty'"=="byte","byte",cond("`ty'"=="int","int",cond("`ty'"=="long","long",cond("`ty'"=="float","float","double")))))
        local lab : variable label `v'
        mata: st_local("lab", subinstr(subinstr(subinstr(subinstr(st_local("lab"), char(96), "'"), char(34), "'"), ",", ";"), char(39), uchar(8217)))
        local vl : value label `v'
        local lv = strlower("`v'")
        local ll = strlower(`"`lab'"')
        * 1. identifier key
        local idkey = 0
        foreach k of local idkeys {
            if strmatch("`lv'", strlower("`k'")) local idkey = 1
        }
        * 2. direct-id term (whole-word-ish to avoid "nic" in "clinic", "age" in "village")
        local dterm ""
        foreach t of local DIRECT {
            if "`dterm'"=="" {
                if regexm("`lv'","(^|_)`t'") | regexm("`ll'","(^|[^a-z])`t'") local dterm "`t'"
            }
        }
        if "`dterm'"=="national" & !regexm("`ll'","national id|national identity|nic") local dterm ""
        local latlon = `: list v in pairvars'
        * value-label flag: many long labels (coded free text) or a direct term inside a
        * label. Only for variables with at most 300 distinct values (the text of a coded
        * free-text field); label text is sanitised through Mata before it touches a macro.
        local vflag ""
        if "`vl'"!="" {
            capture label list `vl'
            if _rc==0 {
                capture {
                    quietly tab `v' if !missing(`v')
                    local ndv = r(r)
                }
                if _rc==0 & `ndv'<=300 {
                    quietly levelsof `v', local(vals)
                    local lens = 0
                    local cnt = 0
                    local vtext ""
                    foreach x of local vals {
                        local t : label `vl' `x'
                        mata: st_local("t", subinstr(subinstr(subinstr(st_local("t"), char(96), "'"), char(34), "'"), char(39), uchar(8217)))
                        local lens = `lens' + strlen(`"`t'"')
                        local ++cnt
                        local vtext `"`vtext' `=strlower(`"`t'"')'"'
                    }
                    if `cnt'>0 {
                        local avg = `lens'/`cnt'
                        if `cnt'>=30 & `avg'>12 local vflag "many long value labels (`cnt')"
                        foreach t in name address phone cnic email caste {
                            if "`vflag'"=="" & regexm(`"`vtext'"',"(^|[^a-z])`t'") local vflag "value labels mention `t'"
                        }
                    }
                }
            }
        }
        * keyword (pii_scan-style, informational)
        local kw ""
        foreach t of local KEYWORD {
            if "`kw'"=="" & (strpos("`lv'","`t'") | regexm("`ll'","(^|[^a-z])`t'")) local kw "`t'"
        }
        local oth = (regexm("`lv'","oth|spec") | regexm("`ll'","other|specify")) & !regexm("`ll'","mother|brother|another")
        local cnt_lab = regexm("`ll'","`COUNT'")
        * ---- counts and content ----
        preserve
            quietly keep `v'
            if `isstr' quietly drop if `v'==""
            else quietly drop if missing(`v')
            quietly count
            local nnm = r(N)
            local nd = 0
            local s1 ""
            local s2 ""
            local numdis = 0
            local timelike = 0
            if `nnm'>0 {
                if `isstr' {
                    quietly count if regexm(trim(`v'),"^-?[0-9]+([.][0-9]+)?$")
                    local numdis = r(N)/`nnm' >= 0.95
                    quietly count if regexm(trim(`v'),"^[0-9]{1,2}[:.][0-9]{2}( ?[AaPp][Mm])?$")
                    local timelike = r(N)/`nnm' >= 0.80
                }
                quietly duplicates drop
                quietly count
                local nd = r(N)
                if `isstr' {
                    local s1 = substr(`v'[1],1,30)
                    if `nd'>1 local s2 = substr(`v'[2],1,30)
                }
                else {
                    local s1 = string(`v'[1])
                    if `nd'>1 local s2 = string(`v'[2])
                }
                mata: st_local("s1", subinstr(subinstr(subinstr(subinstr(st_local("s1"), char(96), "'"), char(34), "'"), ",", ";"), char(39), uchar(8217)))
                mata: st_local("s2", subinstr(subinstr(subinstr(subinstr(st_local("s2"), char(96), "'"), char(34), "'"), ",", ";"), char(39), uchar(8217)))
            }
        restore
        local ratio = cond(`nnm'>0, round(`nd'/`nnm',0.001), 0)
        * redaction status (strings)
        local red "n/a"
        if `isstr' {
            if `nnm'==0 local red "empty (all blank)"
            else if `nd'==1 & regexm(upper(trim(`"`s1'"')),"(`PLACEH')") local red "redacted (placeholder)"
            else if `nd'==1 & regexm(trim(`"`s1'"'),"^-?9{1,3}$|^[.;,-]+$") local red "single value (missing code)"
            else if `nd'==1 local red "single value"
            else local red "content"
        }
        else if `nnm'==0 local red "empty (all missing)"
        * ---- category ----
        local cat ""
        local why ""
        if `idkey' {
            local cat "identifier"
            local why "linkage key"
        }
        else if "`dterm'"!="" {
            local cat "likely_pii"
            local why "direct-id term '`dterm'' in name/label"
        }
        else if `latlon' {
            local cat "likely_pii"
            local why "lat/lon pair"
        }
        else if "`vflag'"!="" {
            local cat "likely_pii"
            local why "`vflag'"
        }
        else if !`isstr' {
            local cat "other"
            local why = cond("`sc'"=="byte","byte","numeric")
        }
        else if `numdis' {
            local cat "other"
            local why "string holding numbers"
        }
        else if `timelike' {
            local cat "other"
            local why "time slot"
        }
        else if `cnt_lab' {
            local cat "other"
            local why "count/amount/score label"
        }
        else if "`red'"=="content" | "`red'"=="single value" {
            local cat "likely_pii"
            local why = cond(`oth',"free text: other (specify)","free text")
        }
        else {
            local cat "other"
            local why "string without content (`red')"
        }
        file write `H' `""`dataset'","`v'","`ty'","`sc'","`lab'","`vl'",`nnm',`nd',`ratio',`idkey',"`dterm'",`latlon',"`vflag'","`kw'",`oth',`numdis',`timelike',`cnt_lab',"`red'","`s1'","`s2'","`cat'","`why'""' _n
    }
    file close `H'
end
