# The standing suite at the quick tier, on CRAN (greta 0.6.0), main and
# greta#843.
#
#   Rscript --quiet --vanilla 2026-10-01-retracing-i546/02-measure-suite.R
#
# The root pipeline with its `tier` target swapped in, run into a store of its
# own, so the standing pipeline and its store are left alone. Its `branches`
# target has to name these three versions already; the script stops if it does
# not. The root report is left out of the copy: it would render from the
# standing store, not this one; 03-report.R renders it from this one. About 10
# minutes, installs included.

library(here)
library(fs)
library(targets)

run_dir <- here("2026-10-01-retracing-i546")
tier <- "quick"
expected_branches <- c("v0.6.0", "main", "faster-hessians-i546")

script <- readLines(here("_targets.R"))
script <- sub(
  'tier <- "[a-z]+" \\|>',
  sprintf('tier <- "%s" |>', tier),
  script
)
script <- script[!grepl("tar_quarto\\(", script)]
script_path <- path(run_dir, sprintf("_targets-%s.R", tier))
writeLines(script, script_path)
store <- path(run_dir, sprintf("_targets-%s", tier))

tar_make(
  names = "branches",
  script = script_path,
  store = store,
  callr_function = NULL
)
if (!identical(unname(tar_read(branches, store = store)), expected_branches)) {
  stop(
    "_targets.R's branches are not ",
    paste(expected_branches, collapse = ", "),
    call. = FALSE
  )
}

tar_make(script = script_path, store = store, callr_function = NULL)

# for results.qmd, the write-up before the report template, which reads this
# rather than the store
saveRDS(
  list(
    tier = tier,
    shas = tar_read(shas, store = store),
    iterations = tar_read(iterations, store = store),
    timings = tar_read(timings, store = store),
    sampling = tar_read(sampling, store = store),
    agreement = tar_read(agreement, store = store),
    posterior_comparison = tar_read(posterior_comparison, store = store),
    fit_diagnostics = tar_read(fit_diagnostics, store = store),
    provenance = tar_read(provenance, store = store)
  ),
  path(run_dir, "results.rds")
)
