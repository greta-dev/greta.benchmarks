# Is the low ESS greta, or is it the harness measuring itself?
#
#   Rscript --quiet --vanilla 2026-09-21-session-state-vs-ess/01-measure.R
#
# 2026-09-21-mcmc-suite reports that 4 of 5 models never clear bulk-ESS 400 and
# Rhat 1.01 at greta's defaults, on either branch. That reads as "greta does not
# converge", which contradicts dev/njt-todo.md, where `linear` on main outside
# any harness gave Rhat 1.005/1.005/1.002 and ESS 654/664/2871.
#
# Both cannot be true of the same sampler. The difference between them is not
# the model or the settings - it is that the harness runs all 25 mcmc() calls
# (5 models x 5 replicates) inside ONE R session per branch, which is the thing
# AGENTS.md forbids and which that harness does anyway.
#
# Three conditions, same model, same settings, same greta, differing only in
# what else has happened in the process first:
#
#   fresh    5 runs of `linear`, each in its own R process
#   session  5 runs of `linear`, all in one process
#   harness  the harness grid - 5 models x 5 replicates interleaved in one
#            process, exactly as 2026-09-21-mcmc-suite does it - and we read
#            the `linear` runs out of it
#
# fresh vs session isolates re-using a process for the same model.
# session vs harness isolates the other four models sharing the process.
#
# No {cross}: this is one greta against itself, not a branch comparison. The
# installed greta is used throughout so all three conditions see the same code.
#
# The whole per-variable summary is kept, not just the minimum, so questions
# about the distribution across variables can be asked without re-measuring.

library(here)
library(fs)
library(callr)
library(dplyr)

run_dir <- here("2026-09-21-session-state-vs-ess")
source(here("provenance.R"))

models_file <- path(here("suite"), "models.R")
stopifnot(file_exists(models_file))

# overridable so the script can be smoke-run at a fraction of the cost before
# it is trusted; the defaults are the ones 2026-09-21-mcmc-suite used
chains <- as.integer(Sys.getenv("GRETA_STATE_CHAINS", "4"))
n_samples <- as.integer(Sys.getenv("GRETA_STATE_SAMPLES", "1000"))
warmup <- as.integer(Sys.getenv("GRETA_STATE_WARMUP", "1000"))
reps <- as.integer(Sys.getenv("GRETA_STATE_REPS", "5"))
focus <- "linear"

# Run a grid of (model, rep) inside a single R process and return one row per
# variable per run. Defined as a string-free function passed to callr, so the
# child process gets it by value rather than closing over this session.
run_grid <- function(models_file, grid, chains, n_samples, warmup) {
  library(greta)
  source(models_file)

  one <- function(model_name, rep) {
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

    summ <- posterior::summarise_draws(
      posterior::as_draws_array(draws),
      rhat = posterior::rhat,
      ess_bulk = posterior::ess_bulk,
      ess_tail = posterior::ess_tail
    )

    data.frame(
      model = model_name,
      rep = rep,
      elapsed = elapsed,
      variable = summ$variable,
      rhat = summ$rhat,
      ess_bulk = summ$ess_bulk,
      ess_tail = summ$ess_tail
    )
  }

  do.call(rbind, Map(one, grid$model_name, grid$rep))
}

call_in_child <- function(grid) {
  r(
    run_grid,
    args = list(
      models_file = models_file,
      grid = grid,
      chains = chains,
      n_samples = n_samples,
      warmup = warmup
    )
  )
}

# ---- fresh: one process per measurement -------------------------------------

fresh <- lapply(
  seq_len(reps),
  function(rep) {
    call_in_child(data.frame(model_name = focus, rep = rep))
  }
) |>
  bind_rows() |>
  mutate(condition = "fresh")

# ---- session: one process, the same model repeatedly ------------------------

session <- call_in_child(
  data.frame(model_name = focus, rep = seq_len(reps))
) |>
  mutate(condition = "session")

# ---- harness: one process, the full interleaved grid ------------------------

# expand.grid varies the first factor fastest, so this is rep 1 of every model,
# then rep 2 of every model - the order 2026-09-21-mcmc-suite uses
harness_grid <- expand.grid(
  model_name = c(
    "linear",
    "multiple_linear",
    "hierarchical_linear",
    "hierarchical_slopes_corr",
    "wide_linear"
  ),
  rep = seq_len(reps),
  stringsAsFactors = FALSE
)

harness <- call_in_child(harness_grid) |>
  mutate(condition = "harness")

results <- bind_rows(fresh, session, harness)

saveRDS(
  list(
    results = results,
    focus = focus,
    design = list(
      chains = chains,
      n_samples = n_samples,
      warmup = warmup,
      reps = reps
    ),
    greta_version = as.character(packageVersion("greta")),
    provenance = host_provenance()
  ),
  path(run_dir, "results.rds"),
  compress = "xz"
)

cat("wrote", path(run_dir, "results.rds"), "\n")
