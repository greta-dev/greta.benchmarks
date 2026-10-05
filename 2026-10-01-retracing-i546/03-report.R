# Render the report template, report.qmd, from this run's store, with the
# tracing runs from 02-tracing-runs.R as its further measurements, to
# report.html and report.md here.
#
#   Rscript --quiet --vanilla 2026-10-01-retracing-i546/03-report.R

library(here)

source(here("packages.R"))
tar_source()

run_dir <- "2026-10-01-retracing-i546"

render_report(
  store = file.path(run_dir, "_targets-quick"),
  out_dir = run_dir,
  title = "Retracing on CRAN, main and greta#843",
  further = file.path(run_dir, "further.qmd")
)
