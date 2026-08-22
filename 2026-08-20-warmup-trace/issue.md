# `mcmc()` doesn't need to do trace() during warmup

greta's warmup loop calls `self$trace()` once per burst, appending that burst's
free state onto `traced_free_state` with `rbind`. The whole accumulated matrix
is discarded at the "scrub the free state trace" line the moment warmup ends,
and nothing reads it in between.

`rbind` copies everything accumulated so far on every append, so the cost grows
with the square of the burst count. At 200 free parameters and a warmup of
roughly 2000 iterations that is
[**over a gigabyte allocated for a matrix that is then deleted**](https://github.com/greta-dev/greta.benchmarks/blob/main/2026-08-20-warmup-trace/results.md#part-2-the-accumulation-on-its-own).

Numbers, and the code that produced them:
[results.md](https://github.com/greta-dev/greta.benchmarks/blob/main/2026-08-20-warmup-trace/results.md), from [`01-measure.R`](https://github.com/greta-dev/greta.benchmarks/blob/main/2026-08-20-warmup-trace/01-measure.R). How
runtime grows with warmup is
[part 1](https://github.com/greta-dev/greta.benchmarks/blob/main/2026-08-20-warmup-trace/results.md#part-1-how-runtime-scales-with-warmup); what removing
the call buys is [part 3](https://github.com/greta-dev/greta.benchmarks/blob/main/2026-08-20-warmup-trace/results.md#part-3-what-removing-it-buys), which
fills in once a branch carrying the deletion exists.

## Why it is there

It fed tuning, and then stopped.

1. [`92c876af`](https://github.com/greta-dev/greta/commit/92c876af)
   (21 Mar 2018) added the warmup `trace()` call **and** the scrub, so
   `tune_diag_sd()` could do `samples <- self$traced_free_state` and take the
   sample posterior variance from it. Before this, warmup did not trace at all.
2. [`3c433f96`](https://github.com/greta-dev/greta/commit/3c433f96)
   (4 Sep 2018) made these fields per-chain lists, so the append became the
   `mapply(rbind, ...)` still in `trace()` today and the read became a loop over
   chains.
3. [`ef013050`](https://github.com/greta-dev/greta/commit/ef013050)
   (11 Sep 2018, "use welford accumulator for tuning") deleted that loop from
   `tune_diag_sd()` and replaced `sample_variance(samples)` with
   `self$sample_variance()`, backed by an online Welford accumulator fed from
   `last_burst_free_states`.

The consumer went; the producer stayed. Note this is specifically
`tune_diag_sd()` — `trace_values()` was untouched by that commit and still reads
`traced_free_state`, which is the sampling-phase consumer and why the *sampling*
`trace()` call must stay.

So it is a leftover from an R-side tuning refactor, not from TF1.

## Fix

Remove the `self$trace()` call from the warmup loop in `R/sampler_class.R`. The
sampling loop keeps its own.

Checked:

- **draws are bit-identical** with and without it. Fixing both seeds
  (`set.seed()` *and* `tf$random$set_seed()` — see below) makes `mcmc()`
  reproducible, and 2 chains x 150 draws x 5 parameters come back identical,
  max absolute difference 0
- **no TF or TFP code can see it.** With `values = FALSE`, `trace()` does one
  thing: `mapply(rbind, ...)` into an R6 field. Its input is already
  `as.array()`-converted R matrices. No tensor is touched, no Python round trip
  is made. The `values = TRUE` branch is the only one calling into TF, and
  warmup never takes it
- **the warmup progress bar is unaffected** — it is driven by the burst loop's
  `completed_iterations`, and this removes the trace, not the bursts
- aborting mid-warmup still returns NULL from `stashed_samples()`, which gates
  on `traced_values`; warmup calls `trace()` with `values = FALSE`, so it never
  fills that
- full test suite unchanged, `FAIL 0 | WARN 0 | SKIP 2 | PASS 1952`

## Relation to #547 and #765

- This is a piece of #547 — if the warmup loop moves into TF, the R-side trace goes with it. Worth doing separately because it is a one-line deletion available now. 
- #779, which resolves #765, does not fix it: it adds `do_warmup <- self$warmup > 0` so warmup can be skipped wholesale, and stubs `tune_tf` / `tune_r`, but never touches the `trace()` call.

# Aside, relevant to #285 / #427

`mcmc()` *is* reproducible today if both seeds are set:

```r
set.seed(1)
tf$random$set_seed(1L)
```

Neither alone is enough; together they give bit-identical draws, and different
seeds give different draws. greta's own `set_tf_seed()` stores `self$seed` in
`dag$tf_environment$rng_seed`, which nothing reads — it never calls
`tf$random$set_seed()`. Relevant to #285 and #427
