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
  mcmc_iterations <- settings$mcmc_iterations |> tar_target()
  target_ess <- settings$target_ess |> tar_target()
  reps <- settings$reps |> tar_target()
  time_limit <- settings$time_limit |> tar_target()

  # greta and greta.benchmarks are assumed to share a parent directory
  greta_repo <- path(path_dir(here()), "greta") |> tar_target()

  # git refs, named as the report shows them. The first is the reference:
  # greta's current CRAN release, by its tag, since users upgrade from CRAN
  branches <- c(
    CRAN = "v0.6.0",
    main = "main",
    `#843` = "faster-hessians-i546"
  ) |>
    tar_target()
  comparisons <- branch_pairs(names(branches)) |> tar_target()
  # re-read on every run, so a branch that has moved to a new commit is
  # measured again, and one that has not is left alone
  shas <- branch_shas(branches, greta_repo) |>
    tar_target(cue = tar_cue(mode = "always"))

  # every mcmc() call: iterations, not arguments, so each version does the
  # same work whatever it runs per draw (AGENTS.md, "Compare at equal
  # iterations")
  warmup_iterations <- 2000 |> tar_target()
  sample_iterations <- 2000 |> tar_target()
  mcmc_chains <- 4 |> tar_target()
  mcmc_cores <- 4 |> tar_target()
  opt_iterations <- 100 |> tar_target()

  # file targets, so editing one invalidates the measurement that used it
  examples_file <- here("R", "examples.R") |> tar_file()
  target_file <- here("R", "sample-to-target.R") |> tar_file()
  iterations_file <- here("R", "iterations.R") |> tar_file()

  # both tiers in one cross call: run_branches() reinstalls every branch from
  # scratch per call, so two calls installed each branch twice
  measured <- measure_branches(
    shas,
    examples_file,
    target_file,
    iterations_file,
    greta_repo,
    bench_iterations,
    mcmc_iterations,
    warmup_iterations,
    sample_iterations,
    mcmc_chains,
    mcmc_cores,
    opt_iterations,
    target_ess,
    reps,
    time_limit,
    example_names
  ) |>
    tar_target()

  timings <- branch_timings(measured) |> tar_target()
  sampling <- branch_sampling(measured) |> tar_target()
  rss <- branch_rss(measured) |> tar_target()
  iterations <- branch_iterations(measured) |> tar_target()

  fits <- branch_fits(measured) |> tar_target()
  fit_draws <- tidy_fit_draws(fits) |> tar_target()
  fitted_values <- tidy_fitted(fits) |> tar_target()
  fit_diagnostics <- tidy_fit_diagnostics(fits) |> tar_target()

  # bench normalises against the single fastest row in whatever it is given, so
  # relative medians are computed per example x task - where the branch is the
  # only thing varying.
  timings_relative <- relative_timings(timings) |> tar_target()
  speed <- speed_table(timings_relative, comparisons) |> tar_target()
  sampling_speed <- sampling_table(sampling, comparisons) |> tar_target()

  pooled_posterior <- pool_replicates(per_variable_posterior(sampling)) |>
    tar_target()

  posterior_comparison <- compare_all_posteriors(
    pooled_posterior,
    comparisons
  ) |>
    tar_target()

  agreement <- posterior_agreement(posterior_comparison) |> tar_target()

  provenance <- host_provenance() |> tar_target()

})
