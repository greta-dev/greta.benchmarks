# The standing suite at the quick and standard tiers, main against
# thinning-i318 (greta#318: thin + 1 iterations per draw).
#
#   Rscript --quiet --vanilla 2026-09-29-thinning-i318/01-measure.R
#
# Each tier runs the root pipeline with its `tier` and `branches` targets
# swapped in, into a store of its own, so the standing pipeline and its store
# are left alone.
#
# The results.rds beside this file came from the equivalent run by hand: the
# two lines edited in the root _targets.R, tar_make(callr_function = NULL),
# and the targets below read out of the root store straight after each tier.

library(here)
library(fs)
library(targets)

run_dir <- here("2026-09-29-thinning-i318")
branches <- c("main", "thinning-i318")

run_tier <- function(tier) {
  script <- readLines(here("_targets.R"))
  script <- sub(
    'tier <- "[a-z]+" \\|>',
    sprintf('tier <- "%s" |>', tier),
    script
  )
  script <- sub(
    "branches <- c\\([^)]*\\) \\|>",
    sprintf(
      "branches <- c(%s) |>",
      paste0('"', branches, '"', collapse = ", ")
    ),
    script
  )
  script_path <- path(run_dir, sprintf("_targets-%s.R", tier))
  writeLines(script, script_path)
  store <- path(run_dir, sprintf("_targets-%s", tier))

  tar_make(script = script_path, store = store, callr_function = NULL)

  list(
    shas = tar_read(shas, store = store),
    timings = tar_read(timings_relative, store = store),
    sampling = tar_read(sampling, store = store),
    agreement = tar_read(agreement, store = store)
  )
}

results <- lapply(c(quick = "quick", standard = "standard"), run_tier)
saveRDS(results, path(run_dir, "results.rds"))
