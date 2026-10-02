# Render the write-up from what 01-measure.R produced.
#
#   Rscript --quiet --vanilla 2026-09-30-trace-census-i546/02-report.R

library(here)
library(fs)
library(quarto)

quarto_render(path(here("2026-09-30-trace-census-i546"), "results.qmd"))
