# Is a batch-means score normal or t-distributed, at the batch counts greta's
# bivariate normal test uses?
#
#   GRETA_REPO=~/github/greta-dev/greta \
#     Rscript --quiet --vanilla 2026-09-28-batch-means-t-threshold/01-measure.R
#
# test_posteriors_bivariate_normal.R scores each posterior summary as
# |estimate - truth| / MCSE, with the MCSE from batch means over about sqrt(n)
# batches (mcse() in tests/testthat/helpers.R), and fails a sampler when any of
# five scores passes qnorm(1 - 0.01 / 10). A standard error estimated from `a`
# batch means makes the score t-distributed with a - 1 degrees of freedom
# (Flegal and Jones 2010), so the normal cut-off should reject more than the 0.2%
# per score it is set for.
#
# Chains here are AR(1) with a known mean of zero, standing in for MCMC output:
# autocorrelated, like a sampler's draws, and with the truth known exactly. n of
# 4000 and 16000 give 63 and 126 batches, spanning what the test sees.
#
# Not a timing run, so one process is fine.

library(here)
library(fs)

run_dir <- here("2026-09-28-batch-means-t-threshold")
source(here("R", "provenance.R"))

# mcse() exactly as the test uses it, taken from the greta checkout rather than
# copied, so the run measures the code the test runs
greta_repo <- path_expand(Sys.getenv("GRETA_REPO", "~/github/greta-dev/greta"))
helpers <- path(greta_repo, "tests", "testthat", "helpers.R")
greta_sha <- git_sha(greta_repo, "HEAD")
exprs <- parse(helpers)
is_mcse <- vapply(
  exprs,
  function(e) is.call(e) && identical(e[[2]], as.name("mcse")),
  logical(1)
)
eval(exprs[[which(is_mcse)]])

set.seed(2026 - 09 - 28)
n_reps <- 20000
ns <- c(4000, 16000)
ar <- 0.5

score <- function(n) {
  x <- as.numeric(stats::filter(rnorm(n), ar, method = "recursive"))
  abs(mean(x)) / as.vector(mcse(matrix(x, ncol = 1)))
}

results <- do.call(
  rbind,
  lapply(ns, function(n) {
    data.frame(
      n = n,
      n_batches = floor(n / floor(sqrt(n))),
      score = replicate(n_reps, score(n))
    )
  })
)

saveRDS(
  list(
    results = results,
    ar = ar,
    greta_sha = greta_sha,
    provenance = host_provenance(packages = "stats")
  ),
  path(run_dir, "results.rds")
)
