# Does greta.dynamics' `iter = as_data(1)` actually cost anything?
#
#   Rscript --quiet --vanilla 2026-09-22-as-data-opt-in/02-does-it-matter.R
#
# The concern was that as_data() is exported coercion, so plumbing calls it and
# marks nodes swappable that nobody will replace. greta.dynamics does exactly
# that for a loop counter. But that call feeds as_tf_matrix_function(), which
# builds inside a tf_function trace, and define_data_variables() bails out
# there - so the mark may never turn into a tf$Variable.
#
# Prints the number of tf$Variables in a greta.dynamics model's dag. If that is
# no higher than the number of greta arrays the user declared with as_data(),
# the concern is empty.
#
# Run on branch data-values-as-data-opt-in.

library(here)
library(fs)

root <- path_dir(here())
suppressMessages(pkgload::load_all(path(root, "greta"), quiet = TRUE))
suppressMessages(pkgload::load_all(path(root, "greta.dynamics"), quiet = TRUE))

matrix_function <- function(state, iter) {
  mat <- zeros(2, 2)
  mat[1, 1] <- 0.9
  mat[1, 2] <- 1.2
  mat[2, 1] <- 0.1
  mat[2, 2] <- 0.8
  mat
}

initial_state <- as_data(matrix(c(2, 20), nrow = 2, ncol = 1))

results <- iterate_dynamic_matrix(
  matrix_function = matrix_function,
  initial_state = initial_state,
  niter = 100,
  tol = 1e-6
)

sigma <- lognormal(0, 1)
obs <- as_data(matrix(c(3, 21), nrow = 2, ncol = 1))
distribution(obs) <- normal(results$stable_population * sigma, 1)
m <- model(sigma)

data_nodes <- m$dag$node_list[m$dag$node_types == "data"]
marked <- vapply(data_nodes, function(n) isTRUE(n$swappable), logical(1))

data.frame(
  data_nodes = length(data_nodes),
  marked_swappable = sum(marked),
  tf_variables = length(m$dag$data_variables),
  user_as_data_calls = 2L
)
