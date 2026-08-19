# Why does hmc() fail ~10% of the time on a standard 4-D Gaussian?
#
# 09-mvn-easy-stability.R established the rate (5/50 on TF 2.15, 6/50 on TF
# 2.21 -- so not TF-version related) and the signature: chains agree on
# location, but ESS collapses from ~1700 to ~20. That points at step-size
# adaptation rather than initialisation or stranded chains.
#
# This captures the sampler's own tuning state per run and correlates it with
# failure:
#   epsilon        = exp(log_epsilon_bar), the adapted step size
#   mean_accept_stat  vs accept_target (0.651)
#   numerical_rejections
#
# Usage:
#   GRETA_TEST_PYTHON=<venv>/bin/python GRETA_SRC=<checkout> \
#   GRETA_N=60 GRETA_OUT=out.rds Rscript 10-mvn-easy-mechanism.R

py <- Sys.getenv("GRETA_TEST_PYTHON")
src <- Sys.getenv("GRETA_SRC")
label <- Sys.getenv("GRETA_LABEL", "unlabelled")
out <- Sys.getenv("GRETA_OUT", paste0("mechanism-", label, ".rds"))
n_runs <- as.integer(Sys.getenv("GRETA_N", "60"))
n_chains <- as.integer(Sys.getenv("GRETA_CHAINS", "4"))
warmup <- as.integer(Sys.getenv("GRETA_WARMUP", "1000"))
stopifnot(nzchar(src))
if (nzchar(py)) Sys.setenv(RETICULATE_PYTHON = py)
Sys.setenv(TF_CPP_MIN_LOG_LEVEL = 2)

suppressMessages(pkgload::load_all(src, quiet = TRUE))

cat(sprintf("[%s] %d runs, %d chains, %d warmup\n\n", label, n_runs, n_chains, warmup))
cat("run  rhat      minESS   epsilon    accept   numrej  verdict\n")

rows <- vector("list", n_runs)

for (i in seq_len(n_runs)) {
  res <- tryCatch(
    {
      x <- multivariate_normal(mean = zeros(1, 4), Sigma = diag(4))
      m <- model(x)
      draws <- mcmc(m, warmup = warmup, chains = n_chains, verbose = FALSE)

      rh <- coda::gelman.diag(draws, autoburnin = FALSE, multivariate = FALSE)
      rhat <- max(rh$psrf[, 2])
      ess <- min(coda::effectiveSize(draws))

      s <- attr(draws, "model_info")$samplers[[1]]
      epsilon <- exp(s$log_epsilon_bar)
      accept <- s$mean_accept_stat
      numrej <- s$numerical_rejections
      # diag_sd: the adapted per-dimension scaling
      diag_sd <- tryCatch(
        {
          p <- s$parameters
          v <- p$diag_sd
          if (is.null(v)) NA_real_ else max(abs(unlist(v)))
        },
        error = function(e) NA_real_
      )

      list(ok = TRUE, rhat = rhat, ess = ess, epsilon = epsilon,
           accept = accept, numrej = numrej, diag_sd = diag_sd)
    },
    error = function(e) list(ok = FALSE, msg = conditionMessage(e))
  )

  if (!res$ok) {
    cat(sprintf("%3d  ERROR %s\n", i, substr(res$msg, 1, 50)))
    next
  }

  bad <- res$rhat >= 1.1
  cat(sprintf(
    "%3d  %-9.3f %-8.0f %-10.3f %-8.3f %-7s %s\n",
    i, res$rhat, res$ess, res$epsilon, res$accept, res$numrej,
    if (bad) "<-- FAILED" else ""
  ))

  rows[[i]] <- data.frame(
    label = label, run = i, rhat = res$rhat, ess = res$ess,
    epsilon = res$epsilon, accept = res$accept,
    numrej = res$numrej, diag_sd = res$diag_sd, failed = bad,
    stringsAsFactors = FALSE
  )
}

df <- do.call(rbind, rows)
saveRDS(df, out)

cat("\n================ mechanism ================\n")
n_bad <- sum(df$failed)
cat(sprintf("failures: %d / %d (%.0f%%)\n\n", n_bad, nrow(df), 100 * n_bad / nrow(df)))

summarise <- function(d, what) {
  cat(sprintf(
    "  %-8s n=%-3d  epsilon med %6.2f [%5.2f, %6.2f]   accept med %.3f   ESS med %6.0f\n",
    what, nrow(d), stats::median(d$epsilon), min(d$epsilon), max(d$epsilon),
    stats::median(d$accept), stats::median(d$ess)
  ))
}
if (n_bad > 0) summarise(df[df$failed, ], "FAILED")
summarise(df[!df$failed, ], "passed")

cat(sprintf("\naccept_target is 0.651; Lmin/Lmax default 5/10\n"))
cat(sprintf(
  "correlation(epsilon, log10(ESS)) = %.3f\n",
  suppressWarnings(stats::cor(df$epsilon, log10(pmax(df$ess, 1)), use = "complete.obs"))
))
cat(sprintf(
  "correlation(accept,  log10(ESS)) = %.3f\n",
  suppressWarnings(stats::cor(df$accept, log10(pmax(df$ess, 1)), use = "complete.obs"))
))
cat(sprintf("\nwrote %s\n", out))
