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
#   Rscript --quiet --vanilla posts/YYYY-MM-DD-short-name-iNNN/benchmark.R

# ---- setup ----
library(greta)
library(bench)
session <- as.integer(Sys.getenv("GRETA_BENCH_SESSION", "1"))
# the date the post was started, as a seed
session_seed <- 2026 - 01 - 01 + session
# warmup and n_samples are mcmc()'s arguments, so they count draws, and the
# *_calls settings count timed calls on one model, the first of which traces.
# FIXME: warmup and n_samples are placeholders until a pilot finds how many
# each model needs to converge (R-hat below 1.01, bulk ESS above 400) on every
# version
settings <- list(
  chains = 4,
  warmup = 1000,
  n_samples = 1000,
  mcmc_calls = 4,
  opt_iterations = 2000,
  opt_calls = 6
)

# ---- mcmc-linear ----
# mcmc() on greta's linear example: the rating of each department in
# `attitude` regressed on its complaints
mcmc_linear <- local({
  int <- normal(0, 10)
  coef <- normal(0, 10)
  sd <- cauchy(0, 3, truncation = c(0, Inf))
  mu <- int + coef * attitude$complaints
  distribution(attitude$rating) <- normal(mu, sd)
  m <- model(int, coef, sd)
  set.seed(session_seed)
  mark(
    mcmc(
      m,
      warmup = settings$warmup,
      n_samples = settings$n_samples,
      chains = settings$chains,
      verbose = FALSE
    ),
    iterations = settings$mcmc_calls,
    check = FALSE,
    memory = FALSE,
    filter_gc = FALSE
  )
})

# ---- opt-linear ----
# opt() with adam() on the same model, built afresh so that its first call
# traces
opt_linear <- local({
  int <- normal(0, 10)
  coef <- normal(0, 10)
  sd <- cauchy(0, 3, truncation = c(0, Inf))
  mu <- int + coef * attitude$complaints
  distribution(attitude$rating) <- normal(mu, sd)
  m <- model(int, coef, sd)
  set.seed(session_seed)
  mark(
    opt(m, optimiser = adam(), max_iterations = settings$opt_iterations),
    iterations = settings$opt_calls,
    check = FALSE,
    memory = FALSE,
    filter_gc = FALSE
  )
})

# ---- provenance ----
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
  machine = paste(Sys.info()[c("sysname", "release", "machine")], collapse = " "),
  cores = parallel::detectCores()
)

# ---- results ----
# the value source() returns to run.R: every bench_mark object as mark() made
# it, so summary() and autoplot() work on it
list(
  session_seed = session_seed,
  settings = settings,
  provenance = provenance,
  session_info = session_info,
  greta_sitrep_report = greta_sitrep_report,
  mcmc = list(linear = mcmc_linear),
  opt = list(linear = opt_linear)
)
