# Wiring `model(compile=)` through to `jit_compile`


## The question

`model(compile = TRUE)` is documented as applying XLA JIT compilation
but has been inert since January 2023. The `wire-jit-compile` branch
passes it through at the two `tf_function()` sites in `dag_class.R`.
Does that make greta faster?

A ratio below 1 means the branch is faster. Both branches resolve their
own Python stack, recorded below, so a ratio here is the effect of the
wiring rather than of a version bump.

The model is a plain regression on purpose: XLA cannot compile the
gradients of `FillScaleTriL` or `CorrelationCholesky`, so anything using
`wishart()`, `lkj_correlation()` or `cholesky_variable()` errors on the
wired branch instead of producing a timing.

## Results

| task       | wire-jit-compile |    main |
|:-----------|-----------------:|--------:|
| build      |             20ms |  20.2ms |
| mcmc_short |            788ms | 850.3ms |

| task       | median |   min |
|:-----------|-------:|------:|
| build      |  0.990 | 1.008 |
| mcmc_short |  0.927 | 0.935 |

`bench::mark()`. `min` is the statistic least contaminated by garbage
collection and scheduling; where the two branches share byte-identical
code, it is the one to read.

## What this says

Wiring `compile` through makes sampling about **7% faster** (0.927
median, and the `min` ratio agrees, so this is not a garbage-collection
artefact). Model definition is unchanged (0.990), which is what you
would expect: XLA compiles at first call, not at definition.

Both branches resolved the same Python stack, so this is the effect of
the wiring rather than of a version difference.

The model is a plain regression on purpose. XLA cannot compile the
gradients of `FillScaleTriL` or `CorrelationCholesky`, so `wishart()`,
`lkj_correlation()` and `cholesky_variable()` models error on the wired
branch instead of producing a timing. **7% is therefore the upside for
the models XLA can handle, and says nothing about the ones it cannot.**

## Environment

|  |  |
|:---|:---|
| run at | 2026-08-23 10:21:31 AEST |
| OS | macOS Tahoe 26.5.2 |
| system | aarch64, darwin23 |
| CPU | Apple M3 |
| cores detected | 8 |
| R | R version 4.6.1 (2026-06-24) |
| R package: bench | 1.1.4 (CRAN (R 4.6.0)) |
| R package: cross | 0.0.0.9000 (Github ([DavisVaughan/cross@1a0db276e1f14b404efa6305b7890ffe24690f1d](https://github.com/DavisVaughan/cross/commit/1a0db276e1f14b404efa6305b7890ffe24690f1d))) |
| R package: reticulate | 1.46.0 (CRAN (R 4.6.0)) |
| R package: tensorflow | 2.20.0 (CRAN (R 4.6.0)) |
| stack, wire-jit-compile | python 3.12 \| tensorflow 2.21.0 \| tfp 0.25.0 |
| stack, main | python 3.12 \| tensorflow 2.21.0 \| tfp 0.25.0 |
| greta, current | [`3b7027ed9eb11d293cd5e9bbfee1d7bf7b54e9b2`](https://github.com/greta-dev/greta/commit/3b7027ed9eb11d293cd5e9bbfee1d7bf7b54e9b2) |
| greta, reference | [`e8563dae0ef2b8be384fac023f62df1febf17ae6`](https://github.com/greta-dev/greta/commit/e8563dae0ef2b8be384fac023f62df1febf17ae6) |
