# Capture-from-commands (when a package saves no result files)

Goal: get one number per estimate out of a package that only prints to a log,
**without re-implementing the estimations** — you must test the package's own
commands, not a rewrite of them.

## Principle
Take the analysis script **verbatim** and insert save-lines *after* each estimation
that write that command's own stored results to a table. Generate the instrumented
copy **programmatically** from the real script (a pass that inserts lines after
matched estimation lines) so it is provably "the original script + saves" — then
diff the two to confirm every original line survived unchanged.

## Stata example
After each estimation, its results sit in `e()`/`r()`. Append them to a growing
file keyed by a label you assign per cell (`exhibit_panel_row_stat`):

```stata
* once, near the top:
capture postclose CAP
postfile CAP str40 key double value using "captured.dta", replace

* after an estimation command that the script already runs, e.g. a regression:
post CAP ("T2_priv_coef") (_b[treat])
post CAP ("T2_priv_se")   (_se[treat])
post CAP ("T2_N")         (e(N))
post CAP ("T2_r2")        (e(r2))
* a chi2 / test statistic, a lagged term, etc. -- capture every reported number:
post CAP ("T5_hansenJ")   (e(j))

* at the very end:
postclose CAP
* then: use captured.dta; export delimited using "new.csv", replace   (key,value)
```

For a **display-only** result (a command that prints a table but stores nothing,
e.g. a summary/tabulation), re-issue that command's *identical internal
computation* to capture the same number — do not eyeball it from the log.

## Precision
Also record, per cell, the precision the target reports at (its `decimals`), so the
comparison matches at reported precision rather than full double precision. Put that
in the REFERENCE table; `compare_tables.py` reads it.

## Not Stata?
Same shape: run the analysis code as-is, and after each model pull the fitted
object's coefficients / SEs / p-values / N / fit stats (R's `broom::tidy`/`glance`,
Python `statsmodels` `.params`/`.bse`/`.pvalues`) into a `key,value` CSV. The rule
is unchanged: capture from the package's own fitted objects, never a re-run of your
own specification.
