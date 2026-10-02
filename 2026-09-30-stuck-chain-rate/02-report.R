# Summarises results.csv into results.md.
#
#   Rscript --vanilla ~/github/greta-dev/greta.benchmarks/2026-09-30-stuck-chain-rate/02-report.R

library(here)
library(knitr)

run_dir <- here("2026-09-30-stuck-chain-rate")
runs <- read.csv(file.path(run_dir, "results.csv"))
runs$off_whole_turn <- abs(runs$turns - round(runs$turns))
poorly_mixing <- runs$ess_bulk < 100

worst <- runs[order(runs$ess_bulk), ][1:12, ]
worst_table <- kable(
  worst[, c(
    "seed",
    "epsilon",
    "sampling_l",
    "turns",
    "off_whole_turn",
    "observed_lag1",
    "ess_bulk"
  )],
  digits = 3,
  row.names = FALSE,
  col.names = c(
    "seed",
    "epsilon",
    "L",
    "L * theta / pi",
    "distance from whole number",
    "lag-1 autocorrelation",
    "bulk ESS"
  )
)

by_l <- kable(
  as.data.frame.matrix(table(
    L = runs$sampling_l,
    mixing = ifelse(poorly_mixing, "ESS < 100", "ESS >= 100")
  )),
  row.names = TRUE
)

writeLines(
  c(
    "# How often an hmc() chain stops mixing on main",
    "",
    paste0(
      "greta main at 179021a8, one chain per seed, seeds 1 to ",
      nrow(runs),
      ", `mcmc()` defaults (1000 warmup, 1000 samples, `hmc(Lmin = 5, ",
      "Lmax = 10)`) with `verbose = FALSE`, on the one-parameter model from ",
      "`test-data-swapping.R`. `01-measure.R` records the leapfrog count L ",
      "that `hmc()` draws for the sampling phase; `theta` is the angle one ",
      "leapfrog step turns a Gaussian posterior with sd 1 / sqrt(10.01)."
    ),
    "",
    paste0(
      "- ",
      sum(poorly_mixing),
      " of ",
      nrow(runs),
      " chains have a bulk ESS below 100 from 1000 draws; ",
      sum(runs$ess_bulk < 10),
      " below 10."
    ),
    paste0(
      "- Every one of them has L * theta / pi within ",
      round(max(runs$off_whole_turn[poorly_mixing]), 3),
      " of a whole number."
    ),
    paste0(
      "- Tuned epsilon ranges from ",
      round(min(runs$epsilon), 3),
      " to ",
      round(max(runs$epsilon), 3),
      ", so theta barely changes between seeds and the same values of L ",
      "land on whole numbers every time."
    ),
    "",
    "## The twelve chains with the lowest ESS",
    "",
    worst_table,
    "",
    "## Chains by the L drawn for sampling",
    "",
    by_l
  ),
  file.path(run_dir, "results.md")
)
