# The cost of greta’s discarded warmup trace


## The question

greta’s warmup loop appends each burst’s free state onto
`traced_free_state`, then discards the whole thing when warmup ends.
What does that cost, and does it grow faster than linearly?

Wall time rather than effective samples per second, on purpose: the
change this measures deletes work whose result is thrown away, so the
sampler behaves identically and the draws are unchanged. ESS is a
stochastic estimate and would only add variance. It is also unavailable
as a clean comparison anyway, since `mcmc()` does not respect
`set.seed()` ([greta
\#285](https://github.com/greta-dev/greta/issues/285),
[\#427](https://github.com/greta-dev/greta/issues/427)).

## Part 1: how runtime scales with warmup

Wall-clock seconds for `mcmc(n_samples = 100, chains = 2)`, single runs.

| warmup | n_free = 1 | n_free = 20 | n_free = 200 |
|-------:|-----------:|------------:|-------------:|
|    500 |       0.73 |        0.82 |         0.79 |
|   1000 |       1.16 |        1.22 |         1.55 |
|   2000 |       2.17 |        2.22 |         3.14 |
|   4000 |       3.96 |        4.15 |         8.26 |

Warmup 500 to 4000 is an eight-fold increase in iterations. Over that
range the time grows 5.4-fold at one free parameter, 5.1-fold at twenty,
and 10.5-fold at 200. Only the largest model grows faster than its
iteration count; the gap is the accumulation cost, and it appears only
once a model has enough parameters for the copied matrix to be large.

These are single runs, so read the shape across the row rather than any
individual cell. The one- and twenty-parameter columns are the same
model cost to within noise, and swap places between runs.

## Part 2: the accumulation on its own

greta removed, so the growth is attributable to `rbind` rather than to
anything in the sampler. This is the accumulation the warmup loop
performs:

``` r
accumulate <- function(n_bursts, n_free, burst = 3) {
  acc <- matrix(nrow = 0, ncol = n_free)
  for (i in seq_len(n_bursts)) {
    acc <- rbind(acc, matrix(0, nrow = burst, ncol = n_free))
  }
  nrow(acc)
}
```

Warmup breaks a burst roughly every three iterations once tuning
changepoints are counted, so 167, 334 and 667 bursts stand in for
warmups of about 500, 1000 and 2000 iterations. At 200 free parameters:

| bursts |  median | allocated |
|-------:|--------:|----------:|
|    167 |  11.6ms |      65MB |
|    334 |  41.2ms |     258MB |
|    667 | 188.9ms |    1023MB |

Doubling the burst count quadruples both time and memory; quadrupling it
multiplies them by about sixteen. That is the signature of copying the
whole accumulated matrix on every append. At 667 bursts — a warmup of
roughly 2000 iterations — greta allocates over a gigabyte for a matrix
it then deletes.

## Part 3: what removing it buys

**Not measured.** This needs a branch with the `self$trace()` call
removed from the warmup loop in `R/sampler_class.R`. Create it, then
re-run `01-measure.R` with `GRETA_FIX_BRANCH` set, then `02-report.R`.

An in-session check by patching the working tree gave 3.23s to 2.18s at
200 free parameters and warmup 2000, and 7.62s to 3.79s at warmup 4000.
That is recorded as motivation only: patching a working tree is not
reproducible by anyone else, which is the whole reason this directory
exists.

## Environment

|  |  |
|:---|:---|
| run at | 2026-08-20 13:55:14 AEST |
| OS | macOS Tahoe 26.5.2 |
| system | aarch64, darwin23 |
| CPU | Apple M3 |
| cores detected | 8 |
| R | R version 4.6.1 (2026-06-24) |
| R package: bench | 1.1.4 (CRAN (R 4.6.0)) |
| R package: cross | 0.0.0.9000 (Github ([DavisVaughan/cross@1a0db276e1f14b404efa6305b7890ffe24690f1d](https://github.com/DavisVaughan/cross/commit/1a0db276e1f14b404efa6305b7890ffe24690f1d))) |
| R package: reticulate | 1.46.0 (CRAN (R 4.6.0)) |
| R package: tensorflow | 2.20.0 (CRAN (R 4.6.0)) |
