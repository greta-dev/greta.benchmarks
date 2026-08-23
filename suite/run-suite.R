# Run the benchmark suite across git branches, locally.
#
#   Rscript --quiet --vanilla suite/run-suite.R my-branch main
#
# Compares the named branches of greta on the same model set. Two branches
# minimum; the first is the one under test. Results go to
# suite/results/<date>-<branches>.rds, which suite/report.R renders.
#
# {cross} installs each branch and runs the expression in a subprocess, so the
# expression below has to be self-contained: it sources models.R by absolute
# path rather than closing over anything here.
#
# This is a local tool. It is not wired to CI, and is not meant to be - it takes
# minutes per branch, and it is for checking a change by hand before opening a
# PR.

library(cross)
library(bench)
library(here)
library(fs)
library(withr)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) {
  stop(
    "give at least two branches, the one under test first:\n",
    "  Rscript --quiet --vanilla suite/run-suite.R my-branch main",
    call. = FALSE
  )
}
branches <- args

# git_sha() and host_provenance() live here, and are needed when the results are
# saved at the end - sourced up front so a long run cannot die on the last line
source(here("provenance.R"))

greta_repo <- path_expand(Sys.getenv("GRETA_REPO", "~/github/greta-dev/greta"))
models_file <- path(here("suite"), "models.R")

# how many times each cell runs. The default is deliberately high: a difference
# of tens of milliseconds against a within-branch spread of the same size is
# invisible at ten iterations, and silently so - a small run of a real effect
# looks exactly like no effect.
n_iterations <- as.integer(Sys.getenv("GRETA_BENCH_ITERATIONS", "30"))

# which models to run. The default is all of them; GRETA_BENCH_MODELS trims it
# for a quick check. hierarchical_slopes_corr is the only cholesky-path model,
# so a trimmed set that drops it cannot see cholesky regressions.
model_names <- Sys.getenv("GRETA_BENCH_MODELS", "")
model_names <- if (nzchar(model_names)) {
  strsplit(model_names, ",")[[1]]
} else {
  NULL
}

results_dir <- path(here("suite"), "results")
dir_create(results_dir)

# cross operates on the git repo in the working directory, so the run has to
# happen inside the greta checkout. with_dir() restores the old directory on the
# way out, including if bench_branches() errors.
# Everything the expression needs has to arrive through the environment: it is
# evaluated in a subprocess and cannot see anything in this session. Passing
# these as variables looks like it works and fails at run time.
subprocess_env <- c(
  callr::rcmd_safe_env(),
  GRETA_SUITE_MODELS = models_file,
  GRETA_SUITE_ITERATIONS = as.character(n_iterations),
  GRETA_SUITE_SUBSET = paste(model_names, collapse = ",")
)

# cross operates on the git repo in the working directory, so the run has to
# happen inside the greta checkout. with_dir() restores the old directory on the
# way out, including if bench_branches() errors.
timings <- with_dir(
  greta_repo,
  bench_branches(
    {
      library(greta)
      library(bench)

      source(Sys.getenv("GRETA_SUITE_MODELS"))
      iterations <- as.integer(Sys.getenv("GRETA_SUITE_ITERATIONS"))
      subset <- Sys.getenv("GRETA_SUITE_SUBSET")

      models <- greta_bench_models
      if (nzchar(subset)) {
        models <- models[strsplit(subset, ",")[[1]]]
      }

      # build each model once outside the timing: model() is itself a task
      # below, and tracing on first use is a separate question from steady state
      built <- lapply(models, function(f) f())
      for (m in built) {
        invisible(opt(m, optimiser = adam(), max_iterations = 5))
      }

      bench::press(
        model = names(built),
        {
          m <- built[[model]]
          bench::mark(
            build = models[[model]](),
            opt_adam = opt(m, optimiser = adam(), max_iterations = 100),
            mcmc_short = mcmc(
              m,
              n_samples = 100,
              warmup = 100,
              chains = 1,
              verbose = FALSE
            ),
            # the branches draw different numbers, and mcmc() does not respect
            # set.seed() (greta #285, #427), so results cannot be compared
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

stamp <- format(Sys.Date(), "%Y-%m-%d")
out <- path(results_dir, paste0(stamp, "-", paste(branches, collapse = "-vs-"), ".rds"))

saveRDS(
  list(
    timings = timings,
    branches = branches,
    n_iterations = n_iterations,
    shas = vapply(branches, function(b) git_sha(greta_repo, b), character(1)),
    provenance = host_provenance()
  ),
  out,
  compress = "xz"
)

cat("wrote", out, "\n")
