# Do the diagnostics in 01-measure.R report the sampler, or report themselves?
#
#   Rscript --quiet --vanilla 2026-09-21-mcmc-suite/00-check-diagnostics.R
#
# An earlier version of this harness reshaped greta's mcmc.list by hand,
# scrambled chains against variables, and reported Rhat of Inf with a bulk-ESS
# of 4 - diagnostics of the reshape, not of the sampler. The comment recording
# that is still in 01-measure.R. Before quoting any Rhat out of results.rds,
# check that the version which produced it does not do the same thing.
#
# Numbered 00 because it validates 01 rather than measuring anything.
#
# Four checks, each one able to fail:
#
#   1. the coercion is faithful element for element. draws[[chain]][i, v]
#      against as_draws_array(draws)[i, chain, v], every cell.
#   2. a known-good input - four independent iid normal chains - gives
#      Rhat near 1. If this fails the estimator is being called wrongly.
#   3. a known-bad input - four chains parked at different modes - is caught.
#      A check that only passes good input cannot distinguish a working
#      diagnostic from one that returns 1 unconditionally.
#   4. deliberately scrambling chains against variables changes the answer,
#      which is what makes check 1 worth running.
#
# Then the statistic itself: posterior::rhat() is rank-normalised and folded,
# coda's psrf[, 1] is the classic estimator. They are different numbers on the
# same draws, and only one of them is in results.rds.

library(here)
library(fs)

run_dir <- here("2026-09-21-mcmc-suite")
source(here("provenance.R"))

library(greta)
library(posterior)

set.seed(2026 - 09 - 21)

n_iter <- 500
n_chain <- 4

report <- function(label, ok) {
  cat(if (ok) "PASS  " else "FAIL  ", label, "\n", sep = "")
  ok
}

# ---- 1. is the coercion faithful? -------------------------------------------

# a real greta model, because the question is about greta's mcmc.list and not
# about coda's
int <- normal(0, 10)
coef <- normal(0, 10)
sd <- cauchy(0, 3, truncation = c(0, Inf))
mu <- int + coef * attitude$complaints
distribution(attitude$rating) <- normal(mu, sd)
m <- model(int, coef, sd)

draws <- mcmc(
  m,
  n_samples = n_iter,
  warmup = n_iter,
  chains = n_chain,
  verbose = FALSE
)

arr <- as_draws_array(draws)

n_var <- ncol(draws[[1]])

dims_ok <- identical(
  dim(arr),
  as.integer(c(n_iter, n_chain, n_var))
)

vars_ok <- identical(
  as.character(variables(arr)),
  colnames(draws[[1]])
)

# every cell, not a spot check: a transposition that swaps two chains would
# survive a corner-only comparison.
# unclass() first, because posterior's `[.draws_array` keeps the chain
# dimension rather than dropping it, so arr[, chain, ] is 500x1x3.
# as.array() does not help - it returns a draws_array, class intact
plain <- unclass(arr)
cell_diffs <- vapply(
  seq_len(n_chain),
  function(chain) {
    max(abs(as.matrix(draws[[chain]]) - plain[, chain, ]))
  },
  numeric(1)
)
cells_ok <- max(cell_diffs) == 0

# reported separately rather than combined with `&&`, which would short-circuit
# and hide the two checks after the first failure
check_1 <- all(
  report("1. coercion preserves dimensions", dims_ok),
  report("1. coercion preserves variable names", vars_ok),
  report("1. coercion preserves every draw", cells_ok)
)

# ---- 2. known-good input ----------------------------------------------------

good <- array(
  rnorm(n_iter * n_chain * 3),
  dim = c(n_iter, n_chain, 3),
  dimnames = list(NULL, NULL, c("a", "b", "c"))
) |>
  as_draws_array()

good_rhat <- max(summarise_draws(good, rhat = rhat)$rhat)
good_ess <- min(summarise_draws(good, ess_bulk = ess_bulk)$ess_bulk)

check_2 <- all(
  report("2. iid chains give Rhat < 1.01", good_rhat < 1.01),
  report(
    "2. iid chains give bulk-ESS near the draw count",
    good_ess > 0.8 * n_iter * n_chain
  )
)

# ---- 3. known-bad input -----------------------------------------------------

# same marginal spread, four different centres. Classic Rhat and the
# rank-normalised one should both reject this
bad <- good
for (chain in seq_len(n_chain)) {
  bad[, chain, ] <- bad[, chain, ] + (chain - 1) * 10
}

bad_rhat <- max(summarise_draws(bad, rhat = rhat)$rhat)

check_3 <- report("3. chains at different modes are caught", bad_rhat > 1.01)

# ---- 4. what the old by-hand reshape did ------------------------------------

# The actual reshape that caused the trouble, not a synthetic permutation.
# unlist() walks each chain's matrix column-major - every iteration of
# variable 1, then of variable 2 - so filling (iteration, chain, variable) puts
# chain 1's second variable where chain 2's first should be. Chains and
# variables change places, which is the failure the comment in 01-measure.R
# describes.
old_reshape <- function(chain_list, n_iter, n_chain, n_var, var_names) {
  as_draws_array(
    array(
      unlist(chain_list),
      dim = c(n_iter, n_chain, n_var),
      dimnames = list(NULL, NULL, var_names)
    )
  )
}

# demonstrated on chains known to be good, because greta's own draws here are
# not: they come back at Rhat 2.5, and a reshape that also reports 2.5 shows
# nothing. Four iid chains, three variables on deliberately different scales,
# because the reshape swaps variables into chain positions and only differing
# scales make that visible.
control <- lapply(
  seq_len(n_chain),
  function(chain) {
    coda::mcmc(cbind(
      small = rnorm(n_iter, 0, 1),
      medium = rnorm(n_iter, 10, 1),
      large = rnorm(n_iter, 100, 1)
    ))
  }
) |>
  coda::mcmc.list()

control_arr <- as_draws_array(control)
control_rhat <- max(summarise_draws(control_arr, rhat = rhat)$rhat)
control_ess <- min(summarise_draws(control_arr, ess_bulk = ess_bulk)$ess_bulk)

control_scrambled <- old_reshape(
  control,
  n_iter,
  n_chain,
  3,
  c("small", "medium", "large")
)
control_scrambled_rhat <- max(
  summarise_draws(control_scrambled, rhat = rhat)$rhat
)
control_scrambled_ess <- min(
  summarise_draws(control_scrambled, ess_bulk = ess_bulk)$ess_bulk
)

posterior_rhat <- summarise_draws(arr, rhat = rhat)

scrambled <- old_reshape(draws, n_iter, n_chain, n_var, variables(arr))
scrambled_rhat <- max(summarise_draws(scrambled, rhat = rhat)$rhat)
scrambled_ess <- min(summarise_draws(scrambled, ess_bulk = ess_bulk)$ess_bulk)

check_4 <- all(
  report(
    "4. the old reshape does not match the coercion",
    !isTRUE(all.equal(as.numeric(unclass(scrambled)), as.numeric(plain)))
  ),
  report(
    "4. and on known-good chains it turns Rhat ~1 into a failure",
    control_rhat < 1.01 && control_scrambled_rhat > 1.5
  )
)

# ---- the statistic in results.rds -------------------------------------------

# posterior::rhat() is rank-normalised and folded (Vehtari et al. 2021);
# coda's psrf[, 1] is the classic estimator. results.rds holds the first.
# Recording both, because a folded Rhat of 1.3 and a classic Rhat of 1.05 are
# the same chains described by two statistics, and the write-up should say
# which one it is quoting.
coda_psrf <- coda::gelman.diag(
  coda::as.mcmc.list(draws),
  autoburnin = FALSE,
  multivariate = FALSE
)$psrf

comparison <- data.frame(
  variable = posterior_rhat$variable,
  rhat_posterior = round(posterior_rhat$rhat, 4),
  rhat_coda_point = round(coda_psrf[, 1], 4),
  rhat_coda_upper = round(coda_psrf[, 2], 4)
)

cat("\n")
print(comparison)

saveRDS(
  list(
    checks = c(
      coercion = check_1,
      known_good = check_2,
      known_bad = check_3,
      old_reshape = check_4
    ),
    good_rhat = good_rhat,
    good_ess = good_ess,
    bad_rhat = bad_rhat,
    scrambled_rhat = scrambled_rhat,
    scrambled_ess = scrambled_ess,
    control_rhat = control_rhat,
    control_ess = control_ess,
    control_scrambled_rhat = control_scrambled_rhat,
    control_scrambled_ess = control_scrambled_ess,
    comparison = comparison,
    design = list(n_iter = n_iter, n_chain = n_chain),
    provenance = host_provenance()
  ),
  path(run_dir, "check-diagnostics.rds"),
  compress = "xz"
)

cat("\nwrote", path(run_dir, "check-diagnostics.rds"), "\n")
