# The benchmark suite

A fixed set of models and tasks, run across two git branches of greta with
[{cross}](https://github.com/DavisVaughan/cross), by hand.

Not wired to CI, and not meant to be: a run takes minutes per branch because
each branch is installed first. This is for checking a change before opening a
pull request.

## Running it

```bash
Rscript --quiet --vanilla suite/run-suite.R my-branch main
Rscript --quiet --vanilla suite/report.R suite/results/<the file it wrote>.rds
```

The branch under test goes first. Two knobs, both environment variables:

| variable | default | what it does |
|---|---|---|
| `GRETA_BENCH_ITERATIONS` | 30 | iterations per model x task cell |
| `GRETA_BENCH_MODELS` | all | comma-separated subset, for a quick look |
| `GRETA_REPO` | `~/github/greta-dev/greta` | the checkout {cross} installs from |

## Reading the result

**Check the "is the difference resolved?" table before the ratios.** A ratio is
only meaningful when the difference between branches is larger than the spread
within a branch. This is not a theoretical worry: comparing `wire-jit-compile`
against `main` at 10 iterations gave estimates of 27 ms and 62 ms on separate
runs, and only at 50 iterations did it resolve to 42 ms with a 95% interval of
9 to 55 ms. A small run of a real effect looks exactly like no effect.

If a cell says "not at this n", raise `GRETA_BENCH_ITERATIONS` rather than
reporting the median.

## A worked check that the guard works

Running the suite with `GRETA_BENCH_ITERATIONS=3` on a branch whose only changes
are code comments gave ratios of 0.964, 1.007 and 0.964 - which reads as "3.6%
faster" and is entirely noise. Every cell of the resolution table said
`not at this n`. That is the table doing its job; trust it over the ratios.

## The models

In `models.R`, taken from greta's own `inst/examples/` so the suite measures
models people actually write:

| model | free params | why it is here |
|---|---|---|
| `linear` | 3 | the cheapest real model - a floor for per-iteration overhead |
| `multiple_linear` | 8 | matrix multiply in the gradient |
| `hierarchical_linear` | 6 | `rbind` and integer indexing |
| `hierarchical_slopes_corr` | 10 | **the only cholesky-path model** |
| `wide_linear` | 202 | a 2000x200 design, so the gradient is real work |

`hierarchical_slopes_corr` uses `lkj_correlation()` and `chol()`, which go
through `CorrelationCholesky`. XLA cannot compile its gradients, so this is the
model that catches breakage a plain regression never will. **A trimmed subset
that drops it cannot see cholesky regressions.**

## The tasks

`build` (`model()`), `opt_adam`, and `mcmc_short`. Both inference entry points,
deliberately: `mcmc()` and `opt()` share almost no code, so a change to one is
invisible to the other.

## Adding a model

Give it a name in `models.R`, return a `model()`, and say in the comment which
part of the stack it exercises that the others do not. A model that duplicates
an existing one's coverage costs run time and buys nothing.
