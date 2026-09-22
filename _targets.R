# The greta benchmark suite. See README.md for how to run it and what the
# tiers cost.
#
#   targets::tar_make(callr_function = NULL)
#
# callr_function = NULL is required: tar_make() otherwise runs the pipeline in
# its own callr process, and {cross} spawns further callr subprocesses and pak
# installs inside that. The nesting segfaults. Diagnosis in AGENTS.md.

source("packages.R")

tar_source()

tar_assign({
  # "quick" before a commit, "standard" before a PR, "thorough" before a CRAN
  # release. R/tiers.R has the settings and what each costs.
  tier <- "quick" |> tar_target()

  settings <- tier_settings(tier) |> tar_target()
  example_names <- settings$examples |> tar_target()
  bench_iterations <- settings$bench_iterations |> tar_target()
  target_ess <- settings$target_ess |> tar_target()
  reps <- settings$reps |> tar_target()
  time_limit <- settings$time_limit |> tar_target()

  # greta and greta.benchmarks are assumed to share a parent directory
  greta_repo <- path(path_dir(here()), "greta") |> tar_target()

  branches <- c("main", "data-interface-into-log-prob-739") |> tar_target()
  reference <- branches[[1]] |> tar_target()
  under_test <- branches[[2]] |> tar_target()
  shas <- branch_shas(branches, greta_repo) |> tar_target()

  # file targets, so editing either invalidates the measurement that used it
  examples_file <- here("R", "examples.R") |> tar_file()
  target_file <- here("R", "sample-to-target.R") |> tar_file()

  # both tiers in one cross call: run_branches() reinstalls every branch from
  # scratch per call, so two calls installed each branch twice
  measured <- measure_branches(
    branches,
    examples_file,
    target_file,
    greta_repo,
    bench_iterations,
    target_ess,
    reps,
    time_limit,
    example_names
  ) |>
    tar_target()

  timings <- branch_timings(measured) |> tar_target()
  sampling <- branch_sampling(measured) |> tar_target()
  rss <- branch_rss(measured) |> tar_target()

  # bench normalises against the single fastest row in whatever it is given, so
  # relative medians are computed per example x task - where the branch is the
  # only thing varying.
  timings_relative <- relative_timings(timings) |> tar_target()

  pooled_posterior <- pool_replicates(per_variable_posterior(sampling)) |>
    tar_target()

  posterior_comparison <- compare_posteriors(
    pooled_posterior,
    reference,
    under_test
  ) |>
    tar_target()

  agreement <- posterior_agreement(posterior_comparison) |> tar_target()

  provenance <- host_provenance() |> tar_target()

  report <- tar_quarto(path = "report.qmd")
})
