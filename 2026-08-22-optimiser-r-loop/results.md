# What driving the optimiser loop from R costs


## The question

`tf_optimiser` and `tf_compat_optimiser` run a `while` loop in R,
stepping into TensorFlow once per iteration. `tfp_optimiser` does not.
What does the R-driven loop cost, and what would moving it into TF
actually buy?

## Part 1: `opt()` cost per iteration does not move with model size

| n_free | iterations | per iteration (ms) |
|-------:|-----------:|-------------------:|
|      1 |         58 |               0.86 |
|     10 |         90 |               0.68 |
|    100 |        100 |               0.61 |
|    500 |        100 |               0.61 |

0.61–0.86 ms per iteration across a 500-fold change in the number of
free parameters. The per-iteration cost is therefore fixed overhead, not
gradient work.

## Part 2: the ceiling, on identical arithmetic

greta removed. The same 200 gradient-descent steps, driven from R and
driven inside TF, so the difference is the cost of crossing back into R:

``` r
# one gradient-descent step on a scalar: identical work either way, so the
# difference between these two is the cost of crossing back into R each time
n_steps <- 200L

x_r <- tf$Variable(1, dtype = tf$float32)
step_once <- tf_function(function() {
  x_r$assign_sub(tf$constant(0.001, dtype = tf$float32) * (2 * x_r))
  x_r
})

r_driven <- function() {
  for (i in seq_len(n_steps)) step_once()
  x_r
}

x_tf <- tf$Variable(1, dtype = tf$float32)
tf_driven <- tf_function(function() {
  tf$while_loop(
    cond = function(i) tf$less(i, n_steps),
    body = function(i) {
      x_tf$assign_sub(tf$constant(0.001, dtype = tf$float32) * (2 * x_tf))
      list(tf$add(i, 1L))
    },
    loop_vars = list(tf$constant(0L))
  )
})
```

| expression |     min |  median |    itr/sec |
|-----------:|--------:|--------:|-----------:|
|     r_loop |  12.6ms |  13.2ms |   70.80483 |
|    tf_loop | 496.8µs | 524.1µs | 1853.30283 |

Driving the loop inside TF is **25x** faster here, which puts the bare
round trip at about **0.063 ms per step**.

## What that means for the fix

The round trip is real but it is *not* most of what `opt()` spends per
iteration: 0.063 ms of round trip against 0.64 ms per `opt()` iteration,
so roughly 10% of it.

The rest is greta’s own loop body, which runs in R: the convergence
check, the `$numpy()` conversion of the objective, and
`check_numerical_overflow()`. So moving the `while` loop into TF only
pays if the body moves with it. Wrapping the loop alone and leaving the
body in R would recover the smaller share.

## Environment

|  |  |
|:---|:---|
| run at | 2026-08-22 14:27:12 AEST |
| OS | macOS Tahoe 26.5.2 |
| system | aarch64, darwin23 |
| CPU | Apple M3 |
| cores detected | 8 |
| R | R version 4.6.1 (2026-06-24) |
| R package: bench | 1.1.4 (CRAN (R 4.6.0)) |
| R package: cross | 0.0.0.9000 (Github ([DavisVaughan/cross@1a0db276e1f14b404efa6305b7890ffe24690f1d](https://github.com/DavisVaughan/cross/commit/1a0db276e1f14b404efa6305b7890ffe24690f1d))) |
| R package: reticulate | 1.46.0 (CRAN (R 4.6.0)) |
| R package: tensorflow | 2.20.0 (CRAN (R 4.6.0)) |
