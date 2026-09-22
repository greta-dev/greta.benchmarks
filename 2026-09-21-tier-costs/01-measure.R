# What does each example cost, in each tier, at each target?
#
#   Rscript --quiet --vanilla 2026-09-21-tier-costs/01-measure.R
#
# The suite is about to grow tiers - a quick check you run before every commit,
# a standard one before a pull request, a thorough one before a release - and
# the only way to size those honestly is to know what a pass costs.
#
# Two things are measured per example:
#
#   deterministic  model() and opt(), the bench::mark tier. Per-iteration cost
#                  times the iteration count, plus the one-off warm-up.
#   sampling       sample_to_target() at several ESS targets, because the cost
#                  of the sampling tier is set by the target and not much else.
#
# Sampling cost does not scale linearly with the target. sample_to_target()
# always pays 2000 warmup and 2000 initial samples, so an example that reaches
# the target on that first pass costs the same at 200 as at 1000 - only the
# ones that have to grow get more expensive. Measuring several targets shows
# which is which, and that is what decides where the tier boundaries go.
#
# One greta throughout, one fresh process per measurement.

library(here)
library(fs)
library(callr)
library(bench)
library(dplyr)

run_dir <- here("2026-09-21-tier-costs")
source(here("R", "provenance.R"))

examples_file <- here("R", "examples.R")
target_file <- here("R", "sample-to-target.R")
stopifnot(file_exists(examples_file), file_exists(target_file))

iterations <- as.integer(Sys.getenv("GRETA_TIER_ITERATIONS", "30"))
targets <- as.integer(strsplit(
  Sys.getenv("GRETA_TIER_TARGETS", "200,500,1000"),
  ","
)[[1]])
time_limit <- as.integer(Sys.getenv("GRETA_TIER_TIME_LIMIT", "300"))

source(examples_file)
example_names <- names(bench_examples())

# ---- deterministic tier ------------------------------------------------------

deterministic_one <- function(examples_file, example, iterations) {
  library(greta)
  library(bench)
  source(examples_file)

  examples <- bench_examples()

  # the warm-up is a real cost of the tier - TensorFlow traces on first use -
  # so it is timed rather than hidden
  warmup_time <- system.time({
    m <- examples[[example]]()
    invisible(opt(m, optimiser = adam(), max_iterations = 5))
  })[["elapsed"]]

  marked <- bench::mark(
    model = examples[[example]](),
    opt = opt(m, optimiser = adam(), max_iterations = 100),
    check = FALSE,
    filter_gc = FALSE,
    min_iterations = iterations,
    max_iterations = iterations * 2
  )

  data.frame(
    example = example,
    task = as.character(marked$expression),
    median_ms = as.numeric(marked$median) * 1000,
    n_itr = marked$n_itr,
    total_seconds = as.numeric(marked$median) * marked$n_itr,
    warmup_seconds = warmup_time
  )
}

message("deterministic tier")
deterministic <- lapply(
  example_names,
  function(example) {
    message("  ", example)
    r(
      deterministic_one,
      args = list(
        examples_file = examples_file,
        example = example,
        iterations = iterations
      )
    )
  }
) |>
  bind_rows()

# ---- sampling tier, at each target ------------------------------------------

sampling_one <- function(
  examples_file,
  target_file,
  example,
  target_ess,
  time_limit
) {
  library(greta)
  source(examples_file)
  source(target_file)

  row <- sample_to_target(
    bench_examples()[[example]](),
    target_ess = target_ess,
    time_limit = time_limit
  )
  # the per-variable summary is not the question here and would bloat the file
  row$posterior <- NULL
  cbind(example = example, row)
}

message("sampling tier")
grid <- expand.grid(
  example = example_names,
  target_ess = targets,
  stringsAsFactors = FALSE
)

sampling <- Map(
  function(example, target_ess) {
    message("  ", example, " at target ", target_ess)
    r(
      sampling_one,
      args = list(
        examples_file = examples_file,
        target_file = target_file,
        example = example,
        target_ess = target_ess,
        time_limit = time_limit
      )
    )
  },
  grid$example,
  grid$target_ess
) |>
  bind_rows()

saveRDS(
  list(
    deterministic = deterministic,
    sampling = sampling,
    iterations = iterations,
    targets = targets,
    time_limit = time_limit,
    greta_version = as.character(packageVersion("greta")),
    provenance = host_provenance()
  ),
  path(run_dir, "results.rds"),
  compress = "xz"
)

cat("\n---- deterministic tier ----\n")
print(deterministic, row.names = FALSE, digits = 4)
cat("\n---- sampling tier ----\n")
print(
  sampling[, c(
    "example",
    "target_ess",
    "elapsed",
    "iterations",
    "ess_bulk_min",
    "hit_cap"
  )],
  row.names = FALSE,
  digits = 4
)
cat("\nwrote", path(run_dir, "results.rds"), "\n")
