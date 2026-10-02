# How long one more draw takes, on each version, at thin = 1 and thin = 3.
#
#   GRETA_LIB=<library> VERSION=<label> Rscript --vanilla 01-time-per-draw.R
#
# Run once per version, each with greta installed in its own library. Writes
# time-per-draw-<VERSION>.rds beside this file.
#
# Timing is independent of how greta or TFP count anything: if a version runs
# two iterations per draw, each draw takes twice as long. Every mcmc() call
# traces its sampler afresh, a fixed cost, so the time per draw is the slope
# between two run lengths rather than one run's time divided by its draws.
# rwmh() has the same cost every iteration, where hmc()'s depends on its
# leapfrog count; 20,000 observations make that cost large enough to time.

library(greta, lib.loc = Sys.getenv("GRETA_LIB"))

run_dir <- "~/github/greta-dev/greta.benchmarks/2026-10-01-iterations-and-efficiency-i318"
version <- Sys.getenv("VERSION")

set.seed(2026 - 10 - 01)
n_observations <- 20000
predictor <- rnorm(n_observations)
response <- 1 + 2 * predictor + rnorm(n_observations)

intercept <- normal(0, 10)
slope <- normal(0, 10)
distribution(response) <- normal(intercept + slope * predictor, 1)
m <- model(intercept, slope)

seconds_for <- function(n_samples, thin) {
  elapsed <- system.time(
    mcmc(
      m,
      sampler = rwmh(),
      warmup = 0,
      n_samples = n_samples,
      thin = thin,
      chains = 1,
      verbose = FALSE
    )
  )[["elapsed"]]
  data.frame(
    version = version,
    thin = thin,
    n_samples = n_samples,
    seconds = elapsed
  )
}

# the first call in a session pays for initialising TensorFlow
invisible(seconds_for(30, 1))

grid <- expand.grid(
  rep = 1:3,
  n_samples = c(3000, 12000),
  thin = c(1, 3)
)
times <- do.call(rbind, Map(seconds_for, grid$n_samples, grid$thin))
times$rep <- grid$rep

saveRDS(times, file.path(run_dir, paste0("time-per-draw-", version, ".rds")))
print(times)
