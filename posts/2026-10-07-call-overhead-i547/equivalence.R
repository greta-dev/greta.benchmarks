# Seeded results from one installed greta, saved for comparison with another.
# results-equivalence/ holds f30ab146's (measured.rds) and 88e44dff's
# (reviewed.rds). To repeat it, install each version into a library of its
# own, run this against each, and compare the two files with identical():
#
#   Rscript -e 'pak::pkg_install("greta-dev/greta@<sha>", lib = "<library>")'
#   Rscript --quiet --vanilla posts/2026-10-07-call-overhead-i547/equivalence.R \
#     <library> <output.rds>

args <- commandArgs(trailingOnly = TRUE)
library(greta, lib.loc = args[1])

linear <- function() {
  int <- normal(0, 10)
  coef <- normal(0, 10)
  sd <- cauchy(0, 3, truncation = c(0, Inf))
  mu <- int + coef * attitude$complaints
  distribution(attitude$rating) <- normal(mu, sd)
  model(int, coef, sd)
}

draws_of <- function(sampler, ...) {
  m <- linear()
  set.seed(2026 - 10 - 9)
  draws <- mcmc(m, sampler = sampler, ...)
  lapply(draws, as.matrix)
}

runs <- list(
  hmc_defaults = draws_of(
    hmc(),
    warmup = 200,
    n_samples = 200,
    chains = 2,
    verbose = FALSE
  ),
  hmc_progress = draws_of(
    hmc(),
    warmup = 200,
    n_samples = 200,
    chains = 2,
    pb_update = 30
  ),
  hmc_one_by_one = draws_of(
    hmc(),
    warmup = 60,
    n_samples = 60,
    chains = 2,
    one_by_one = TRUE,
    verbose = FALSE
  ),
  hmc_thin = draws_of(
    hmc(),
    warmup = 100,
    n_samples = 150,
    thin = 3,
    chains = 4,
    verbose = FALSE
  ),
  rwmh = draws_of(
    rwmh(),
    warmup = 200,
    n_samples = 200,
    chains = 2,
    verbose = FALSE
  ),
  slice_one_chain = draws_of(
    slice(),
    warmup = 100,
    n_samples = 100,
    chains = 1,
    verbose = FALSE
  )
)

# extra_samples() carries on the same chains
m <- linear()
set.seed(2026 - 10 - 9)
draws <- mcmc(
  m,
  warmup = 100,
  n_samples = 100,
  chains = 2,
  thin = 2,
  verbose = FALSE
)
more <- extra_samples(draws, n_samples = 60, thin = 2, verbose = FALSE)
runs$extra_samples <- lapply(more, as.matrix)

# opt() with each kind of optimiser, twice on one model so the cache is used
optimisers <- list(
  adam = adam(learning_rate = 0.1),
  gradient_descent = gradient_descent(learning_rate = 0.01),
  rms_prop = rms_prop(),
  bfgs = bfgs(),
  nelder_mead = nelder_mead(),
  proximal_adagrad = proximal_adagrad()
)
# an optimiser that overflows on this model is compared by its error message
opt_or_error <- function(m, optimiser) {
  tryCatch(
    opt(m, optimiser = optimiser, max_iterations = 200),
    error = conditionMessage
  )
}
for (name in names(optimisers)) {
  m <- linear()
  first <- opt_or_error(m, optimisers[[name]])
  second <- opt_or_error(m, optimisers[[name]])
  runs[[paste0("opt_", name)]] <- list(first = first, second = second)
}

saveRDS(runs, args[2])
cat(
  "saved",
  length(runs),
  "runs from greta",
  as.character(packageVersion("greta", lib.loc = args[1])),
  "\n"
)
