# Does swapping data without a retrace make the Geweke loop faster?
#
#   Rscript --quiet --vanilla 2026-09-20-geweke-data-swap/01-measure.R
#
# greta's Geweke check runs a Gibbs loop: draw x given theta, then advance the
# chain one step under the new x. Changing x currently means rebuilding the log
# prob tf_function and the sampler's traced step, once per iteration:
#
#   dag$tf_log_prob_function <- NULL
#   dag$define_tf_log_prob_function()
#   sampler$define_tf_evaluate_sample_batch()
#
# That is the cost greta-dev/greta#739 is about, and why the checks take ~33
# minutes for three samplers. Backing data nodes with tf$Variable lets the same
# loop call dag$set_data_value() instead, which retraces nothing.
#
# Both variants run here, on the same model and iteration count, so the
# comparison is of the two loops rather than of two machines or two days.

library(here)
library(fs)

run_dir <- here("2026-09-20-geweke-data-swap")
greta_repo <- path_expand(Sys.getenv("GRETA_REPO", "~/github/greta-dev/greta"))

# how many Gibbs iterations to time. The real check uses 2000; the per-iteration
# cost is what matters and it is flat, so a short run measures the same thing
niter <- as.integer(Sys.getenv("GRETA_GEWEKE_NITER", "50"))

suppressMessages(pkgload::load_all(greta_repo, quiet = TRUE))

set.seed(2026 - 09 - 20)

n <- 10
mu1 <- rnorm(1, 0, 3)
sd1 <- rlnorm(1)
sd2 <- rlnorm(1)

p_x_bar_theta <- function(theta) rnorm(n, theta, sd2)

build <- function() {
  x <- as_data(rep(0, n))
  greta_theta <- normal(mu1, sd1)
  distribution(x) <- normal(greta_theta, sd2)
  list(model = model(greta_theta, precision = "single"), data = x)
}

# the loop as it stands: rebuild the traced functions on every iteration
gibbs_rebuild <- function(niter) {
  built <- build()
  draws <- mcmc(
    built$model,
    warmup = 100,
    n_samples = 1,
    chains = 1,
    verbose = FALSE
  )
  theta <- rep(NA, niter)
  theta[1] <- rnorm(1, mu1, sd1)

  for (i in 2:niter) {
    x <- p_x_bar_theta(theta[i - 1])
    dag <- built$model$dag
    get_node(built$data)$value(as.matrix(x))

    dag$tf_log_prob_function <- NULL
    dag$define_tf_log_prob_function()
    attr(draws, "model_info")$samplers[[1]]$define_tf_evaluate_sample_batch()

    draws <- extra_samples(draws, n_samples = 1, verbose = FALSE)
    theta[i] <- tail(as.numeric(draws[[1]]), 1)
  }
  theta
}

# the same loop, swapping the value behind the data node instead
gibbs_swap <- function(niter) {
  built <- build()
  draws <- mcmc(
    built$model,
    warmup = 100,
    n_samples = 1,
    chains = 1,
    verbose = FALSE
  )
  theta <- rep(NA, niter)
  theta[1] <- rnorm(1, mu1, sd1)

  for (i in 2:niter) {
    x <- p_x_bar_theta(theta[i - 1])
    dag <- built$model$dag
    get_node(built$data)$value(as.matrix(x))
    dag$set_data_value(built$data, as.matrix(x))

    draws <- extra_samples(draws, n_samples = 1, verbose = FALSE)
    theta[i] <- tail(as.numeric(draws[[1]]), 1)
  }
  theta
}

time_it <- function(f, label) {
  elapsed <- system.time(theta <- f(niter))[["elapsed"]]
  cat(sprintf(
    "%-10s %6.1f s for %d iterations  (%.3f s/iter)\n",
    label,
    elapsed,
    niter,
    elapsed / niter
  ))
  data.frame(
    variant = label,
    niter = niter,
    elapsed = elapsed,
    per_iter = elapsed / niter,
    theta_mean = mean(theta),
    theta_sd = sd(theta)
  )
}

results <- rbind(
  time_it(gibbs_rebuild, "rebuild"),
  time_it(gibbs_swap, "swap")
)

speedup <- results$per_iter[1] / results$per_iter[2]
cat(sprintf("\nswap is %.1fx faster per iteration\n", speedup))

saveRDS(
  list(
    results = results,
    speedup = speedup,
    niter = niter,
    sha = system2(
      "git",
      c("-C", shQuote(greta_repo), "rev-parse", "HEAD"),
      stdout = TRUE
    ),
    model = list(mu1 = mu1, sd1 = sd1, sd2 = sd2, n = n)
  ),
  path(run_dir, "results.rds"),
  compress = "xz"
)

cat("wrote", path(run_dir, "results.rds"), "\n")
