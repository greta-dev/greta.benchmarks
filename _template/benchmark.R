# What each version of greta runs, in a fresh R session of its own: run.R
# sources it once per version per session, and keeps the list it ends with.
# Each `# ---- label ----` line starts a section that index.qmd shows by that
# label.
#
# Run it alone to try it against whichever greta is installed:
#
#   Rscript --quiet --vanilla posts/YYYY-MM-DD-short-name-iNNN/benchmark.R

# ---- benchmark-setup ----
library(greta)
library(bench)
session <- as.integer(Sys.getenv("GRETA_BENCH_SESSION", "1"))
session_seed <- 2026 - 10 - 5 + session

# ---- benchmark-settings ----
# warmup and n_samples are mcmc()'s arguments, so they count draws; the
# *_calls settings count timed calls
bench_settings <- list(
  warmup = 1000,
  n_samples = 1000,
  chains = 4,
  n_cores = 4,
  build_calls = 5,
  opt_calls = 5,
  mcmc_calls = 2
)

# ---- model-linear ----
build_linear <- function() {
  int <- normal(0, 10)
  coef <- normal(0, 10)
  sd <- cauchy(0, 3, truncation = c(0, Inf))
  mu <- int + coef * attitude$complaints
  distribution(attitude$rating) <- normal(mu, sd)
  model(int, coef, sd)
}

# ---- model-multiple-linear ----
build_multiple_linear <- function() {
  design <- as.matrix(attitude[, 2:7])
  int <- normal(0, 10)
  coefs <- normal(0, 10, dim = ncol(design))
  sd <- cauchy(0, 3, truncation = c(0, Inf))
  mu <- int + design %*% coefs
  distribution(attitude$rating) <- normal(mu, sd)
  model(int, coefs, sd)
}

# ---- model-hierarchical-linear ----
build_hierarchical_linear <- function() {
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
}

# ---- model-eight-schools ----
build_eight_schools <- function() {
  y <- c(28, 8, -3, 7, -1, 1, 18, 12)
  sigma_y <- c(15, 10, 16, 11, 9, 11, 10, 18)
  sigma_eta <- inverse_gamma(1, 1)
  eta <- normal(0, sigma_eta, dim = 8)
  mu_theta <- normal(0, 100)
  xi <- normal(0, 5)
  theta <- mu_theta + xi * eta
  distribution(y) <- normal(theta, sigma_y)
  model(sigma_eta, eta, mu_theta, xi)
}

# ---- benchmark-sampler-iterations ----
# A random walk on a target far wider than its steps accepts every proposal, so
# the variance between kept draws over one step's variance counts the sampler
# iterations between them. It is also the session's first mcmc() call, so
# TensorFlow's start-up costs fall here rather than on the first model.
step_sd <- 0.1
x <- normal(0, 1e6)
walk <- mcmc(
  model(x),
  sampler = rwmh(epsilon = step_sd, diag_sd = 1),
  warmup = 0,
  n_samples = 4000,
  thin = 1,
  chains = 1,
  initial_values = initials(x = 0),
  verbose = FALSE
)
sampler_iterations_per_draw <- round(
  var(diff(as.vector(walk[[1]]))) / step_sd^2
)

# ---- bench-build-linear ----
# mark()'s `iterations` is how many times it calls the expression
build_linear
bench_build_linear <- mark(
  build_linear(),
  iterations = bench_settings$build_calls,
  check = FALSE,
  memory = FALSE,
  filter_gc = FALSE
)

# ---- bench-build-multiple-linear ----
build_multiple_linear
bench_build_multiple_linear <- mark(
  build_multiple_linear(),
  iterations = bench_settings$build_calls,
  check = FALSE,
  memory = FALSE,
  filter_gc = FALSE
)

# ---- bench-build-hierarchical-linear ----
build_hierarchical_linear
bench_build_hierarchical_linear <- mark(
  build_hierarchical_linear(),
  iterations = bench_settings$build_calls,
  check = FALSE,
  memory = FALSE,
  filter_gc = FALSE
)

# ---- bench-build-eight-schools ----
build_eight_schools
bench_build_eight_schools <- mark(
  build_eight_schools(),
  iterations = bench_settings$build_calls,
  check = FALSE,
  memory = FALSE,
  filter_gc = FALSE
)

# ---- bench-opt ----
# opt() draws its starting values from R's random numbers, so each model's
# calls start from the same seed
# ---- bench-opt-linear ----
build_linear
linear_for_opt <- build_linear()
set.seed(session_seed)
bench_opt_linear <- mark(
  opt(linear_for_opt),
  iterations = bench_settings$opt_calls,
  check = FALSE,
  memory = FALSE,
  filter_gc = FALSE
)

# ---- bench-opt-multiple-linear ----
build_multiple_linear
multiple_linear_for_opt <- build_multiple_linear()
set.seed(session_seed)
bench_opt_multiple_linear <- mark(
  opt(multiple_linear_for_opt),
  iterations = bench_settings$opt_calls,
  check = FALSE,
  memory = FALSE,
  filter_gc = FALSE
)

# ---- bench-opt-hierarchical-linear ----
build_hierarchical_linear
hierarchical_linear_for_opt <- build_hierarchical_linear()
set.seed(session_seed)
bench_opt_hierarchical_linear <- mark(
  opt(hierarchical_linear_for_opt),
  iterations = bench_settings$opt_calls,
  check = FALSE,
  memory = FALSE,
  filter_gc = FALSE
)

# ---- bench-opt-eight-schools ----
build_eight_schools
eight_schools_for_opt <- build_eight_schools()
set.seed(session_seed)
bench_opt_eight_schools <- mark(
  opt(eight_schools_for_opt),
  iterations = bench_settings$opt_calls,
  check = FALSE,
  memory = FALSE,
  filter_gc = FALSE
)

# ---- bench-mcmc ----
# Both of a model's calls are on the same model: the first traces its
# TensorFlow functions and the second reuses them. Each `draws_` object keeps
# the second call's draws.

# ---- bench-mcmc-linear ----
build_linear
linear_for_mcmc <- build_linear()
set.seed(session_seed)
bench_mcmc_linear <- mark(
  draws_linear <- mcmc(
    linear_for_mcmc,
    warmup = bench_settings$warmup,
    n_samples = bench_settings$n_samples,
    chains = bench_settings$chains,
    n_cores = bench_settings$n_cores,
    verbose = FALSE
  ),
  iterations = bench_settings$mcmc_calls,
  check = FALSE,
  memory = FALSE,
  filter_gc = FALSE
)

# ---- bench-mcmc-multiple-linear ----
build_multiple_linear
multiple_linear_for_mcmc <- build_multiple_linear()
set.seed(session_seed)
bench_mcmc_multiple_linear <- mark(
  draws_multiple_linear <- mcmc(
    multiple_linear_for_mcmc,
    warmup = bench_settings$warmup,
    n_samples = bench_settings$n_samples,
    chains = bench_settings$chains,
    n_cores = bench_settings$n_cores,
    verbose = FALSE
  ),
  iterations = bench_settings$mcmc_calls,
  check = FALSE,
  memory = FALSE,
  filter_gc = FALSE
)

# ---- bench-mcmc-hierarchical-linear ----
build_hierarchical_linear
hierarchical_linear_for_mcmc <- build_hierarchical_linear()
set.seed(session_seed)
bench_mcmc_hierarchical_linear <- mark(
  draws_hierarchical_linear <- mcmc(
    hierarchical_linear_for_mcmc,
    warmup = bench_settings$warmup,
    n_samples = bench_settings$n_samples,
    chains = bench_settings$chains,
    n_cores = bench_settings$n_cores,
    verbose = FALSE
  ),
  iterations = bench_settings$mcmc_calls,
  check = FALSE,
  memory = FALSE,
  filter_gc = FALSE
)

# ---- bench-mcmc-eight-schools ----
build_eight_schools
eight_schools_for_mcmc <- build_eight_schools()
set.seed(session_seed)
bench_mcmc_eight_schools <- mark(
  draws_eight_schools <- mcmc(
    eight_schools_for_mcmc,
    warmup = bench_settings$warmup,
    n_samples = bench_settings$n_samples,
    chains = bench_settings$chains,
    n_cores = bench_settings$n_cores,
    verbose = FALSE
  ),
  iterations = bench_settings$mcmc_calls,
  check = FALSE,
  memory = FALSE,
  filter_gc = FALSE
)

# ---- mcmc-draws ----
# Every draw of every chain from each model's second call. A posterior draws
# array holds just the draws: the greta_mcmc_list mcmc() returns carries the
# model and its TensorFlow objects, which cannot be saved.
mcmc_draws <- list(
  linear = posterior::as_draws_array(draws_linear),
  multiple_linear = posterior::as_draws_array(draws_multiple_linear),
  hierarchical_linear = posterior::as_draws_array(draws_hierarchical_linear),
  eight_schools = posterior::as_draws_array(draws_eight_schools)
)

# ---- benchmark-provenance ----
session_info <- sessioninfo::session_info()
# greta_sitrep() reports through messages, so capture those
greta_sitrep_report <- utils::capture.output(greta_sitrep(), type = "message")

greta_sha <- packageDescription("greta")$RemoteSha
provenance <- data.frame(
  greta_version = as.character(packageVersion("greta")),
  greta_sha = if (is.null(greta_sha)) NA_character_ else greta_sha,
  r_version = paste(R.version$major, R.version$minor, sep = "."),
  tensorflow_version = tensorflow::tf$version$VERSION,
  tfp_version = reticulate::import("tensorflow_probability")$`__version__`,
  machine = paste(
    Sys.info()[c("sysname", "release", "machine")],
    collapse = " "
  ),
  cores = parallel::detectCores()
)

# ---- benchmark-results ----
# the value source() returns to run.R: every bench_mark object as mark() made
# it, and the summaries beside them
list(
  session_seed = session_seed,
  bench_settings = bench_settings,
  provenance = provenance,
  session_info = session_info,
  greta_sitrep_report = greta_sitrep_report,
  sampler_iterations_per_draw = sampler_iterations_per_draw,
  build = list(
    linear = bench_build_linear,
    multiple_linear = bench_build_multiple_linear,
    hierarchical_linear = bench_build_hierarchical_linear,
    eight_schools = bench_build_eight_schools
  ),
  opt = list(
    linear = bench_opt_linear,
    multiple_linear = bench_opt_multiple_linear,
    hierarchical_linear = bench_opt_hierarchical_linear,
    eight_schools = bench_opt_eight_schools
  ),
  mcmc = list(
    linear = bench_mcmc_linear,
    multiple_linear = bench_mcmc_multiple_linear,
    hierarchical_linear = bench_mcmc_hierarchical_linear,
    eight_schools = bench_mcmc_eight_schools
  ),
  mcmc_draws = mcmc_draws
)
