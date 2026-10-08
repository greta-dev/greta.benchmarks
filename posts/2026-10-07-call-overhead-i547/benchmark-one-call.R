# A closer look at mcmc() with verbose = FALSE, in one call to TensorFlow per
# phase, which benchmark.R found 1% to 3% slower on the branch than on the
# earlier commit. What each version runs, in a fresh R session of its own:
# run-one-call.R sources it once per version per session, and keeps the list
# it ends with. Each `# ---- label ----` line starts a section that index.qmd
# shows by that label.
#
#   Rscript --quiet --vanilla posts/2026-10-07-call-overhead-i547/benchmark-one-call.R

# ---- one-call-setup ----
library(greta)
library(bench)
session <- as.integer(Sys.getenv("GRETA_BENCH_SESSION", "1"))
session_seed <- 2026 - 10 - 7 + session

# ---- one-call-settings ----
# warmup and n_samples are mcmc()'s arguments, so they count draws; mcmc_calls
# counts timed calls on each model, the first of which traces
one_call_settings <- list(
  chains = 4,
  warmup = 1000,
  n_samples = 1000,
  mcmc_calls = 10
)

# ---- one-call-models ----
build_linear <- function() {
  int <- normal(0, 10)
  coef <- normal(0, 10)
  sd <- cauchy(0, 3, truncation = c(0, Inf))
  mu <- int + coef * attitude$complaints
  distribution(attitude$rating) <- normal(mu, sd)
  model(int, coef, sd)
}

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

# ---- one-call-mcmc ----
bench_one_call <- function(build) {
  m <- build()
  set.seed(session_seed)
  mark(
    mcmc(
      m,
      warmup = one_call_settings$warmup,
      n_samples = one_call_settings$n_samples,
      chains = one_call_settings$chains,
      verbose = FALSE
    ),
    iterations = one_call_settings$mcmc_calls,
    check = FALSE,
    memory = FALSE,
    filter_gc = FALSE
  )
}

linear_one_call <- bench_one_call(build_linear)
hierarchical_linear_one_call <- bench_one_call(build_hierarchical_linear)

# ---- one-call-results ----
# the value source() returns to run-one-call.R
list(
  session_seed = session_seed,
  one_call_settings = one_call_settings,
  greta_version = as.character(packageVersion("greta")),
  mcmc = list(
    linear = linear_one_call,
    hierarchical_linear = hierarchical_linear_one_call
  )
)
