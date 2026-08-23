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

# ---- part 1: greta opt() on models from the package's own examples ---------

# These are the models in inst/examples/, which the example_models vignette
# renders - real data, real structure, and already recognisable to anyone who
# reads greta's docs. A synthetic z ~ normal(0, 1) would understate the gradient
# work and so overstate how much of an iteration is round-trip overhead.

set.seed(2026 - 08 - 22)

example_models <- list(
  # inst/examples/linear.Rmd
  linear = function() {
    int <- normal(0, 10)
    coef <- normal(0, 10)
    sd <- cauchy(0, 3, truncation = c(0, Inf))
    mu <- int + coef * attitude$complaints
    distribution(attitude$rating) <- normal(mu, sd)
    model(int, coef, sd)
  },
  # inst/examples/multiple_linear.Rmd
  multiple_linear = function() {
    design <- as.matrix(attitude[, 2:7])
    int <- normal(0, 10)
    coefs <- normal(0, 10, dim = ncol(design))
    sd <- cauchy(0, 3, truncation = c(0, Inf))
    mu <- int + design %*% coefs
    distribution(attitude$rating) <- normal(mu, sd)
    model(int, coefs, sd)
  },
  # inst/examples/hierarchical_linear.Rmd
  hierarchical_linear = function() {
    int <- normal(0, 10)
    coef <- normal(0, 10)
    sd <- cauchy(0, 3, truncation = c(0, Inf))
    species_sd <- lognormal(0, 1)
    species_offset <- normal(0, species_sd, dim = 2)
    species_effect <- rbind(0, species_offset)
    species_id <- as.numeric(iris$Species)
    mu <- int + coef * iris$Sepal.Width + species_effect[species_id]
    distribution(iris$Sepal.Length) <- normal(mu, sd)
    model(int, coef, sd, species_sd, species_offset)
  },
  # the same shape as multiple_linear, scaled up until the gradient is real
  # work: if per-iteration cost is still flat here, the overhead dominates even
  # for a model that is not cheap
  wide_linear = function() {
    n <- 2000
    p <- 200
    design <- matrix(rnorm(n * p), n, p)
    y_obs <- as.numeric(design %*% rnorm(p, sd = 0.2) + rnorm(n, sd = 0.5))
    int <- normal(0, 10)
    coefs <- normal(0, 10, dim = p)
    sd <- cauchy(0, 3, truncation = c(0, Inf))
    mu <- int + design %*% coefs
    distribution(y_obs) <- normal(mu, sd)
    model(int, coefs, sd)
  }
)

time_opt <- function(name) {
  m <- example_models[[name]]()
  n_free <- length(unlist(m$dag$example_parameters(free = TRUE)))
  # one short run first, so tracing is not inside the timing
  invisible(opt(m, optimiser = adam(), max_iterations = 5))
  elapsed <- system.time(
    o <- opt(m, optimiser = adam(), max_iterations = 100)
  )[["elapsed"]]
  tibble(model = name, n_free = n_free, iterations = o$iterations,
         elapsed = elapsed)
}

opt_scaling <- map(names(example_models), time_opt) |>
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
