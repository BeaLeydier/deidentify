*! _surf_vlabel -- Mata helper for 04b: for value label `s', set locals vlflag, vlval#, vltxt#, vlwhy#
program define _surf_vlabel
    version 16
    mata: _surf_vlabel_m("`1'")
end
mata:
void _surf_vlabel_m(string scalar lbl)
{
    real colvector vals
    string colvector txt
    real scalar i, n
    string scalar t, why
    st_vlload(lbl, vals, txt)
    n = 0
    for (i=1; i<=rows(vals); i++) {
        t = strlower(txt[i]); why = ""
        if (ustrregexm(t, "(^|[^a-z])(name|dob|birth|address|phone|contact|mobile|cnic|national id|email|caste|gps|latitude|longitude)")) why = "direct-identifier term"
        else if (strlen(t) > 40) why = "long free text (>40 chars)"
        if (why != "") {
            n++
            st_local("vlval" + strofreal(n), strofreal(vals[i]))
            st_local("vltxt" + strofreal(n), subinstr(subinstr(subinstr(subinstr(substr(txt[i],1,120), char(96), "'"), char(34), "'"), ",", ";"), char(39), uchar(8217)))
            st_local("vlwhy" + strofreal(n), why)
        }
    }
    st_local("vlflag", strofreal(n))
}
end
