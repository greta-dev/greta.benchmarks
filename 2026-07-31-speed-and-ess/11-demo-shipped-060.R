# Demonstration: greta 0.6.0, as shipped, fails to converge on a standard
# Gaussian in roughly 1 run out of 10.
#
# Self-contained. Uses `library(greta)` and greta's own default Python
# resolution -- no worktrees, no pkgload, no custom TF environment. This is
# what a user gets from a normal install.
#
#   Rscript 11-demo-shipped-060.R
#
# The model could not be easier: four INDEPENDENT standard normals, expressed
# as a multivariate normal with an identity covariance matrix. Every marginal
# has mean 0 and SD 1. Any working sampler should nail this every time.

library(greta)

n_runs <- as.integer(Sys.getenv("N_RUNS", "40"))

cat("greta            ", as.character(packageVersion("greta")), "\n")
cat("TensorFlow       ", reticulate::py_to_r(reticulate::import("tensorflow")$`__version__`), "\n")
cat("TF Probability   ", reticulate::py_to_r(reticulate::import("tensorflow_probability")$`__version__`), "\n")
cat("python           ", reticulate::py_config()$python, "\n\n")

cat(sprintf("Model: multivariate_normal(mean = zeros(1, 4), Sigma = diag(4))\n"))
cat(sprintf("       4 chains, 1000 warmup, all other defaults\n"))
cat(sprintf("Running %d times.\n\n", n_runs))

cat(" run    rhat    min ESS   per-chain SD (true value = 1.0)\n")
cat(" ---   ------   -------   -------------------------------\n")

rhats <- numeric(n_runs)
esss <- numeric(n_runs)

for (i in seq_len(n_runs)) {
  x <- multivariate_normal(mean = zeros(1, 4), Sigma = diag(4))
  m <- model(x)

  draws <- mcmc(m, warmup = 1000, chains = 4, verbose = FALSE)

  rhats[i] <- max(
    coda::gelman.diag(draws, autoburnin = FALSE, multivariate = FALSE)$psrf[, 2]
  )
  esss[i] <- min(coda::effectiveSize(draws))
  sds <- vapply(draws, function(ch) sd(ch[, 1]), numeric(1))

  cat(sprintf(
    " %3d   %6.3f   %7.0f   %s %s\n",
    i, rhats[i], esss[i],
    paste(sprintf("%.2f", sds), collapse = " "),
    if (rhats[i] >= 1.1) "  <-- FAILED TO CONVERGE" else ""
  ))
}

failed <- rhats >= 1.1
cat("\n=============================================================\n")
cat(sprintf("  runs                       %d\n", n_runs))
cat(sprintf("  failed to converge         %d  (%.0f%%)\n",
            sum(failed), 100 * mean(failed)))
cat(sprintf("  rhat        median %.3f    worst %.2f\n",
            median(rhats), max(rhats)))
cat(sprintf("  min ESS     median %.0f      worst %.0f   (of 4000 draws)\n",
            median(esss), min(esss)))
cat("=============================================================\n")
cat("\nAn rhat of 1.1 is the conventional threshold; >= 1.1 means the chains\n")
cat("disagree and the draws should not be used. On a model this simple the\n")
cat("expected failure rate is zero.\n")
