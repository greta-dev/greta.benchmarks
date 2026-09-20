# Does tuning diag_sd on the right `n` sample more efficiently?
#
#   Rscript --quiet --vanilla 2026-09-20-tune-diag-sd/01-measure.R
#
# tune_diag_sd() shrinks the sample posterior variance towards 5e-3 before using
# it as the proposal scale. That shrinkage is Stan's regularised variance
# estimator, term for term:
#
#   stan/mcmc/var_adaptation.hpp
#     double n = static_cast<double>(estimator_.num_samples());
#     var = (n / (n + 5.0)) * var + 1e-3 * (5.0 / (n + 5.0)) * Ones;
#
#   greta R/sampler_class.R
#     shrinkage  <- 1 / (n + 5)
#     var_shrunk <- n * shrinkage * sample_var + 5e-3 * shrinkage
#
# In Stan `n` is the number of samples the variance was estimated from. greta
# passed `sum(!self$accept_history)`, a count of *rejected* proposals, so the
# weight on the sample variance is lower than intended and diag_sd is pulled
# harder towards 5e-3 - a smaller proposal scale than the data support.
#
# The question this run answers is whether that costs anything measurable.
#
# ESS per second, not wall time. The change alters how the sampler explores,
# not how much work it does per iteration, so a timing comparison would miss it
# entirely. Wall time is recorded anyway, to show the fix is not simply slower.
#
# Warmup is swept because the effect should be largest when it is short: n/(n+5)
# is furthest from 1 there, and the `n > 5` gate can fail outright when the
# rejection count is small, leaving diag_sd untuned for the whole run.
#
# The tuned diag_sd values are recorded alongside as the direct reading of what
# changed, and Rhat and acceptance come too - so that a gain in ESS cannot be
# mistaken for a chain that has quietly stopped mixing.

library(cross)
library(here)
library(withr)
library(fs)
library(dplyr)
library(purrr)

run_dir <- here("2026-09-20-tune-diag-sd")

# git_sha() and host_provenance() live here, and are needed when the results are
# saved at the end - sourced up front so a long run cannot die on the last line
source(here("provenance.R"))

greta_repo <- path_expand(Sys.getenv("GRETA_REPO", "~/github/greta-dev/greta"))
models_file <- path(here("suite"), "models.R")
stopifnot(file_exists(models_file))

branch_fix <- Sys.getenv("GRETA_FIX_BRANCH", "tune-diag-sd-n")
branch_reference <- "main"
branches <- c(branch_reference, branch_fix)

# Short warmups first: that is where the two values of n differ most in relative
# terms, and where the gate can fail.
warmups <- Sys.getenv("GRETA_TDS_WARMUPS", "50,200,1000")

# Replicates per (branch, model, warmup). Higher than a timing run would need,
# because ESS is itself an estimate: the jit comparison only resolved a 4.8%
# difference at n = 50 against a within-branch spread of the same order, and a
# small run of a real effect looks exactly like no effect.
n_reps <- Sys.getenv("GRETA_TDS_REPS", "10")

# Everything the expression needs has to arrive through the environment: it is
# evaluated in a subprocess and cannot see anything in this session. Passing
# these as variables looks like it works and fails at run time.
subprocess_env <- c(
  callr::rcmd_safe_env(),
  GRETA_TDS_MODELS = models_file,
  GRETA_TDS_WARMUPS = warmups,
  GRETA_TDS_REPS = n_reps,
  GRETA_TDS_CHAINS = Sys.getenv("GRETA_TDS_CHAINS", "4"),
  GRETA_TDS_SAMPLES = Sys.getenv("GRETA_TDS_SAMPLES", "1000")
)

# cross operates on the git repo in the working directory, so the run has to
# happen inside the greta checkout. with_dir() restores the old directory on the
# way out, including if run_branches() errors.
#
# current = FALSE on purpose: the default prepends whatever is checked out and
# labels it as a branch, so a script naming branch_fix would record the wrong
# commit without ever looking wrong.
raw <- with_dir(
  greta_repo,
  run_branches(
    {
      library(greta)

      source(Sys.getenv("GRETA_TDS_MODELS"))
      warmups <- as.integer(strsplit(Sys.getenv("GRETA_TDS_WARMUPS"), ",")[[1]])
      n_reps <- as.integer(Sys.getenv("GRETA_TDS_REPS"))
      chains <- as.integer(Sys.getenv("GRETA_TDS_CHAINS"))
      n_samples <- as.integer(Sys.getenv("GRETA_TDS_SAMPLES"))

      # the proposal scale the sampler settled on, read off afterwards. This is
      # the quantity the change acts on, so it is the cheapest signal that the
      # two branches did anything different at all
      tuned_diag_sd <- function(draws) {
        samplers <- attr(draws, "model_info")$samplers
        mean(vapply(samplers, \(s) mean(s$parameters$diag_sd), numeric(1)))
      }

      # gelman.diag() errors on some posteriors rather than returning a value,
      # and a failed diagnostic should not lose the whole cell
      safe_rhat <- function(draws) {
        tryCatch(
          max(coda::gelman.diag(draws, multivariate = FALSE)$psrf[, 1]),
          error = function(e) NA_real_
        )
      }

      one_run <- function(model_name, warmup, rep, built) {
        model <- built[[model_name]]

        elapsed <- system.time(
          draws <- mcmc(
            model,
            n_samples = n_samples,
            warmup = warmup,
            chains = chains,
            verbose = FALSE
          )
        )[["elapsed"]]

        ess <- coda::effectiveSize(draws)

        data.frame(
          model = model_name,
          warmup = warmup,
          rep = rep,
          elapsed = elapsed,
          # the slowest-mixing parameter is what limits a run, so carry the
          # minimum as well as the mean rather than an average that hides it
          ess_min = min(ess),
          ess_mean = mean(ess),
          ess_min_per_sec = min(ess) / elapsed,
          rhat_max = safe_rhat(draws),
          diag_sd = tuned_diag_sd(draws)
        )
      }

      # build each model once, and take one short run per model first:
      # TensorFlow traces on the first call, and that one-off cost is a
      # different question from steady-state sampling
      built <- lapply(greta_bench_models, \(f) f())
      for (m in built) {
        invisible(mcmc(
          m,
          n_samples = 20,
          warmup = 20,
          chains = chains,
          verbose = FALSE
        ))
      }

      grid <- expand.grid(
        model_name = names(built),
        warmup = warmups,
        rep = seq_len(n_reps),
        stringsAsFactors = FALSE
      )

      do.call(
        rbind,
        Map(
          \(model_name, warmup, rep) one_run(model_name, warmup, rep, built),
          grid$model_name,
          grid$warmup,
          grid$rep
        )
      )
    },
    current = FALSE,
    branches = branches,
    args_callr = list(env = subprocess_env)
  )
)

results <- raw |>
  set_names(branches) |>
  imap(\(x, branch) transform(x, branch = branch)) |>
  bind_rows()

# SHAs are captured here, at measure time. Branches move, so resolving them when
# the report renders would record commits that were never measured.
saveRDS(
  list(
    results = results,
    branches = c(reference = branch_reference, fix = branch_fix),
    shas = vapply(branches, \(b) git_sha(greta_repo, b), character(1)),
    design = list(
      warmups = as.integer(strsplit(warmups, ",")[[1]]),
      n_reps = as.integer(n_reps),
      chains = as.integer(Sys.getenv("GRETA_TDS_CHAINS", "4")),
      n_samples = as.integer(Sys.getenv("GRETA_TDS_SAMPLES", "1000"))
    ),
    provenance = host_provenance()
  ),
  path(run_dir, "results.rds"),
  compress = "xz"
)

cat("wrote", path(run_dir, "results.rds"), "\n")
