# What each version of greta runs, in a fresh R session of its own: run.R
# sources it once per version per session, and keeps the list it ends with.
#
# Each `# ---- label ----` line starts a section. The post shows each one by
# its label, links to it under the figure it fed, and builds that figure's
# "Run it yourself" block from `setup` and the figure's own section. So keep
# every timed section self-contained: it builds its own model and reads only
# `setup`'s settings, so that `setup` plus that one section run on their own.
#
# Run it alone to try it against whichever greta is installed:
#
#   Rscript --quiet --vanilla posts/2026-10-13-tuning-efficiency-i547/benchmark.R

# ---- setup ----
library(greta)
library(bench)
session <- as.integer(Sys.getenv("GRETA_BENCH_SESSION", "1"))
# the date the post was started, as a seed
session_seed <- 2026 - 10 - 13 + session
# mcmc() runs with each version's own default warmup and n_samples.
# mcmc_calls counts timed calls on one model, the first of which traces
settings <- list(
  chains = 4,
  mcmc_calls = 2
)

# Times mcmc() on a model, and keeps the last call's draws and the epsilon and
# diag_sd that warmup tuned hmc() to
time_mcmc <- function(m) {
  set.seed(session_seed)
  marks <- mark(
    draws <- mcmc(m, chains = settings$chains, verbose = FALSE),
    iterations = settings$mcmc_calls,
    check = FALSE,
    memory = FALSE,
    filter_gc = FALSE
  )
  tuned <- attr(draws, "model_info")$samplers[[1]]$parameters
  list(
    marks = marks,
    draws = posterior::as_draws_array(draws),
    epsilon = tuned$epsilon,
    diag_sd = as.numeric(tuned$diag_sd)
  )
}

# ---- sampler-iterations ----
# A random walk on a target far wider than its steps accepts every proposal, so
# the variance between kept draws over one step's variance counts the sampler
# iterations between them. It is also the session's first mcmc() call, so
# TensorFlow's start-up costs fall here rather than on the first model
sampler_iterations_per_draw <- local({
  step_sd <- 0.1
  x <- normal(0, 1e6)
  m <- model(x)
  walk <- mcmc(
    m,
    sampler = rwmh(epsilon = step_sd, diag_sd = 1),
    warmup = 0,
    n_samples = 4000,
    chains = 1,
    initial_values = initials(x = 0),
    verbose = FALSE
  )
  round(var(diff(as.vector(walk[[1]]))) / step_sd^2)
})

# ---- mcmc-linear ----
# greta's linear example: the rating of each department in `attitude`
# regressed on its complaints
mcmc_linear <- local({
  int <- normal(0, 10)
  coef <- normal(0, 10)
  sd <- cauchy(0, 3, truncation = c(0, Inf))
  mu <- int + coef * attitude$complaints
  distribution(attitude$rating) <- normal(mu, sd)
  m <- model(int, coef, sd)
  time_mcmc(m)
})

# ---- mcmc-multiple-linear ----
# the same rating on all six of `attitude`'s other columns
mcmc_multiple_linear <- local({
  design <- as.matrix(attitude[, 2:7])
  int <- normal(0, 10)
  coefs <- normal(0, 10, dim = ncol(design))
  sd <- cauchy(0, 3, truncation = c(0, Inf))
  mu <- int + design %*% coefs
  distribution(attitude$rating) <- normal(mu, sd)
  m <- model(int, coefs, sd)
  time_mcmc(m)
})

# ---- mcmc-hierarchical-linear ----
# sepal length on sepal width in `iris`, with an offset for each species
mcmc_hierarchical_linear <- local({
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
  time_mcmc(m)
})

# ---- mcmc-eight-schools ----
# the effect of coaching in eight schools, each measured with a known
# standard error
mcmc_eight_schools <- local({
  y <- c(28, 8, -3, 7, -1, 1, 18, 12)
  sigma_y <- c(15, 10, 16, 11, 9, 11, 10, 18)
  sigma_eta <- inverse_gamma(1, 1)
  eta <- normal(0, sigma_eta, dim = 8)
  mu_theta <- normal(0, 100)
  xi <- normal(0, 5)
  theta <- mu_theta + xi * eta
  distribution(y) <- normal(theta, sigma_y)
  m <- model(sigma_eta, eta, mu_theta, xi)
  time_mcmc(m)
})

# ---- provenance ----
session_info <- sessioninfo::session_info()
# greta_sitrep() reports through messages, so capture those
greta_sitrep_report <- utils::capture.output(greta_sitrep(), type = "message")
tf <- tensorflow::tf
tfp <- reticulate::import("tensorflow_probability")
greta_sha <- packageDescription("greta")$RemoteSha
provenance <- data.frame(
  greta_version = as.character(packageVersion("greta")),
  greta_sha = if (is.null(greta_sha)) NA_character_ else greta_sha,
  r_version = paste(R.version$major, R.version$minor, sep = "."),
  tensorflow_version = tf$version$VERSION,
  tfp_version = tfp$`__version__`,
  reticulate_version = as.character(packageVersion("reticulate")),
  machine = paste(
    Sys.info()[c("sysname", "release", "machine")],
    collapse = " "
  ),
  cores = parallel::detectCores()
)

# ---- results ----
# the value source() returns to run.R: every bench_mark object as mark() made
# it, so summary() and autoplot() work on it, with each run's draws and tuned
# values beside it
list(
  session_seed = session_seed,
  settings = settings,
  provenance = provenance,
  session_info = session_info,
  greta_sitrep_report = greta_sitrep_report,
  sampler_iterations_per_draw = sampler_iterations_per_draw,
  mcmc = list(
    linear = mcmc_linear,
    multiple_linear = mcmc_multiple_linear,
    hierarchical_linear = mcmc_hierarchical_linear,
    eight_schools = mcmc_eight_schools
  )
)
