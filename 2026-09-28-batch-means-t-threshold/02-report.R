# Render the write-up from the numbers 01-measure.R produced.
#
#   Rscript --quiet --vanilla 2026-09-28-batch-means-t-threshold/02-report.R

library(here)
library(fs)
library(quarto)

quarto_render(path(here("2026-09-28-batch-means-t-threshold"), "results.qmd"))
