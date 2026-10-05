# Render tracing-run.qmd `reps` times against each of CRAN (greta 0.6.0), main
# and greta#843, each in a fresh R session, so that each model's mcmc() call,
# and the opt(hessian = TRUE) call, includes tracing.
#
#   Rscript --quiet --vanilla 2026-10-01-retracing-i546/02-tracing-runs.R
#
# Run after 01-measure-suite.R: the warmup and sampling iterations, chains,
# cores and number of runs are read from its store, so the tracing runs use the
# same settings as the suite.
#
# Each version is installed from its commit into a library of its own under
# libs/ (gitignored), and the document is rendered with that library first on
# R_LIBS. The document prints which greta it loaded, so a render against the
# wrong build shows on the page rather than passing unnoticed. Each version's
# iterations per draw is measured in a process of its own, so the measurement's
# tracing does not reach the tracing runs.
#
# Every run writes tracing-run-<branch>-run<n>.rds; the markdown and html are
# from the last run.

library(here)
library(fs)
library(quarto)
library(withr)
library(targets)

run_dir <- here("2026-10-01-retracing-i546")
source(here("R", "provenance.R"))

store <- path(run_dir, "_targets-quick")
settings <- list(
  warmup_iterations = tar_read(warmup_iterations, store = store),
  sample_iterations = tar_read(sample_iterations, store = store),
  chains = tar_read(mcmc_chains, store = store),
  cores = tar_read(mcmc_cores, store = store),
  runs = tar_read(reps, store = store)
)

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

  iterations_per_draw <- callr::r(
    function(iterations_file) {
      library(greta)
      source(iterations_file)
      iterations_per_draw()
    },
    args = list(iterations_file = here("R", "iterations.R")),
    libpath = c(lib, .libPaths())
  )

  list(
    label = label,
    branch = branch,
    sha = sha,
    lib = lib,
    iterations_per_draw = iterations_per_draw
  )
}

render_run <- function(build, run) {
  markdown <- paste0("tracing-run-", build$branch, ".md")
  with_envvar(
    c(R_LIBS = paste(c(build$lib, .libPaths()), collapse = ":")),
    quarto_render(
      path(run_dir, "tracing-run.qmd"),
      output_file = markdown,
      execute_params = c(
        list(
          label = build$label,
          branch = build$branch,
          sha = build$sha,
          out_rds = path(
            run_dir,
            paste0("tracing-run-", build$branch, "-run", run, ".rds")
          ),
          run = run,
          iterations_per_draw = build$iterations_per_draw
        ),
        settings
      )
    )
  )
  markdown
}

for (label in names(versions)) {
  build <- install_version(label, versions[[label]])
  for (run in seq_len(settings$runs)) {
    markdown <- render_run(build, run)
  }
  quarto_render(
    path(run_dir, markdown),
    output_format = "html",
    quarto_args = c("--metadata", "embed-resources:true")
  )
}
