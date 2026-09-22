# Can each example reach the suite's ESS target at all, and what does it cost?
#
#   Rscript --quiet --vanilla 2026-09-21-example-baseline/01-measure.R
#
# The pipeline's sampling tier fixes the quality and measures the cost, so the
# only way an example can fail is to run out of time - `hit_cap`. Before
# comparing two branches it is worth knowing which examples can reach the
# target on one, and roughly how long each takes, because that sets the run
# time of every comparison afterwards.
#
# This also settles a question the earlier mcmc-suite could not. That harness
# reported that 4 of 5 examples "never converge", but it sampled at 4 chains x
# 1000, which is too short for these posteriors - `linear` has an intercept and
# slope correlated at -0.97 and needs several thousand draws before bulk-ESS
# clears a few hundred. Fixing the target and letting the chain grow removes
# that confound entirely.
#
# One greta, not a branch comparison, so no {cross}: this is about the examples,
# and the same installed greta is used for all five. Each example runs in its
# own fresh R process, because greta and TensorFlow accumulate state over a
# session and an example measured late would be measured on a fuller process
# than one measured early.

library(here)
library(fs)
library(callr)
library(dplyr)

run_dir <- here("2026-09-21-example-baseline")
source(here("R", "provenance.R"))

examples_file <- here("R", "examples.R")
target_file <- here("R", "sample-to-target.R")
stopifnot(file_exists(examples_file), file_exists(target_file))

# the pipeline's defaults, so this measures what a real run would do
target_ess <- as.integer(Sys.getenv("GRETA_TARGET_ESS", "1000"))
time_limit <- as.integer(Sys.getenv("GRETA_TIME_LIMIT", "300"))

one_example <- function(
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
  cbind(example = example, row)
}

source(examples_file)
example_names <- names(bench_examples())

results <- lapply(
  example_names,
  function(example) {
    message("measuring ", example)
    r(
      one_example,
      args = list(
        examples_file = examples_file,
        target_file = target_file,
        example = example,
        target_ess = target_ess,
        time_limit = time_limit
      )
    )
  }
) |>
  bind_rows()

saveRDS(
  list(
    results = results,
    target_ess = target_ess,
    time_limit = time_limit,
    greta_version = as.character(packageVersion("greta")),
    provenance = host_provenance()
  ),
  path(run_dir, "results.rds"),
  compress = "xz"
)

print(results, row.names = FALSE, digits = 4)
cat("\nwrote", path(run_dir, "results.rds"), "\n")
