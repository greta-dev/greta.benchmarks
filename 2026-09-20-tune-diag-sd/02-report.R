# Render the write-up from the numbers 01-measure.R produced.
#
#   Rscript --quiet --vanilla 2026-09-20-tune-diag-sd/02-report.R
#
# Separate from the measurement so a wording fix does not cost a re-run. The
# order is the only thing holding the numbers and the prose together: measure
# first, report second.

library(here)
library(fs)
library(quarto)

quarto_render(path(here("2026-09-20-tune-diag-sd"), "results.qmd"))
