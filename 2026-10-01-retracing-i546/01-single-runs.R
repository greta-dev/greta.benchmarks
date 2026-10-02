# Render single-run.qmd once against each of CRAN (greta 0.6.0), main and
# greta#843.
#
#   Rscript --quiet --vanilla 2026-10-01-retracing-i546/01-single-runs.R
#
# Each version is installed from its commit into a library of its own under
# libs/ (gitignored), and the document is rendered with that library first on
# R_LIBS. The document prints which greta it loaded, so a render against the
# wrong build shows on the page rather than passing unnoticed.
#
# Rendered once, to markdown, so each version's numbers come from one run;
# the html is converted from that markdown rather than run again.

library(here)
library(fs)
library(quarto)
library(withr)

run_dir <- here("2026-10-01-retracing-i546")
source(here("R", "provenance.R"))

greta_repo <- path_expand(Sys.getenv("GRETA_REPO", "~/github/greta-dev/greta"))
versions <- c(
  CRAN = "v0.6.0",
  main = "main",
  `#843` = "faster-hessians-i546"
)

install_version <- function(label, branch) {
  sha <- git_sha(greta_repo, branch)
  source_dir <- path(tempdir(), paste0("greta-", sha))
  dir_create(source_dir)
  extracted <- system(sprintf(
    "git -C %s archive %s | tar -x -C %s",
    shQuote(greta_repo),
    sha,
    shQuote(source_dir)
  ))
  stopifnot(extracted == 0)

  lib <- path(run_dir, "libs", branch)
  dir_create(lib)
  installed <- system2(
    "R",
    c("CMD", "INSTALL", "--no-test-load", paste0("--library=", lib), source_dir)
  )
  stopifnot(installed == 0)

  list(label = label, branch = branch, sha = sha, lib = lib)
}

render_version <- function(build) {
  markdown <- paste0("single-run-", build$branch, ".md")
  with_envvar(
    c(R_LIBS = paste(c(build$lib, .libPaths()), collapse = ":")),
    quarto_render(
      path(run_dir, "single-run.qmd"),
      output_file = markdown,
      execute_params = list(
        label = build$label,
        branch = build$branch,
        sha = build$sha,
        out_rds = path(run_dir, paste0("single-run-", build$branch, ".rds"))
      )
    )
  )
  quarto_render(
    path(run_dir, markdown),
    output_format = "html",
    quarto_args = c("--metadata", "embed-resources:true")
  )
}

for (label in names(versions)) {
  render_version(install_version(label, versions[[label]]))
}
