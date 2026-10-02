# Render the write-up from the numbers 01-time-per-draw.R and 02-efficiency.R
# produced, to results.html and results.md.
#
#   Rscript --quiet --vanilla 2026-10-01-iterations-and-efficiency-i318/03-report.R

library(here)
library(fs)
library(quarto)

results_qmd <- path(
  here("2026-10-01-iterations-and-efficiency-i318"),
  "results.qmd"
)

# html first: embedding its figures deletes results_files/, which the
# markdown version links to, so the markdown has to be rendered after it
quarto_render(results_qmd, output_format = "html")
quarto_render(results_qmd, output_format = "gfm")
