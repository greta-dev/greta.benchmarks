# Render a suite result into markdown.
#
#   Rscript --quiet --vanilla suite/report.R suite/results/<file>.rds
#
# Separate from run-suite.R so a wording fix does not cost a re-run.

library(here)
library(fs)
library(quarto)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1) {
  stop("give one results file:\n  Rscript suite/report.R suite/results/<file>.rds",
       call. = FALSE)
}

quarto_render(
  path(here("suite"), "report.qmd"),
  execute_params = list(results = path_abs(args[[1]]))
)
