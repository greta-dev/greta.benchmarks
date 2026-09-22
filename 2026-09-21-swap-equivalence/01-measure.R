# Does swapping data sample the same distribution as rebuilding the graph?
#
#   Rscript --quiet --vanilla 2026-09-21-swap-equivalence/01-measure.R
#
# greta-dev/greta#739 replaces the Geweke loop's per-iteration rebuild
#
#   dag$tf_log_prob_function <- NULL; dag$define_tf_log_prob_function(); ...
#
# with dag$set_data_value(). That made the checks about 42x faster, which is
# large enough to suspect the loop stopped doing the work: if the swap never
# reached the sampler, the chain would sample against a frozen x, run fast, and
# still produce a plausible-looking vector of draws.
#
# A timing comparison cannot see that, and neither can checking the type of the
# output. This compares the draws themselves.
#
# The Geweke construction is what makes the check sharp: if the sampler and the
# data-generating step are both correct, theta comes out distributed as its
# prior, whatever path the data took to get there. So there are two questions,
# and the second is the one that matters:
#
#   1. do the two loops agree with each other?
#   2. does each agree with the prior it should reproduce?
#
# A frozen x would fail (2) conspicuously: theta would concentrate on the
# posterior given that one dataset instead of spreading over the prior.
#
# Both loops run from the same seed, so the R-side draws (theta[1], and each
# x | theta) are drawn from the same stream and the comparison is of the two
# graph paths rather than of two different random runs.

library(here)
library(fs)

run_dir <- here("2026-09-21-swap-equivalence")
greta_repo <- path_expand(Sys.getenv("GRETA_REPO", "~/github/greta-dev/greta"))

niter <- as.integer(Sys.getenv("GRETA_SWAP_NITER", "500"))
seed <- 2026 - 09 - 21

suppressMessages(pkgload::load_all(greta_repo, quiet = TRUE))

n <- 10

# the model, rebuilt per loop so neither inherits the other's graph
build <- function() {
  x <- as_data(rep(0, n))
  greta_theta <- normal(mu1, sd1)
  distribution(x) <- normal(greta_theta, sd2)
  list(model = model(greta_theta, precision = "single"), data = x)
}

# one Gibbs loop, with `advance` deciding how the new data reaches the graph
gibbs <- function(niter, advance) {
  set.seed(seed)
  built <- build()
  draws <- mcmc(
    built$model,
    warmup = 1000,
    n_samples = 1,
    chains = 1,
    verbose = FALSE
  )

  theta <- rep(NA_real_, niter)
  theta[1] <- rnorm(1, mu1, sd1)

  for (i in 2:niter) {
    x <- rnorm(n, theta[i - 1], sd2)
    advance(built, x, draws)
    draws <- extra_samples(draws, n_samples = 1, verbose = FALSE)
    theta[i] <- tail(as.numeric(draws[[1]]), 1)
  }
  theta
}

# both calls, as helpers.R had them. Rebuilding only the log prob leaves the
# sampler on its stale traced graph, so the chain samples against frozen data
# -- which looks like a working loop and is not one
rebuild <- function(built, x, draws) {
  dag <- built$model$dag
  get_node(built$data)$value(as.matrix(x))
  dag$tf_log_prob_function <- NULL
  dag$define_tf_log_prob_function()
  attr(draws, "model_info")$samplers[[1]]$define_tf_evaluate_sample_batch()
}

swap <- function(built, x, draws) {
  dag <- built$model$dag
  get_node(built$data)$value(as.matrix(x))
  dag$set_data_value(built$data, as.matrix(x))
}

# the model constants, drawn once so both loops target the same prior
set.seed(seed)
mu1 <- rnorm(1, 0, 3)
sd1 <- rlnorm(1)
sd2 <- rlnorm(1)

theta_rebuild <- gibbs(niter, rebuild)
theta_swap <- gibbs(niter, swap)

# what theta should look like if the whole construction is correct
prior <- rnorm(niter, mu1, sd1)

ks <- function(a, b) suppressWarnings(stats::ks.test(a, b))

comparisons <- data.frame(
  comparison = c("rebuild vs swap", "rebuild vs prior", "swap vs prior"),
  statistic = c(
    ks(theta_rebuild, theta_swap)$statistic,
    ks(theta_rebuild, prior)$statistic,
    ks(theta_swap, prior)$statistic
  ),
  p_value = c(
    ks(theta_rebuild, theta_swap)$p.value,
    ks(theta_rebuild, prior)$p.value,
    ks(theta_swap, prior)$p.value
  )
)

summaries <- data.frame(
  series = c("rebuild", "swap", "prior"),
  mean = c(mean(theta_rebuild), mean(theta_swap), mean(prior)),
  sd = c(sd(theta_rebuild), sd(theta_swap), sd(prior))
)

cat("\nmodel: theta ~ normal(", round(mu1, 3), ",", round(sd1, 3), ")\n")
cat("niter:", niter, "\n\n")
print(summaries, row.names = FALSE, digits = 4)
cat("\n")
print(comparisons, row.names = FALSE, digits = 4)

saveRDS(
  list(
    theta_rebuild = theta_rebuild,
    theta_swap = theta_swap,
    prior = prior,
    comparisons = comparisons,
    summaries = summaries,
    niter = niter,
    seed = seed,
    model = list(mu1 = mu1, sd1 = sd1, sd2 = sd2, n = n),
    sha = system2(
      "git",
      c("-C", shQuote(greta_repo), "rev-parse", "HEAD"),
      stdout = TRUE
    )
  ),
  path(run_dir, "results.rds"),
  compress = "xz"
)

cat("\nwrote", path(run_dir, "results.rds"), "\n")
