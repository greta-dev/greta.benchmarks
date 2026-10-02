# Effective samples per iteration and per second, at equal iterations.
#
#   GRETA_LIB=<library> VERSION=<label> WARMUP=<n> N_SAMPLES=<n> \
#     Rscript --vanilla 02-efficiency.R
#
# Run once per version. Writes efficiency-<VERSION>.rds beside this file.
#
# Every version runs 2000 warmup and 2000 sampling iterations per chain, so
# CRAN and main are given warmup = 1000, n_samples = 1000, which they run at
# two iterations per draw, and #850 is given 2000 and 2000. Eight seeds per
# model, because tuned step sizes and so ESS vary several-fold between runs
# of one version. CRAN does not follow set.seed() in mcmc(), so its runs
# differ by more than the seed.

library(greta, lib.loc = Sys.getenv("GRETA_LIB"))

run_dir <- "~/github/greta-dev/greta.benchmarks/2026-10-01-iterations-and-efficiency-i318"
version <- Sys.getenv("VERSION")
warmup <- as.integer(Sys.getenv("WARMUP"))
n_samples <- as.integer(Sys.getenv("N_SAMPLES"))

source("~/github/greta-dev/greta.benchmarks/R/examples.R")
examples <- bench_examples()[c(
  "linear",
  "multiple_linear",
  "hierarchical_linear",
  "eight_schools"
)]

fit_once <- function(example, seed) {
  m <- examples[[example]]()
  set.seed(seed)
  elapsed <- system.time(
    draws <- mcmc(
      m,
      warmup = warmup,
      n_samples = n_samples,
      chains = 4,
      n_cores = 4L,
      verbose = FALSE
    )
  )[["elapsed"]]
  summ <- posterior::summarise_draws(
    posterior::as_draws_array(draws),
    "rhat",
    "ess_bulk",
    "ess_tail"
  )
  data.frame(
    version = version,
    example = example,
    seed = seed,
    seconds = elapsed,
    epsilon = tryCatch(
      mean(vapply(
        attr(draws, "model_info")$samplers,
        function(s) s$parameters$epsilon,
        numeric(1)
      )),
      error = function(e) NA_real_
    ),
    ess_bulk_min = min(summ$ess_bulk),
    ess_tail_min = min(summ$ess_tail),
    rhat_max = max(summ$rhat)
  )
}

# the first call in a session pays for initialising TensorFlow
invisible(fit_once("linear", 1))

grid <- expand.grid(seed = 1:8, example = names(examples))
runs <- do.call(
  rbind,
  Map(fit_once, as.character(grid$example), grid$seed)
)

saveRDS(runs, file.path(run_dir, paste0("efficiency-", version, ".rds")))
print(runs)
