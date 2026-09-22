# First pass at an MCMC suite: does a branch sample as well, and as fast?
#
#   Rscript --quiet --vanilla 2026-09-21-mcmc-suite/01-measure.R
#
# Two tiers, because they answer different questions and {bench} fits one of
# them and fights the other.
#
#   tier 1  build and opt, via cross::bench_branches(). Deterministic work, so
#           bench::mark() is the right tool: many iterations, a real
#           <bench_mark> back, and summary(relative = TRUE) and autoplot()
#           apply.
#   tier 2  mcmc, via cross::run_branches(). Sampling is stochastic, so the
#           question is not "how long did one call take" but "how many
#           effective draws per second, and did the chains converge". bench's
#           model - many iterations, check = TRUE, mem_alloc off the R heap -
#           answers none of that. run_branches() hands back a result
#           list-column that can hold whatever we like.
#
# Diagnostics use {posterior}, not {coda}. coda::effectiveSize() fits an AR
# model per chain with no between-chain information, so it reports a large ESS
# for chains stuck in different modes - exactly the failure a sampler
# regression test exists to catch. posterior::rhat() is rank-normalised and
# folded, and ess_bulk()/ess_tail() separate the centre from the tails.
# Vehtari et al. (2021), doi:10.1214/20-BA1221.
#
# Everything the expression needs arrives through the environment: cross runs
# it in a callr subprocess that cannot see this session.

library(cross)
library(bench)
library(here)
library(fs)
library(withr)
library(dplyr)

run_dir <- here("2026-09-21-mcmc-suite")
source(here("provenance.R"))

greta_repo <- path_expand(Sys.getenv("GRETA_REPO", "~/github/greta-dev/greta"))
models_file <- path(here("suite"), "models.R")

branches <- strsplit(
  Sys.getenv(
    "GRETA_SUITE_BRANCHES",
    "main,data-interface-into-log-prob-739"
  ),
  ","
)[[1]]

# four chains is the minimum the diagnostics are calibrated for, and ESS > 400
# is where they become trustworthy rather than where accuracy is sufficient
chains <- as.integer(Sys.getenv("GRETA_SUITE_CHAINS", "4"))
n_samples <- as.integer(Sys.getenv("GRETA_SUITE_SAMPLES", "1000"))
warmup <- as.integer(Sys.getenv("GRETA_SUITE_WARMUP", "1000"))
reps <- as.integer(Sys.getenv("GRETA_SUITE_REPS", "5"))
iterations <- as.integer(Sys.getenv("GRETA_SUITE_ITERATIONS", "20"))

subprocess_env <- c(
  callr::rcmd_safe_env(),
  GRETA_SUITE_MODELS = models_file,
  GRETA_SUITE_CHAINS = as.character(chains),
  GRETA_SUITE_SAMPLES = as.character(n_samples),
  GRETA_SUITE_WARMUP = as.character(warmup),
  GRETA_SUITE_REPS = as.character(reps),
  GRETA_SUITE_ITERATIONS = as.character(iterations)
)

# ---- tier 1: deterministic work, measured with bench -------------------------

timings <- with_dir(
  greta_repo,
  bench_branches(
    {
      library(greta)
      library(bench)
      source(Sys.getenv("GRETA_SUITE_MODELS"))
      iterations <- as.integer(Sys.getenv("GRETA_SUITE_ITERATIONS"))

      built <- lapply(greta_bench_models, function(f) f())
      # build each model once before timing: TensorFlow traces on first use,
      # and that one-off cost is a different question from steady state
      for (m in built) {
        invisible(opt(m, optimiser = adam(), max_iterations = 5))
      }

      bench::press(
        model = names(built),
        {
          m <- built[[model]]
          bench::mark(
            build = greta_bench_models[[model]](),
            opt_adam = opt(m, optimiser = adam(), max_iterations = 100),
            # the branches draw different numbers, so results cannot be
            # compared for equality
            check = FALSE,
            filter_gc = FALSE,
            min_iterations = iterations,
            max_iterations = iterations * 2
          )
        }
      )
    },
    current = FALSE,
    branches = branches,
    args_callr = list(env = subprocess_env)
  )
)

# ---- tier 2: sampling quality, measured per replicate ------------------------

sampling <- with_dir(
  greta_repo,
  run_branches(
    {
      library(greta)
      source(Sys.getenv("GRETA_SUITE_MODELS"))

      chains <- as.integer(Sys.getenv("GRETA_SUITE_CHAINS"))
      n_samples <- as.integer(Sys.getenv("GRETA_SUITE_SAMPLES"))
      warmup <- as.integer(Sys.getenv("GRETA_SUITE_WARMUP"))
      reps <- as.integer(Sys.getenv("GRETA_SUITE_REPS"))

      one_run <- function(model_name, rep) {
        model <- greta_bench_models[[model_name]]()

        elapsed <- system.time(
          draws <- mcmc(
            model,
            n_samples = n_samples,
            warmup = warmup,
            chains = chains,
            verbose = FALSE
          )
        )[["elapsed"]]

        # posterior coerces greta.s mcmc.list itself. Reshaping it by hand
        # scrambles chains against variables, which shows up as Rhat of Inf
        # and a bulk-ESS of 4 -- diagnostics of the reshape, not the sampler
        d <- posterior::as_draws_array(draws)
        summ <- posterior::summarise_draws(
          d,
          rhat = posterior::rhat,
          ess_bulk = posterior::ess_bulk,
          ess_tail = posterior::ess_tail
        )

        data.frame(
          model = model_name,
          rep = rep,
          elapsed = elapsed,
          n_variables = nrow(summ),
          # the slowest-mixing parameter limits a run, but the minimum is the
          # fragile one: a parameter that never moved zeroes it however well
          # the rest mixed. Carry the median too.
          ess_bulk_min = min(summ$ess_bulk, na.rm = TRUE),
          ess_bulk_median = median(summ$ess_bulk, na.rm = TRUE),
          ess_tail_min = min(summ$ess_tail, na.rm = TRUE),
          n_below_400 = sum(summ$ess_bulk < 400, na.rm = TRUE),
          rhat_max = max(summ$rhat, na.rm = TRUE),
          n_rhat_above_1.01 = sum(summ$rhat > 1.01, na.rm = TRUE),
          ess_bulk_min_per_sec = min(summ$ess_bulk, na.rm = TRUE) / elapsed
        )
      }

      grid <- expand.grid(
        model_name = names(greta_bench_models),
        rep = seq_len(reps),
        stringsAsFactors = FALSE
      )

      do.call(rbind, Map(one_run, grid$model_name, grid$rep))
    },
    current = FALSE,
    branches = branches,
    args_callr = list(env = subprocess_env)
  )
)

sampling_results <- sampling$result |>
  setNames(sampling$branch) |>
  bind_rows(.id = "branch")

# SHAs at measure time: branches move, so resolving them at render time would
# record commits that were never measured
saveRDS(
  list(
    timings = timings,
    sampling = sampling_results,
    branches = branches,
    shas = vapply(branches, function(b) git_sha(greta_repo, b), character(1)),
    design = list(
      chains = chains,
      n_samples = n_samples,
      warmup = warmup,
      reps = reps,
      iterations = iterations
    ),
    provenance = host_provenance()
  ),
  path(run_dir, "results.rds"),
  compress = "xz"
)

cat("wrote", path(run_dir, "results.rds"), "\n")
