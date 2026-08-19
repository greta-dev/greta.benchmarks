# How often does plain hmc() fail on a STANDARD 4-D Gaussian?
#
# From the branch benchmarks: `mvn_easy/hmc` produced worst-case rhat of 16.6 on
# one run and 1.0 on others, and ESS/sec spreads from 2.6x to 233x. The model is
# multivariate_normal(mean = zeros(1,4), Sigma = diag(4)) -- correlation 0, all
# marginal SDs 1. That should be trivial to sample.
#
# This runs the same model many times and reports the distribution of rhat and
# min ESS, so we can say whether failures are a real rate or a one-off. It also
# records per-chain posterior means, because rhat ~16 with 4 chains suggests one
# chain sitting somewhere else entirely rather than everything mixing slowly.
#
# Usage:
#   GRETA_TEST_PYTHON=<venv>/bin/python GRETA_SRC=<checkout> \
#   GRETA_LABEL=main GRETA_N=50 GRETA_OUT=out.rds \
#     Rscript 09-mvn-easy-stability.R

py <- Sys.getenv("GRETA_TEST_PYTHON")
src <- Sys.getenv("GRETA_SRC")
label <- Sys.getenv("GRETA_LABEL", "unlabelled")
out <- Sys.getenv("GRETA_OUT", paste0("stability-", label, ".rds"))
n_runs <- as.integer(Sys.getenv("GRETA_N", "50"))
n_chains <- as.integer(Sys.getenv("GRETA_CHAINS", "4"))
warmup <- as.integer(Sys.getenv("GRETA_WARMUP", "1000"))
stopifnot(nzchar(src))
if (nzchar(py)) Sys.setenv(RETICULATE_PYTHON = py)
Sys.setenv(TF_CPP_MIN_LOG_LEVEL = 2)

suppressMessages(pkgload::load_all(src, quiet = TRUE))

cat(sprintf(
  "[%s] %d runs, %d chains, %d warmup\n",
  label, n_runs, n_chains, warmup
))
cat("run  rhat      minESS   secs   chain means (dim 1)          verdict\n")

rows <- vector("list", n_runs)

for (i in seq_len(n_runs)) {
  res <- tryCatch(
    {
      dim <- 4
      x <- multivariate_normal(mean = zeros(1, dim), Sigma = diag(dim))
      m <- model(x)

      secs <- system.time(
        draws <- mcmc(m, warmup = warmup, chains = n_chains, verbose = FALSE)
      )[["elapsed"]]

      rh <- coda::gelman.diag(draws, autoburnin = FALSE, multivariate = FALSE)
      rhat <- max(rh$psrf[, 2])
      ess <- min(coda::effectiveSize(draws))

      # per-chain mean of the first coordinate: if one chain is stranded this
      # shows it immediately, where a pooled summary would hide it
      chain_means <- vapply(draws, function(ch) mean(ch[, 1]), numeric(1))

      list(
        ok = TRUE, rhat = rhat, ess = ess, secs = secs,
        chain_means = chain_means,
        spread = diff(range(chain_means))
      )
    },
    error = function(e) list(ok = FALSE, msg = conditionMessage(e))
  )

  if (!res$ok) {
    cat(sprintf("%3d  ERROR: %s\n", i, substr(res$msg, 1, 60)))
    rows[[i]] <- data.frame(
      label = label, run = i, rhat = NA_real_, ess = NA_real_,
      secs = NA_real_, chain_spread = NA_real_, failed = TRUE,
      error = substr(res$msg, 1, 80), stringsAsFactors = FALSE
    )
    next
  }

  bad <- res$rhat >= 1.1
  cat(sprintf(
    "%3d  %-9.3f %-8.0f %-6.2f %-28s %s\n",
    i, res$rhat, res$ess, res$secs,
    paste(sprintf("%.2f", res$chain_means), collapse = " "),
    if (bad) "<-- FAILED" else ""
  ))

  rows[[i]] <- data.frame(
    label = label, run = i, rhat = res$rhat, ess = res$ess,
    secs = res$secs, chain_spread = res$spread, failed = bad,
    error = NA_character_, stringsAsFactors = FALSE
  )
}

df <- do.call(rbind, rows)
saveRDS(df, out)

ok <- df[!is.na(df$rhat), ]
n_bad <- sum(ok$failed)

cat("\n================ summary ================\n")
cat(sprintf("runs:            %d (%d errored)\n", nrow(df), sum(is.na(df$rhat))))
cat(sprintf("convergence failures (rhat >= 1.1): %d / %d  (%.0f%%)\n",
            n_bad, nrow(ok), 100 * n_bad / nrow(ok)))
cat(sprintf("rhat:            median %.3f  max %.2f\n",
            stats::median(ok$rhat), max(ok$rhat)))
cat(sprintf("min ESS:         median %.0f  min %.0f  max %.0f  (spread %.1fx)\n",
            stats::median(ok$ess), min(ok$ess), max(ok$ess),
            max(ok$ess) / max(1, min(ok$ess))))
cat(sprintf("elapsed:         median %.2fs  (spread %.2fx)\n",
            stats::median(ok$secs), max(ok$secs) / min(ok$secs)))
cat(sprintf("chain-mean range: median %.3f  max %.2f\n",
            stats::median(ok$chain_spread), max(ok$chain_spread)))

if (n_bad > 0) {
  cat("\nfailed runs:\n")
  print(ok[ok$failed, c("run", "rhat", "ess", "chain_spread")], row.names = FALSE)
}
cat(sprintf("\nwrote %s\n", out))
