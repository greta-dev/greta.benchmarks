# Render the write-up from the numbers 01-measure.R produced.
#
#   Rscript --quiet --vanilla 2026-09-21-data-variables-cost/02-report.R

library(here)
library(fs)
library(quarto)

quarto_render(path(here("2026-09-21-data-variables-cost"), "results.qmd"))
