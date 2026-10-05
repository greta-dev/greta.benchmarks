# Do the two branches estimate the same posterior?
#
# Posterior means always differ between runs, so "are these the same" is not a
# question about matching numbers - it is whether they differ by more than
# Monte Carlo error:
#
#   z = (mean_a - mean_b) / sqrt(mcse_a^2 + mcse_b^2)
#
# NOT a two-sample KS test on the draws. KS assumes both samples are iid, MCMC
# draws are autocorrelated, so the null distribution is wider than the
# tabulated one and a correct sampler is rejected too often. That mistake is
# live in greta's own test helpers.

per_variable_posterior <- function(sampling) {
  sampling |>
    select(branch, example, rep, posterior) |>
    unnest(posterior)
}

#' Pool replicates within a branch.
#'
#' Replicates are independent runs, so means average and standard errors
#' combine as sqrt(sum(mcse^2)) / n.
pool_replicates <- function(per_variable) {
  per_variable |>
    group_by(branch, example, variable) |>
    summarise(
      reps = n(),
      mean = mean(mean),
      se_mean = sqrt(sum(mcse_mean^2)) / n(),
      sd = mean(sd),
      se_sd = sqrt(sum(mcse_sd^2)) / n(),
      across(c(q5, q25, q50, q75, q95), mean),
      ess_bulk = mean(ess_bulk),
      .groups = "drop"
    )
}

#' Compare two branches per variable, in MCSE units.
compare_posteriors <- function(pooled, reference, under_test) {
  one_branch <- function(which_branch) {
    pooled |>
      filter(branch == which_branch) |>
      select(example, variable, mean, se_mean, sd, se_sd)
  }

  inner_join(
    one_branch(reference),
    one_branch(under_test),
    by = c("example", "variable"),
    suffix = c("_ref", "_test")
  ) |>
    mutate(
      difference = mean_test - mean_ref,
      z_mean = difference / sqrt(se_mean_ref^2 + se_mean_test^2),
      z_sd = (sd_test - sd_ref) / sqrt(se_sd_ref^2 + se_sd_test^2)
    )
}

#' Every pair of branches, in the order given, the earlier one as the reference.
branch_pairs <- function(labels) {
  pairs <- utils::combn(labels, 2)
  data.frame(
    reference = pairs[1, ],
    test = pairs[2, ],
    comparison = paste(pairs[2, ], "vs", pairs[1, ])
  )
}

#' compare_posteriors() for every pair in `comparisons`.
compare_all_posteriors <- function(pooled, comparisons) {
  Map(
    function(reference, test, comparison) {
      compare_posteriors(pooled, reference, test) |>
        mutate(comparison = comparison, .before = 1)
    },
    comparisons$reference,
    comparisons$test,
    comparisons$comparison
  ) |>
    bind_rows() |>
    mutate(comparison = factor(comparison, levels = comparisons$comparison))
}

#' Add the ratio of the two branches in each comparison, as a column named for
#' it. A ratio above 1 means the test branch took longer than its reference.
add_ratios <- function(wide, comparisons) {
  ratios <- Map(
    function(reference, test) wide[[test]] / wide[[reference]],
    comparisons$reference,
    comparisons$test
  )
  bind_cols(wide, setNames(ratios, comparisons$comparison))
}

#' Median milliseconds per example x task, one column per branch, and the
#' ratios. `every_run` is timed_runs(): one row per timed run.
speed_table <- function(every_run, comparisons) {
  every_run |>
    group_by(example, task, branch) |>
    summarise(ms = 1000 * median(seconds), .groups = "drop") |>
    pivot_wider(names_from = branch, values_from = ms) |>
    add_ratios(comparisons)
}

#' Median seconds per 1000 effective draws per example, one column per branch,
#' the ratios, and the fewest runs any branch's median is over.
sampling_table <- function(sampling, comparisons) {
  sampling |>
    filter(!hit_cap) |>
    group_by(example, branch) |>
    summarise(
      seconds = median(seconds_per_1000_ess),
      runs = n(),
      .groups = "drop"
    ) |>
    group_by(example) |>
    mutate(runs = min(runs)) |>
    ungroup() |>
    pivot_wider(names_from = branch, values_from = seconds) |>
    add_ratios(comparisons)
}

#' One row per comparison and example: the largest |z|, and how many variables
#' are beyond `threshold`.
#'
#' `threshold` is not 2. There is one z per variable and the largest of many
#' standard normals exceeds 2 routinely - `cjs` alone has 40 of them.
posterior_agreement <- function(comparison, threshold = 4) {
  comparison |>
    group_by(comparison, example) |>
    summarise(
      variables = n(),
      max_abs_z = max(abs(z_mean)),
      n_disagree = sum(abs(z_mean) > threshold),
      worst_variable = variable[which.max(abs(z_mean))],
      .groups = "drop"
    )
}
