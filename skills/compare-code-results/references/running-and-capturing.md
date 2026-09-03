# Running packages and capturing their results (Stata)

For running the two packages being compared and pulling numbers out of them. Unlike
the ID-rename step, comparison often runs code that does **not** run as-is on your
Stata — the original and the cleaned package may target different versions, and the
two packages are frequently written by **different people** with different
conventions and dependencies. So expect to adapt a run here.

## Run Stata headless and find errors

```bash
"/Applications/Stata/StataSE.app/Contents/MacOS/stata-se" -b do FILE.do
```
- The log lands in `FILE.log`. Scan it: `grep -nE "r\([0-9]+\);" FILE.log` — an
  `r(NNN);` is an error that halted the run.
- **No `timeout` on stock macOS** (that's `gtimeout`); don't wrap Stata in it —
  you'll get exit 127 and a stale log. Use your tool's own timeout.
- Batch Stata returns OS exit 0 even on error, so read the log, not the exit code.

## Runnability fixes (running code written for another Stata / by someone else)

None of these change an estimate — they are mechanical. Run → read the first
`r(...)` → apply the matching fix → rerun. Record every fix.

| Symptom / code | Fix | Note |
|---|---|---|
| `set mem 150m` → error | delete the line | memory is automatic since Stata 12 |
| `set matsize 800` | leave it | still accepted (no-op in SE) |
| `set scheme lean1` → not found | fall back to a stock scheme (`s2color`) | cosmetic; note it |
| `graph set pict fontface ...` → "not available under Unix" | wrap in `capture ` | cosmetic |
| `use "$dir\file"` (backslash) → not found | forward slash | Windows path separator |
| `merge k1 k2 using X, sort` → invalid | `merge 1:1 k1 k2 using "X"` (or `m:1`) | pre-Stata-11 merge removed in 11; keep `_merge` if the code uses it |
| `outreg ... 10pct` → "10pct not allowed" | drop ` 10pct` | current SSC `outreg`; `sigsymb(...)` still works |
| `ivreg2 ..., gmm` → "-gmm- no longer supported" | ` gmm` → ` gmm2s` | same two-step efficient GMM |
| `gen tmp = ...` → "tmp already defined" | `cap drop tmp` before it | scratch var reused; faithful to intent |
| missing SSC command | `ssc install <cmd>` | e.g. `ivreg2`, `outreg`, `grc1leg`, `estout` |
| author-only ado not on SSC | comment the block out **with a note** | first check if it maps to a reported result |
| package ships its own `.ado` | bundle it + `adopath + "$projectdir"` | keeps the run self-sufficient |

## Instrument a dofile to capture results (read verbatim, insert `post`)

Capture from the package's OWN commands — never re-implement the estimations. Read
the dofile **verbatim** with Mata `cat()` (using `file read` + a quoted context
makes Stata expand `$globals`/`` `locals` `` inside the code — `use "$dir/x"` →
`use "/x"`):

```stata
mata:
    L = cat("pkg/analysis.do")
    n = rows(L); st_addobs(n)
    ci = st_addvar("str2045","code")
    for (i=1; i<=n; i++) st_sstore(i, ci, L[i])
end
```
Then insert `post` lines after matched estimation lines and write the file out with
`file write (code[`r'])` (a variable value, literal — not a macro). See
`scripts/capture_estimates.md` for the `postfile`/`post` pattern.

## Capture / compare gotchas

- **`gettoken` leaves a leading space in the remainder.** `gettoken a b : pair`
  gives `b` a leading blank; a key built from it (`"T1_A_ english_b"`) fails to
  merge. `local b = trim("`b'")`. (Keys from the *first* token are safe.)
- **`tabstat` returns nothing without `save`.** `r(StatTotal)` is empty unless you
  add `, save`. If keeping the command verbatim, reproduce the quantity directly
  (e.g. `s(sum)` of a 1/. indicator = `count if x==1 & <sample>`).
- **Single-line `if/foreach { … ; … }` fails.** `;` is not a separator without
  `#delimit`. Use `cond(c,"A","B")` (an expression) or pre-computed keyed locals.
- **`postfile` forbids `strL`.** Use `str2045`. A postfile survives `use`/`clear`
  but `clear all` closes it — check the instrumented dofile doesn't `clear all`
  between opening the postfile and the last `post`.
- **Align by the shared key, never by row position (`_n`).** Every `merge`
  re-sorts, so `_n`-alignment compares unrelated rows.
