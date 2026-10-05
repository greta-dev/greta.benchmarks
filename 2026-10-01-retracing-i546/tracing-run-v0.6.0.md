# Tracing run of each model, on CRAN


This document is rendered 3 times per version by `02-tracing-runs.R`,
each time in a fresh R session against that version’s greta, installed
on its own: CRAN (greta 0.6.0), main, and greta#843. This is run 3 of 3.
The report, `report.html`, puts every run of the three versions side by
side.

## Which greta this is

``` r
library(greta)
```


    Attaching package: 'greta'

    The following objects are masked from 'package:stats':

        binomial, cov2cor, poisson

    The following objects are masked from 'package:base':

        %*%, %o%, apply, backsolve, beta, chol2inv, colMeans, colSums,
        diag, eigen, forwardsolve, gamma, identity, outer, rowMeans,
        rowSums, sweep, tapply

``` r
params$label
```

    [1] "CRAN"

``` r
params$branch
```

    [1] "v0.6.0"

``` r
params$sha
```

    [1] "026efd63c08893f65de582b232c0748afaf72127"

``` r
find.package("greta")
```

    [1] "/Users/nick_1/github/greta-dev/greta.benchmarks/2026-10-01-retracing-i546/libs/v0.6.0/greta"

``` r
# the settings every mcmc() call below uses: the draws asked for are the
# iterations divided by this version's iterations per draw
params$iterations_per_draw
```

    [1] 2

``` r
warmup_draws <- as.integer(params$warmup_iterations / params$iterations_per_draw)
sample_draws <- as.integer(params$sample_iterations / params$iterations_per_draw)
c(
  warmup_draws = warmup_draws,
  sample_draws = sample_draws,
  chains = params$chains,
  cores = params$cores
)
```

    warmup_draws sample_draws       chains        cores 
            1000         1000            4            4 

``` r
# greta#843 adds pfor_min_elements(), so this is TRUE only on #843
exists("pfor_min_elements", envir = asNamespace("greta"))
```

    [1] FALSE

## How the retracing is shown

TensorFlow warns when a `tf.function` is traced many times, but it logs
the warning through Python, where knitr cannot see it. `retracing()`
routes TensorFlow’s logger to stderr, captures that, and returns the
warning lines. `traces()` asks a traced function how many times it has
been traced.

``` r
rebind_tf_logger <- function() {
  reticulate::py_run_string(paste(
    "import sys",
    "from tensorflow.python.platform import tf_logging",
    "for _h in tf_logging.get_logger().handlers: _h.stream = sys.stderr",
    sep = "\n"
  ))
}

retracing <- function(expr) {
  out <- reticulate::py_capture_output(
    {
      rebind_tf_logger()
      force(expr)
    },
    type = "stderr"
  )
  grep(
    "triggered tf.function retracing",
    strsplit(out, "\n")[[1]],
    value = TRUE
  )
}

traces <- function(f) {
  as.integer(f$experimental_get_tracing_count())
}

# one timed mcmc() run: the elapsed seconds, the retracing warnings logged
# during it, and how many times each of the model's functions was traced
one_run <- function(m) {
  warnings <- retracing(
    time <- system.time(
      draws <- mcmc(
        m,
        warmup = warmup_draws,
        n_samples = sample_draws,
        chains = params$chains,
        n_cores = params$cores,
        verbose = FALSE
      )
    )
  )
  sampler <- attr(draws, "model_info")$samplers[[1]]
  data.frame(
    seconds = round(time[["elapsed"]], 2),
    retracing_warnings = length(warnings),
    log_prob_traces = traces(m$dag$tf_log_prob_function),
    trace_values_traces = traces(m$dag$tf_trace_values_batch),
    sampler_traces = traces(sampler$tf_evaluate_sample_batch)
  )
}

runs <- list()
```

Each model is from greta’s `inst/examples/`, and is the same model the
benchmark suite runs.

## linear

A simple linear regression: the rating in `attitude` against the number
of complaints. Three parameters, so it is the floor for greta’s
per-iteration overhead. The intercept and slope come out correlated at
-0.97, because the predictor is not centred, so they mix more slowly
than `sd`.

``` r
set.seed(2026 - 09 - 29)
int <- normal(0, 10)
```

    ℹ Initialising python and checking dependencies, this may take a moment.

    ✔ Initialising python and checking dependencies ... done!

``` r
coef <- normal(0, 10)
sd <- cauchy(0, 3, truncation = c(0, Inf))
mu <- int + coef * attitude$complaints
distribution(attitude$rating) <- normal(mu, sd)
m <- model(int, coef, sd)

runs$linear <- one_run(m)
runs$linear
```

      seconds retracing_warnings log_prob_traces trace_values_traces sampler_traces
    1    3.36                  0               2                   2              1

## multiple_linear

The same regression on all six predictors in `attitude`, through a
matrix multiply, so the gradient goes through `%*%`. Eight parameters.

``` r
set.seed(2026 - 09 - 29)
design <- as.matrix(attitude[, 2:7])
int <- normal(0, 10)
coefs <- normal(0, 10, dim = ncol(design))
sd <- cauchy(0, 3, truncation = c(0, Inf))
mu <- int + design %*% coefs
distribution(attitude$rating) <- normal(mu, sd)
m <- model(int, coefs, sd)

runs$multiple_linear <- one_run(m)
runs$multiple_linear
```

      seconds retracing_warnings log_prob_traces trace_values_traces sampler_traces
    1    3.31                  0               2                   2              1

## hierarchical_linear

Sepal length against sepal width in `iris`, with an offset per species
drawn from a shared distribution. It uses `rbind()` and integer
indexing, which cost more per iteration than its six parameters suggest.

``` r
set.seed(2026 - 09 - 29)
int <- normal(0, 10)
coef <- normal(0, 10)
sd <- cauchy(0, 3, truncation = c(0, Inf))
species_sd <- lognormal(0, 1)
species_offset <- normal(0, species_sd, dim = 2)
species_effect <- rbind(0, species_offset)
species_id <- as.numeric(iris$Species)
mu <- int + coef * iris$Sepal.Width + species_effect[species_id]
distribution(iris$Sepal.Length) <- normal(mu, sd)
m <- model(int, coef, sd, species_sd, species_offset)

runs$hierarchical_linear <- one_run(m)
runs$hierarchical_linear
```

      seconds retracing_warnings log_prob_traces trace_values_traces sampler_traces
    1     4.7                  0               2                   2              1

## eight_schools

The classic hierarchical model of coaching effects in eight schools. The
school effects’ scale is itself a parameter, which makes the posterior a
funnel: the standard test of whether a sampler handles hierarchical
models.

``` r
set.seed(2026 - 09 - 29)
y <- c(28, 8, -3, 7, -1, 1, 18, 12)
sigma_y <- c(15, 10, 16, 11, 9, 11, 10, 18)
N <- length(y)
sigma_eta <- inverse_gamma(1, 1)
eta <- normal(0, sigma_eta, dim = N)
mu_theta <- normal(0, 100)
xi <- normal(0, 5)
theta <- mu_theta + xi * eta
distribution(y) <- normal(theta, sigma_y)
m <- model(sigma_eta, eta, mu_theta, xi)

runs$eight_schools <- one_run(m)
runs$eight_schools
```

      seconds retracing_warnings log_prob_traces trace_values_traces sampler_traces
    1    3.29                  0               2                   2              1

## cjs

A Cormack-Jolly-Seber capture-recapture model: survival and detection
probabilities for 20 occasions, from simulated capture histories of 100
animals. The recursion for `chi` adds nodes on each of 19 iterations, so
this is the deep graph, where graph construction costs more than the 40
parameters suggest.

``` r
set.seed(2026)
n_obs <- 100
n_time <- 20
y <- matrix(
  sample(c(0, 1), size = n_obs * n_time, replace = TRUE),
  ncol = n_time
)

first_obs <- apply(y, 1, function(x) min(which(x > 0)))
final_obs <- apply(y, 1, function(x) max(which(x > 0)))
obs_id <- unlist(apply(
  y,
  1,
  function(x) seq(min(which(x > 0)), max(which(x > 0)), by = 1)[-1]
))
capture_vec <- unlist(apply(
  y,
  1,
  function(x) x[min(which(x > 0)):max(which(x > 0))][-1]
))

phi <- beta(1, 1, dim = n_time)
p <- beta(1, 1, dim = n_time)

chi <- ones(n_time)
for (i in seq_len(n_time - 1)) {
  tn <- n_time - i
  chi[tn] <- (1 - phi[tn]) + phi[tn] * (1 - p[tn + 1]) * chi[tn + 1]
}

alive_data <- ones(length(obs_id))
not_seen_last <- final_obs != n_time
final_observation <- ones(sum(not_seen_last))

distribution(alive_data) <- bernoulli(phi[obs_id - 1])
distribution(capture_vec) <- bernoulli(p[obs_id])
distribution(final_observation) <- bernoulli(chi[final_obs[not_seen_last]])

m <- model(phi, p)

runs$cjs <- one_run(m)
runs$cjs
```

      seconds retracing_warnings log_prob_traces trace_values_traces sampler_traces
    1   37.85                  0               2                   2              1

## opt() with a hessian for each of 20 scalar targets

The case greta#546 reported: a model with many separate targets, each
needing its own hessian.

``` r
set.seed(2026 - 09 - 29)
y <- rnorm(20)

# twenty separate scalar parameters, b1 to b20
target_names <- paste0("b", 1:20)
for (name in target_names) {
  assign(name, variable())
}
distribution(y) <- normal(do.call(c, mget(target_names)), 1)

# model() names its targets from the expressions it is given, so the call is
# built from the names: this is model(b1, b2, ..., b20)
m <- eval(as.call(c(quote(model), lapply(target_names, as.name))))

hessian_warnings <- retracing(
  hessian_time <- system.time(fit <- opt(m, hessian = TRUE))
)
hessian_run <- data.frame(
  seconds = round(hessian_time[["elapsed"]], 2),
  retracing_warnings = length(hessian_warnings)
)
hessian_run
```

      seconds retracing_warnings
    1   10.47                  2

``` r
cat(substr(hessian_warnings, 1, 120), sep = "\n")
```

    WARNING:tensorflow:5 out of the last 5 calls to <function pfor.<locals>.f at 0x132fd0d60> triggered tf.function retracin
    WARNING:tensorflow:6 out of the last 6 calls to <function pfor.<locals>.f at 0x132e8e200> triggered tf.function retracin

## All five mcmc() runs

``` r
summary <- do.call(rbind, runs)
summary
```

                        seconds retracing_warnings log_prob_traces
    linear                 3.36                  0               2
    multiple_linear        3.31                  0               2
    hierarchical_linear    4.70                  0               2
    eight_schools          3.29                  0               2
    cjs                   37.85                  0               2
                        trace_values_traces sampler_traces
    linear                                2              1
    multiple_linear                       2              1
    hierarchical_linear                   2              1
    eight_schools                         2              1
    cjs                                   2              1

``` r
if (nzchar(params$out_rds)) {
  saveRDS(
    list(
      label = params$label,
      branch = params$branch,
      sha = params$sha,
      run = params$run,
      mcmc = cbind(model = rownames(summary), summary),
      hessian = hessian_run
    ),
    params$out_rds
  )
}
```
