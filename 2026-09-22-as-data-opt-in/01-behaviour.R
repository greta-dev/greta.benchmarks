# as_data() is exported coercion, so plumbing calls it. Using it as the marker
# for "back this with a tf$Variable" therefore promotes data nobody asked to
# swap. Run on branch data-values-as-data-opt-in.
#
#   Rscript --quiet --vanilla 2026-09-22-as-data-opt-in/01-behaviour.R

library(here)
library(fs)

greta_repo <- path(path_dir(here()), "greta")
suppressMessages(pkgload::load_all(greta_repo, quiet = TRUE))

promoted <- function(m) length(m$dag$data_variables)

# the opt-in working as intended: 2 of 8 data nodes promoted, the other six
# being the 0, 10, 0, 10, 0 and 3 in the priors
x <- as_data(attitude$complaints)
y <- as_data(attitude$rating)
int <- normal(0, 10)
coef <- normal(0, 10)
sd <- cauchy(0, 3, truncation = c(0, Inf))
distribution(y) <- normal(int + coef * x, sd)
promoted(model(int, coef, sd))

# the problem: greta.dynamics calls as_data() on a loop counter, so a scalar
# nobody will ever replace is promoted in a package greta cannot patch
writeLines(grep(
  "as_data(1)",
  readLines(path(
    path_dir(here()),
    "greta.dynamics/R/iterate_dynamic_matrix.R"
  )),
  fixed = TRUE,
  value = TRUE
))
