# What each version of greta runs, in a fresh R session of its own: run.R
# sources it once per version per session, and keeps the list it ends with.
# Each `# ---- label ----` line starts a section that index.qmd shows by that
# label.
#
# Run it alone to try it against whichever greta is installed:
#
#   Rscript --quiet --vanilla posts/2026-10-07-tf-warmup-i547/benchmark.R

# ---- benchmark-setup ----
library(greta)
library(bench)
session <- as.integer(Sys.getenv("GRETA_BENCH_SESSION", "1"))
session_seed <- 2026 - 10 - 7 + session

# ---- benchmark-settings ----
# warmup and n_samples are mcmc()'s arguments, so they count draws; the
# *_calls settings count timed calls; scaling_chains are the numbers of chains
# the chain-count section runs
bench_settings <- list(
  warmup = 1000,
  n_samples = 1000,
  chains = 4,
  n_cores = 4,
  mcmc_calls = 2,
  opt_calls = 3,
  opt_max_iterations = 2000,
  scaling_chains = c(4, 16, 64)
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
# 2000 each on #850 and the branch. Each model is built afresh, so the first
# call traces again.

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

# ---- bench-opt-adam ----
# opt() with adam(), whose whole loop the branch runs in one call to
# TensorFlow, where the other versions return to R after every iteration. Each
# model's calls start from the same seed

# ---- bench-opt-adam-linear ----
build_linear
linear_for_opt <- build_linear()
set.seed(session_seed)
bench_opt_adam_linear <- mark(
  opt(
    linear_for_opt,
    optimiser = adam(),
    max_iterations = bench_settings$opt_max_iterations
  ),
  iterations = bench_settings$opt_calls,
  check = FALSE,
  memory = FALSE,
  filter_gc = FALSE
)

# ---- bench-opt-adam-multiple-linear ----
build_multiple_linear
multiple_linear_for_opt <- build_multiple_linear()
set.seed(session_seed)
bench_opt_adam_multiple_linear <- mark(
  opt(
    multiple_linear_for_opt,
    optimiser = adam(),
    max_iterations = bench_settings$opt_max_iterations
  ),
  iterations = bench_settings$opt_calls,
  check = FALSE,
  memory = FALSE,
  filter_gc = FALSE
)

# ---- bench-opt-adam-hierarchical-linear ----
build_hierarchical_linear
hierarchical_linear_for_opt <- build_hierarchical_linear()
set.seed(session_seed)
bench_opt_adam_hierarchical_linear <- mark(
  opt(
    hierarchical_linear_for_opt,
    optimiser = adam(),
    max_iterations = bench_settings$opt_max_iterations
  ),
  iterations = bench_settings$opt_calls,
  check = FALSE,
  memory = FALSE,
  filter_gc = FALSE
)

# ---- bench-opt-adam-eight-schools ----
build_eight_schools
eight_schools_for_opt <- build_eight_schools()
set.seed(session_seed)
bench_opt_adam_eight_schools <- mark(
  opt(
    eight_schools_for_opt,
    optimiser = adam(),
    max_iterations = bench_settings$opt_max_iterations
  ),
  iterations = bench_settings$opt_calls,
  check = FALSE,
  memory = FALSE,
  filter_gc = FALSE
)

# ---- bench-chains ----
# mcmc() with each version's defaults on 4, 16 and 64 chains
# (greta-dev/greta#294), twice for each: the first call on a new model traces,
# the second reuses the trace. Each keeps the smallest and median bulk ESS of
# its draws rather than the draws, which would be large to save at 64 chains.
draws_ess <- function(draws) {
  summary <- posterior::summarise_draws(
    posterior::as_draws_array(draws),
    "ess_bulk"
  )
  data.frame(
    smallest_ess_bulk = min(summary$ess_bulk),
    median_ess_bulk = stats::median(summary$ess_bulk)
  )
}

# ---- bench-chains-linear ----
build_linear
chains_ess_linear <- list()
bench_chains_linear <- press(
  chains = bench_settings$scaling_chains,
  {
    linear_for_chains <- build_linear()
    set.seed(session_seed)
    marks <- mark(
      draws_chains <- mcmc(
        linear_for_chains,
        chains = chains,
        n_cores = bench_settings$n_cores,
        verbose = FALSE
      ),
      iterations = bench_settings$mcmc_calls,
      check = FALSE,
      memory = FALSE,
      filter_gc = FALSE
    )
    # press() evaluates this in an environment of its own, so the ESS goes
    # to the list outside it
    chains_ess_linear[[length(chains_ess_linear) + 1]] <<-
      data.frame(chains = chains, draws_ess(draws_chains))
    marks
  }
)

# ---- bench-chains-eight-schools ----
build_eight_schools
chains_ess_eight_schools <- list()
bench_chains_eight_schools <- press(
  chains = bench_settings$scaling_chains,
  {
    eight_schools_for_chains <- build_eight_schools()
    set.seed(session_seed)
    marks <- mark(
      draws_chains <- mcmc(
        eight_schools_for_chains,
        chains = chains,
        n_cores = bench_settings$n_cores,
        verbose = FALSE
      ),
      iterations = bench_settings$mcmc_calls,
      check = FALSE,
      memory = FALSE,
      filter_gc = FALSE
    )
    # press() evaluates this in an environment of its own, so the ESS goes
    # to the list outside it
    chains_ess_eight_schools[[length(chains_ess_eight_schools) + 1]] <<-
      data.frame(chains = chains, draws_ess(draws_chains))
    marks
  }
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
  opt_adam = list(
    linear = bench_opt_adam_linear,
    multiple_linear = bench_opt_adam_multiple_linear,
    hierarchical_linear = bench_opt_adam_hierarchical_linear,
    eight_schools = bench_opt_adam_eight_schools
  ),
  chains = list(
    linear = bench_chains_linear,
    eight_schools = bench_chains_eight_schools
  ),
  chains_ess = list(
    linear = do.call(rbind, chains_ess_linear),
    eight_schools = do.call(rbind, chains_ess_eight_schools)
  ),
  mcmc_draws = mcmc_draws
)
