# Stata runnability fixes + dofile text-processing traps

Read this when a de-identified package halts on a run, or when writing a script
that transforms a dofile. None of these fixes change an estimate — they are
mechanical modernizations of code written for an older Stata, plus two real
traps in programmatic dofile editing.

## Running Stata headless (macOS)

```bash
"/Applications/Stata/StataSE.app/Contents/MacOS/stata-se" -b do FILE.do
```
- Log lands in `FILE.log` in the current directory. Scan it with
  `grep -nE "r\([0-9]+\);" FILE.log` — an `r(NNN);` is an error that halted the run.
- There is **no `timeout` command on stock macOS** (that's `gtimeout` from
  coreutils). Don't wrap Stata in `timeout` — you'll get exit 127 and a stale
  log. Use your tool's own timeout instead.
- `StataSE.app` may live under `/Applications/Stata/` or `/Applications/`; find
  the binary with `find /Applications -name stata-se`.

## Runnability fixes (old code → modern Stata)

| Symptom / old code | Fix | Note |
|---|---|---|
| `set mem 150m` → error | delete the line | memory is automatic since Stata 12 |
| `set matsize 800` | leave it | still accepted (no-op in SE) |
| `set scheme lean1` → scheme not found | fall back to a stock scheme (`s2color`) | cosmetic only; note it in the readme |
| `graph set pict fontface ...` → "pict settings not available under Unix" | wrap in `capture ` | pict/eps fontface is Windows/Mac-classic; cosmetic |
| `use "$dir\file"` (backslash) → not found on Unix | forward slash | Windows path separator |
| `merge k1 k2 using X, sort` → invalid syntax | `merge 1:1 k1 k2 using "X"` (or `m:1`) | pre-Stata-11 merge was removed in 11. Check key uniqueness in each dataset to choose 1:1 vs m:1. If the old code kept `_merge` (e.g. `keep if _merge==3`, `drop if _m==2`), keep the default `_merge`. |
| `outreg using f, ... 10pct ...` → "option 10pct not allowed" | drop ` 10pct` | the current SSC `outreg` makes a 3-symbol scheme the default; `sigsymb(...)` still works |
| `ivreg2 ..., gmm` → "-gmm- is no longer supported; use -gmm2s-" | ` gmm` → ` gmm2s` | same two-step efficient GMM |
| `gen tmp = ...` → "tmp already defined" | insert `cap drop tmp` before it | latent bug: a scratch var reused without dropping. Faithful to intent. |
| missing user command from SSC | `ssc install <cmd>` | e.g. `ivreg2`, `outreg`, `grc1leg`, `estout` |
| user command not on SSC (author-only ado) | comment the block out **with a note** | first check if it maps to a *published* result (see SKILL.md stage 3) |
| author-provided `.ado` in the package | bundle it into the deid folder + `adopath + "$projectdir"` | keeps the package self-sufficient |

General approach: run → read the first `r(...)` → apply the matching fix →
rerun. Repeat. Keep a note of every fix for the readme; reviewers want to know
exactly what changed and that none of it touched an estimate.

## Trap 1 — reading a dofile without corrupting it

If you read source lines with `file read` into a local and store them via
`postfile` (or re-reference them through `` `macval(line)' `` in a quoted
context), Stata **expands `$globals` and `` `locals` `` inside the code text**.
A line like `use "$projectdir/x"` silently becomes `use "/x"`. This is easy to
miss because most lines have no macros.

Use **Mata `cat()`**, which returns file lines completely literally:

```stata
clear
local inpath "orig/final.do"
mata:
    L = cat(st_local("inpath"))
    n = rows(L)
    st_addobs(n)
    ci = st_addvar("str2045", "code")     // postfile forbids strL; str2045 is plenty
    li = st_addvar("int", "lineno")
    for (i = 1; i <= n; i++) {
        st_sstore(i, ci, L[i])
        st_store(i, li, i)
    }
end
```

Now `code` holds every line verbatim, and you can transform it row-by-row.

## Trap 2 — writing generated lines with literal `$` and `"`

When you build a replacement line and need a literal `$` or `"` in the *output*,
do NOT type them inside a double-quoted Stata string — macro expansion mangles
them (e.g. `"$projectdir"` expands to nothing at build time). Emit them via
`char()`:

```stata
* want the file to contain:  use "$projectdir/data", clear
replace code = "use " + char(34) + char(36) + "projectdir/data" + char(34) + ", clear" ///
    if lineno==51
```
`char(34)` = `"`, `char(36)` = `$`. Because these are function results, they're
inserted as literal bytes and never re-expanded.

Write the transformed lines out with `file write` of the *variable value* (a
string expression, not a macro), which is also literal:

```stata
tempname out
file open `out' using "deid/final.do", write text replace
forvalues r = 1/`=_N' {
    file write `out' (code[`r']) _n
}
file close `out'
```

## Word-boundary matching for ID names

When flagging/replacing an ID name, use boundaries that treat `_` as a word
character, so `villageid` does not match inside `hh_villageid`, and `clusterid` does not
match inside `resid`/`consider`:

```stata
local pat "(?<![A-Za-z0-9_])" + "`v'" + "(?![A-Za-z0-9_])"
* detect:  ustrregexm(code, "`pat'")
* replace: ustrregexra(code, "`pat'", "`v'_pubrep")   // lookarounds are zero-width, preserved
```

## Gotchas that bite when building the verify/compare scripts

**`gettoken` leaves a leading space in the remainder.** `gettoken a b : pair`
gives `b` a leading blank. If you build a *key* from the second token you get
`"T1_A_ english_b"` (note the space), and the later merge/compare silently fails
to join. Trim it: `local b = trim("`b'")`. (Building the key from the *first*
token is safe — `gettoken` strips leading blanks before the first token.)

**`tabstat` returns nothing without `save`.** `tabstat x, s(sum)` only displays;
`r(StatTotal)` is empty unless you add `, save`. If you're capturing a result the
package computes with `tabstat` (and can't add `save` because you're keeping the
command verbatim), reproduce the same quantity directly — for `s(sum)` of a 1/.
indicator that's `count if x==1 & <sample>`.

**Single-line `if/foreach { … ; … }` fails in a do-file.** `if "\`s'"=="x" {
local a 1 ; local b 2 }` throws *"code follows on the same line as open brace"* /
*"matching close brace not found"* because `;` is not a separator without
`#delimit`. For branching inside `post`/inline code use `cond(cond, "A", "B")`
(an expression) or pre-computed keyed locals — not inline braces.

**Align by the scrambled key, never by row position.** `merge 1:1 _n using deid`
assumes the original and de-identified datasets are in the same order — but every
`merge` re-sorts by its key, so the output's row order rarely matches the input's.
`_n`-alignment then compares unrelated rows and reports mass false mismatches (or,
worse, passes by luck of monotonic ordering). Always align on the `_pubrep` key:
map the original's id through the idmap, then `merge 1:1 <id>_pubrep <key> using
deid`.

**`postfile` forbids `strL`.** Use `str2045` (plenty for var-name lists / code
lines); `strL` errors. A postfile survives `use`/`clear`, but `clear all` closes
it — check the dofile you instrument doesn't `clear all` between opening the
postfile and the last `post`.
