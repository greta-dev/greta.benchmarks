# Does greta converge on these models? Run this and look.
#
#   Rscript --quiet --vanilla 2026-09-21-session-state-vs-ess/explore.R
#
# or open it and run it line by line.
#
# This one is meant to be EDITED - change `model_name` and the settings below
# and run it again. That is the opposite of 01-measure.R in this directory,
# which is the record of a measurement and does not change once it has run.
#
# It answers two questions in one go:
#
#   1. what does greta actually give you on this model, per variable, at these
#      settings - the full posterior::summarise_draws() table, not a minimum
#   2. does that get worse as the session goes on - the same model run
#      `n_runs` times in THIS process, which is the thing the mcmc-suite
#      harness does and AGENTS.md says not to
#
# If run 1 looks fine and run 5 looks bad, session state is the problem and the
# harness has been measuring itself. If every run looks the same, it is not.

library(here)
library(greta)
library(posterior)


chains <- 4
n_samples <- 4000
warmup <- 2000
n_runs <- 5

# -----------------------------------------------------------------------------
source(here("R", "examples.R"))
greta_bench_models <- bench_examples()
linear_model <- mcmc(
  greta_bench_models$linear(),
  n_samples = n_samples,
  warmup = warmup,
  chains = chains,
  n_cores = 4L
)

hierarchy_model <- mcmc(
  greta_bench_models$hierarchical_linear(),
  n_samples = n_samples,
  warmup = warmup,
  chains = chains,
  n_cores = 4L
)

summarise_draws(linear_model)
summarise_draws(hierarchy_model)


summarise_one <- function(run) {
  m <- greta_bench_models[[model_name]]()

  elapsed <- system.time(
    draws <- mcmc(
      m,
      n_samples = n_samples,
      warmup = warmup,
      chains = chains,
      verbose = FALSE
    )
  )[["elapsed"]]

  summ <- summarise_draws(as_draws_array(draws))

  cat(
    "\n=== run",
    run,
    "of",
    n_runs,
    "-",
    model_name,
    "-",
    round(elapsed, 1),
    "s ===\n"
  )
  # the whole per-variable table, because a minimum across variables is what
  # made this look like total failure in the first place
  print(summ[, c("variable", "rhat", "ess_bulk", "ess_tail")], n = Inf)

  # A low ESS on a correct sampler usually means the posterior is correlated,
  # not that the sampler is broken - HMC with a diagonal mass matrix mixes
  # badly along a ridge. So report the worst-correlated pairs next to the ESS,
  # because that is the difference between "greta is slow" and "this model is
  # parameterised badly". Top pairs rather than the whole matrix, so this still
  # prints something readable for wide_linear's 202 variables.
  draw_matrix <- as_draws_matrix(draws)
  if (ncol(draw_matrix) > 1) {
    correlations <- cor(draw_matrix)
    correlations[upper.tri(correlations, diag = TRUE)] <- NA
    pairs <- which(!is.na(correlations), arr.ind = TRUE)
    worst <- order(abs(correlations[pairs]), decreasing = TRUE)[
      seq_len(min(5, nrow(pairs)))
    ]
    cat("strongest posterior correlations:\n")
    print(
      data.frame(
        pair = paste(
          colnames(correlations)[pairs[worst, "col"]],
          colnames(correlations)[pairs[worst, "row"]],
          sep = " ~ "
        ),
        correlation = round(correlations[pairs][worst], 3)
      ),
      row.names = FALSE
    )
  }

  data.frame(
    run = run,
    elapsed = elapsed,
    n_variables = nrow(summ),
    rhat_max = max(summ$rhat),
    ess_bulk_min = min(summ$ess_bulk),
    ess_bulk_median = median(summ$ess_bulk),
    n_below_400 = sum(summ$ess_bulk < 400)
  )
}

per_run <- do.call(rbind, lapply(seq_len(n_runs), summarise_one))

cat("\n\n=== all", n_runs, "runs, in one session ===\n")
print(per_run, row.names = FALSE, digits = 4)

# Deliberately NOT a pass/fail count. ESS > 400 is where the diagnostics become
# trustworthy, not where accuracy becomes sufficient (Vehtari et al. 2021), so
# counting runs either side of it turns a distribution straddling the line into
# "this model does not converge". Across ten runs `linear` ranged 83 to 726 on
# minimum bulk-ESS, passing 3 times - the count says more about where the line
# sits than about the sampler.
cat("\nminimum bulk-ESS across", n_runs, "runs:\n")
cat(
  "  range ",
  paste(round(range(per_run$ess_bulk_min)), collapse = " to "),
  "\n"
)
cat("  median", round(median(per_run$ess_bulk_min)), "\n")

cat("max Rhat across", n_runs, "runs:\n")
cat(
  "  range ",
  paste(round(range(per_run$rhat_max), 3), collapse = " to "),
  "\n"
)

cat(
  "\nfor orientation rather than a verdict:",
  "Rhat < 1.01, bulk-ESS > 400 (Vehtari et al. 2021)\n"
)
