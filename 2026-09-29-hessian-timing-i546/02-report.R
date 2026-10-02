# Render the write-up from the numbers 01-measure.R produced.
#
#   Rscript --quiet --vanilla 2026-09-29-hessian-timing-i546/02-report.R

library(here)
library(fs)
library(quarto)

quarto_render(path(here("2026-09-29-hessian-timing-i546"), "results.qmd"))
