# What each version of greta runs, in a fresh R session of its own: run.R
# sources it once per version per session, and keeps the list it ends with.
# Each `# ---- label ----` line starts a section that index.qmd shows by that
# label.
#
# Run it alone to try it against whichever greta is installed:
#
#   Rscript --quiet --vanilla posts/2026-10-07-call-overhead-i547/benchmark.R

# ---- benchmark-setup ----
library(greta)
library(bench)
session <- as.integer(Sys.getenv("GRETA_BENCH_SESSION", "1"))
session_seed <- 2026 - 10 - 7 + session

# ---- benchmark-settings ----
# warmup and n_samples are mcmc()'s arguments, so they count draws, and the
# one_by_one_* settings are those of the one_by_one calls; opt_max_iterations
# are the iteration limits opt() is timed at; the *_calls settings count timed
# calls
bench_settings <- list(
  chains = 4,
  warmup = 1000,
  n_samples = 1000,
  one_by_one_warmup = 200,
  one_by_one_n_samples = 200,
  mcmc_calls = 4,
  opt_max_iterations = c(20L, 2000L),
  opt_calls = 6
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

# ---- benchmark-mcmc ----
# mcmc() on a model built afresh, mcmc_calls times: the first call traces its
# TensorFlow functions and later calls reuse them. Three ways of running it,
# which differ in how often the sampler returns to R:
#
# - one_by_one: once every iteration
# - progress: every pb_update iterations, to update the progress bar, as
#   mcmc() does by default
# - one call: once per phase, with verbose = FALSE
bench_mcmc <- function(build) {
  run_with <- function(...) {
    m <- build()
    set.seed(session_seed)
    mark(
      mcmc(m, chains = bench_settings$chains, ...),
      iterations = bench_settings$mcmc_calls,
      check = FALSE,
      memory = FALSE,
      filter_gc = FALSE
    )
  }
  list(
    one_by_one = run_with(
      warmup = bench_settings$one_by_one_warmup,
      n_samples = bench_settings$one_by_one_n_samples,
      one_by_one = TRUE,
      verbose = FALSE
    ),
    progress = run_with(
      warmup = bench_settings$warmup,
      n_samples = bench_settings$n_samples
    ),
    one_call = run_with(
      warmup = bench_settings$warmup,
      n_samples = bench_settings$n_samples,
      verbose = FALSE
    )
  )
}

# ---- benchmark-opt ----
# opt() with adam() on a model built afresh for each iteration limit,
# opt_calls times: the first call on a model traces its loop, and later calls
# may reuse it
bench_opt <- function(build) {
  press(
    max_iterations = bench_settings$opt_max_iterations,
    {
      m <- build()
      set.seed(session_seed)
      mark(
        opt(m, optimiser = adam(), max_iterations = max_iterations),
        iterations = bench_settings$opt_calls,
        check = FALSE,
        memory = FALSE,
        filter_gc = FALSE
      )
    }
  )
}

# ---- bench-linear ----
linear_mcmc <- bench_mcmc(build_linear)
linear_opt <- bench_opt(build_linear)

# ---- bench-hierarchical-linear ----
hierarchical_linear_mcmc <- bench_mcmc(build_hierarchical_linear)
hierarchical_linear_opt <- bench_opt(build_hierarchical_linear)

# ---- benchmark-provenance ----
session_info <- sessioninfo::session_info()
# greta_sitrep() reports through messages, so capture those
greta_sitrep_report <- utils::capture.output(greta_sitrep(), type = "message")
tf <- tensorflow::tf
tfp <- reticulate::import("tensorflow_probability")

provenance <- data.frame(
  greta_version = as.character(packageVersion("greta")),
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

# ---- benchmark-results ----
# the value source() returns to run.R: every bench_mark object as mark() and
# press() made it
list(
  session_seed = session_seed,
  bench_settings = bench_settings,
  provenance = provenance,
  session_info = session_info,
  greta_sitrep_report = greta_sitrep_report,
  mcmc = list(
    linear = linear_mcmc,
    hierarchical_linear = hierarchical_linear_mcmc
  ),
  opt = list(
    linear = linear_opt,
    hierarchical_linear = hierarchical_linear_opt
  )
)
