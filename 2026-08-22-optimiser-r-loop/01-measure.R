# What does driving the optimiser loop from R cost?
#
# greta's tf_optimiser and tf_compat_optimiser each run a `while` loop in R,
# stepping into TensorFlow once per iteration. tfp_optimiser does not - TFP
# drives the iteration itself. The marker at optimiser_class.R:321 asks for the
# first two to work the same way.
#
# Two measurements:
#
#   part 1  greta's own opt(), per-iteration cost against model size. If the
#           cost is flat, it is dominated by the round trip rather than by the
#           gradient step.
#   part 2  the ceiling on what moving the loop into TF could buy, measured on
#           identical arithmetic driven two ways: an R loop calling a
#           tf_function N times, versus one tf_function containing a
#           tf$while_loop of N iterations. greta is not involved, so this
#           isolates the round trip from anything greta does.
#
# No {cross} here: there is no second version to compare against. Part 2 stands
# in for the branch that does not exist yet, and part 1 measures the status quo.
#
# Wall time, not ESS/sec: opt() is deterministic given a start, and nothing here
# changes what is computed.

library(bench)
library(here)
library(fs)
library(dplyr)
library(tidyr)
library(purrr)
library(greta)
library(tensorflow)

run_dir <- here("2026-08-22-optimiser-r-loop")
source(here("provenance.R"))

# ---- part 1: greta opt(), cost per iteration against model size --------------

set.seed(2026 - 08 - 22)

time_opt <- function(n_free) {
  z <- normal(0, 1, dim = n_free)
  y <- as_data(rnorm(n_free))
  distribution(y) <- normal(z, 1)
  m <- model(z)
  # one short run first, so tracing is not inside the timing
  invisible(opt(m, optimiser = adam(), max_iterations = 5))
  elapsed <- system.time(
    o <- opt(m, optimiser = adam(), max_iterations = 100)
  )[["elapsed"]]
  tibble(n_free = n_free, iterations = o$iterations, elapsed = elapsed)
}

opt_scaling <- map(c(1, 10, 100, 500), time_opt) |>
  list_rbind() |>
  mutate(per_iter_ms = 1000 * elapsed / iterations)

# ---- part 2: the same arithmetic, driven from R and from TF ------------------

## ---- loops ----
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
## ---- end-loops ----

# trace both before timing
invisible(r_driven())
invisible(tf_driven())

loop_cost <- bench::mark(
  r_loop = r_driven(),
  tf_loop = tf_driven(),
  check = FALSE,
  filter_gc = FALSE,
  min_iterations = 20
)

saveRDS(
  list(
    opt_scaling = opt_scaling,
    loop_cost = loop_cost,
    n_steps = n_steps,
    provenance = host_provenance()
  ),
  path(run_dir, "results.rds"),
  compress = "xz"
)
