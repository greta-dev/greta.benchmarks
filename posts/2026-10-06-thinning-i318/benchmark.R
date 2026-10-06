# What each version of greta runs, in a fresh R session of its own: run.R
# sources it once per version per session, and keeps the list it ends with.
# Each `# ---- label ----` line starts a section that index.qmd shows by that
# label.
#
# Run it alone to try it against whichever greta is installed:
#
#   Rscript --quiet --vanilla posts/2026-10-06-thinning-i318/benchmark.R

# ---- benchmark-setup ----
library(greta)
library(bench)
session <- as.integer(Sys.getenv("GRETA_BENCH_SESSION", "1"))
session_seed <- 2026 - 10 - 6 + session

# ---- benchmark-settings ----
# warmup and n_samples are mcmc()'s arguments, so they count draws; mcmc_calls
# counts timed calls
bench_settings <- list(
  warmup = 1000,
  n_samples = 1000,
  chains = 4,
  n_cores = 4,
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
walk_model <- model(x)
iterations_per_draw <- function(thin) {
  walk <- mcmc(
    walk_model,
    sampler = rwmh(epsilon = step_sd, diag_sd = 1),
    warmup = 0,
    n_samples = 4000 * thin,
    thin = thin,
    chains = 1,
    initial_values = initials(x = 0),
    verbose = FALSE
  )
  round(var(diff(as.vector(walk[[1]]))) / step_sd^2)
}
sampler_iterations_per_draw <- data.frame(
  thin = c(1, 3),
  iterations_per_draw = c(iterations_per_draw(1), iterations_per_draw(3))
)

# ---- bench-mcmc-same ----
# The same warmup and n_samples on every version. Both of a model's calls are
# on the same model: the first traces its TensorFlow functions and the second
# reuses them. Each `draws_` object keeps the second call's draws.

# ---- bench-mcmc-same-linear ----
build_linear
linear_for_mcmc <- build_linear()
set.seed(session_seed)
bench_mcmc_same_linear <- mark(
  draws_same_linear <- mcmc(
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

# ---- bench-mcmc-same-multiple-linear ----
build_multiple_linear
multiple_linear_for_mcmc <- build_multiple_linear()
set.seed(session_seed)
bench_mcmc_same_multiple_linear <- mark(
  draws_same_multiple_linear <- mcmc(
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

# ---- bench-mcmc-same-hierarchical-linear ----
build_hierarchical_linear
hierarchical_linear_for_mcmc <- build_hierarchical_linear()
set.seed(session_seed)
bench_mcmc_same_hierarchical_linear <- mark(
  draws_same_hierarchical_linear <- mcmc(
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

# ---- bench-mcmc-same-eight-schools ----
build_eight_schools
eight_schools_for_mcmc <- build_eight_schools()
set.seed(session_seed)
bench_mcmc_same_eight_schools <- mark(
  draws_same_eight_schools <- mcmc(
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

# ---- bench-mcmc-defaults ----
# Each version's own default warmup and n_samples: 1000 each on CRAN and main,
# 2000 each on #850. Each model is built afresh, so the first call traces again.

# ---- bench-mcmc-defaults-linear ----
build_linear
linear_for_defaults <- build_linear()
set.seed(session_seed)
bench_mcmc_defaults_linear <- mark(
  draws_defaults_linear <- mcmc(
    linear_for_defaults,
    chains = bench_settings$chains,
    n_cores = bench_settings$n_cores,
    verbose = FALSE
  ),
  iterations = bench_settings$mcmc_calls,
  check = FALSE,
  memory = FALSE,
  filter_gc = FALSE
)

# ---- bench-mcmc-defaults-multiple-linear ----
build_multiple_linear
multiple_linear_for_defaults <- build_multiple_linear()
set.seed(session_seed)
bench_mcmc_defaults_multiple_linear <- mark(
  draws_defaults_multiple_linear <- mcmc(
    multiple_linear_for_defaults,
    chains = bench_settings$chains,
    n_cores = bench_settings$n_cores,
    verbose = FALSE
  ),
  iterations = bench_settings$mcmc_calls,
  check = FALSE,
  memory = FALSE,
  filter_gc = FALSE
)

# ---- bench-mcmc-defaults-hierarchical-linear ----
build_hierarchical_linear
hierarchical_linear_for_defaults <- build_hierarchical_linear()
set.seed(session_seed)
bench_mcmc_defaults_hierarchical_linear <- mark(
  draws_defaults_hierarchical_linear <- mcmc(
    hierarchical_linear_for_defaults,
    chains = bench_settings$chains,
    n_cores = bench_settings$n_cores,
    verbose = FALSE
  ),
  iterations = bench_settings$mcmc_calls,
  check = FALSE,
  memory = FALSE,
  filter_gc = FALSE
)

# ---- bench-mcmc-defaults-eight-schools ----
build_eight_schools
eight_schools_for_defaults <- build_eight_schools()
set.seed(session_seed)
bench_mcmc_defaults_eight_schools <- mark(
  draws_defaults_eight_schools <- mcmc(
    eight_schools_for_defaults,
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
  same = list(
    linear = posterior::as_draws_array(draws_same_linear),
    multiple_linear = posterior::as_draws_array(draws_same_multiple_linear),
    hierarchical_linear = posterior::as_draws_array(
      draws_same_hierarchical_linear
    ),
    eight_schools = posterior::as_draws_array(draws_same_eight_schools)
  ),
  defaults = list(
    linear = posterior::as_draws_array(draws_defaults_linear),
    multiple_linear = posterior::as_draws_array(
      draws_defaults_multiple_linear
    ),
    hierarchical_linear = posterior::as_draws_array(
      draws_defaults_hierarchical_linear
    ),
    eight_schools = posterior::as_draws_array(draws_defaults_eight_schools)
  )
)

# ---- calls-that-errored ----
# The combinations of n_samples, thin, pb_update and one_by_one reported in
# greta#241, #318, #567 and #609, run after the timed calls so an error cannot
# disturb them. verbose = TRUE where pb_update matters, since sampling runs in
# bursts of pb_update iterations only while the progress bar is shown.
u <- uniform(0, 1)
uniform_model <- model(u)
set.seed(session_seed)
uniform_draws <- mcmc(
  uniform_model,
  n_samples = 30,
  warmup = 10,
  chains = 1,
  verbose = FALSE
)
sampling_calls <- list(
  "last burst shorter than thin (#609)" = function() {
    mcmc(
      uniform_model,
      n_samples = 1000,
      warmup = 10,
      thin = 100,
      pb_update = 101,
      chains = 1,
      verbose = TRUE
    )
  },
  "pb_update below thin (#318)" = function() {
    mcmc(
      uniform_model,
      n_samples = 100,
      warmup = 10,
      thin = 3,
      pb_update = 2,
      chains = 1,
      verbose = TRUE
    )
  },
  "one_by_one with thin (#567)" = function() {
    mcmc(
      uniform_model,
      n_samples = 30,
      warmup = 10,
      thin = 2,
      pb_update = 50,
      one_by_one = TRUE,
      chains = 1,
      verbose = TRUE
    )
  },
  "extra_samples() with thin (#567)" = function() {
    extra_samples(
      uniform_draws,
      n_samples = 202,
      thin = 3,
      pb_update = 50,
      verbose = TRUE
    )
  },
  "thin larger than n_samples (#241)" = function() {
    mcmc(
      uniform_model,
      n_samples = 10,
      warmup = 20,
      thin = 20,
      chains = 1,
      verbose = FALSE
    )
  }
)
# the draws each call kept per chain, or the first line of its error
call_outcome <- function(sample) {
  tryCatch(
    paste(coda::niter(sample()), "draws"),
    error = function(error) {
      paste("error:", strsplit(conditionMessage(error), "\n")[[1]][1])
    }
  )
}
set.seed(session_seed)
calls_that_errored <- data.frame(
  call = names(sampling_calls),
  draws_documented = c(1000 %/% 100, 100 %/% 3, 30 %/% 2, 30 + 202 %/% 3, NA),
  outcome = vapply(sampling_calls, call_outcome, character(1)),
  row.names = NULL
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
  calls_that_errored = calls_that_errored,
  mcmc_same = list(
    linear = bench_mcmc_same_linear,
    multiple_linear = bench_mcmc_same_multiple_linear,
    hierarchical_linear = bench_mcmc_same_hierarchical_linear,
    eight_schools = bench_mcmc_same_eight_schools
  ),
  mcmc_defaults = list(
    linear = bench_mcmc_defaults_linear,
    multiple_linear = bench_mcmc_defaults_multiple_linear,
    hierarchical_linear = bench_mcmc_defaults_hierarchical_linear,
    eight_schools = bench_mcmc_defaults_eight_schools
  ),
  mcmc_draws = mcmc_draws
)
