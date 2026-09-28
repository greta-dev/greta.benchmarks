# How much rounding error does rebuilding a matrix from its Cholesky factor
# carry, and how often does it exceed .Machine$double.eps?
#
#   GRETA_REPO=~/github/greta-dev/greta \
#     Rscript --quiet --vanilla 2026-09-28-chol2symm-tolerance-i842/01-measure.R
#
# greta's "chol2symm inverts chol" test compared x with chol2symm(chol(x)) at
# tolerance = .Machine$double.eps, on an unseeded rWishart() draw. It failed on
# Windows CI for #842 with differences in the last digit. This run measures, over
# many draws, the relative error all.equal() sees, for both chol2symm() in R and
# greta's calculate(chol2symm(as_data(u))), and how often each tolerance fails.
#
# Not a timing run, so one process is fine: rounding does not depend on session
# state the way timings and memory do.

library(here)
library(fs)
library(pkgload)

run_dir <- here("2026-09-28-chol2symm-tolerance-i842")
source(here("R", "provenance.R"))

greta_repo <- path_expand(Sys.getenv("GRETA_REPO", "~/github/greta-dev/greta"))
greta_sha <- git_sha(greta_repo, "HEAD")
load_all(greta_repo, quiet = TRUE)

tolerances <- c(eps = .Machine$double.eps, fixed = 1e-12)

# the statistic all.equal() compares against its tolerance: the mean relative
# difference over the elements that differ, leaving out those that match
# exactly. giveErr = TRUE returns it; with nothing differing there is no error
all_equal_error <- function(target, current) {
  result <- all.equal(target, current, tolerance = 0, giveErr = TRUE)
  attr(result, "err") %||% 0
}

measure <- function(seed, side) {
  set.seed(seed)
  x <- rWishart(1, 10, diag(9))[,, 1]
  u <- chol(x)
  rebuilt <- switch(
    side,
    r = chol2symm(u),
    greta = calculate(chol2symm(as_data(u)))[[1]]
  )
  data.frame(
    seed = seed,
    side = side,
    error = all_equal_error(x, rebuilt),
    fails_eps = !isTRUE(all.equal(x, rebuilt, tolerance = tolerances[["eps"]])),
    fails_fixed = !isTRUE(
      all.equal(x, rebuilt, tolerance = tolerances[["fixed"]])
    )
  )
}

# calculate() is slower, so fewer draws on the greta side
r_seeds <- 1:2000
greta_seeds <- 1:200

results <- rbind(
  do.call(rbind, lapply(r_seeds, measure, side = "r")),
  do.call(rbind, lapply(greta_seeds, measure, side = "greta"))
)

saveRDS(
  list(
    results = results,
    tolerances = tolerances,
    greta_sha = greta_sha,
    provenance = host_provenance(packages = c("tensorflow", "reticulate"))
  ),
  path(run_dir, "results.rds")
)
