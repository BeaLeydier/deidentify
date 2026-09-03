# Editing a dofile to apply ID renames (Stata)

For rewriting the analysis dofile to use the scrambled `_pubrep` ids, and for the
verify whole-dataset diff. These are mechanical text-transformation techniques. 
If a run halts on a Stata version issue, the
modernization catalogue lives in the **compare-code-results** skill.

## Read the dofile verbatim (do not let Stata expand it)

Reading source lines with `file read` into a local and re-referencing them in a
quoted context makes Stata **expand `$globals` and `` `locals` `` inside the code
text** — `use "$projectdir/x"` silently becomes `use "/x"`. Use **Mata `cat()`**,
which returns lines completely literally:

```stata
clear
local inpath "pkg/analysis.do"
mata:
    L = cat(st_local("inpath"))
    n = rows(L)
    st_addobs(n)
    ci = st_addvar("str2045", "code")     // postfile forbids strL; str2045 is plenty
    for (i = 1; i <= n; i++) st_sstore(i, ci, L[i])
end
```
Now `code` holds every line verbatim; transform row by row.

## Match ID names on word boundaries (treat `_` as a word char)

So `villageid` does not match inside `hh_villageid`, and `clusterid` not inside
`resid`/`consider`:

```stata
local pat "(?<![A-Za-z0-9_])" + "`v'" + "(?![A-Za-z0-9_])"
* detect:  ustrregexm(code, "`pat'")
* replace: ustrregexra(code, "`pat'", "`v'_pubrep")   // zero-width lookarounds preserved
```
Flag both ID *variable* names and hardcoded ID *values* (`if hhid==149`).

## Write generated lines with literal `$` and `"`

Typing a literal `$` or `"` inside a double-quoted Stata string gets mangled by
macro expansion (`"$projectdir"` expands to nothing at build time). Emit them via
`char()` — `char(34)` = `"`, `char(36)` = `$` — inserted as literal bytes:

```stata
replace code = "use " + char(34) + char(36) + "projectdir/data" + char(34) + ", clear" if lineno==54
```
Write the transformed lines with `file write` of the *variable value* (a string
expression, not a macro), which is also literal:

```stata
tempname out
file open `out' using "deid/analysis.do", write text replace
forvalues r = 1/`=_N' {
    file write `out' (code[`r']) _n
}
file close `out'
```

## Align the verify diff by the scrambled key, never by row position

`merge 1:1 _n using deid` assumes original and de-identified are in the same row
order — but every `merge` re-sorts by its key, so `_n`-alignment compares unrelated
rows and reports mass false mismatches. Map the original's id through the idmap,
then `merge 1:1 <id>_pubrep <key> using deid`.
