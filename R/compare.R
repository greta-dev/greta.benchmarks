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

#' One row per example: does anything disagree?
#'
#' `threshold` is not 2. There is one z per variable and the largest of many
#' standard normals exceeds 2 routinely - `cjs` alone has 40 of them.
posterior_agreement <- function(comparison, threshold = 4) {
  comparison |>
    group_by(example) |>
    summarise(
      variables = n(),
      max_abs_z = max(abs(z_mean)),
      n_disagree = sum(abs(z_mean) > threshold),
      worst_variable = variable[which.max(abs(z_mean))],
      .groups = "drop"
    ) |>
    mutate(
      verdict = if_else(
        n_disagree > 0,
        "posteriors differ",
        "agree within Monte Carlo error"
      )
    )
}

#' Relative median time per example x task, with the reference branch at 1.
relative_timings <- function(timings) {
  split(timings, list(timings$example, timings$task), drop = TRUE) |>
    lapply(function(cell) {
      s <- summary(cell)
      data.frame(
        example = cell$example[[1]],
        task = cell$task[[1]],
        branch = s$branch,
        ms = as.numeric(s$median) * 1000,
        relative = as.numeric(s$median) / min(as.numeric(s$median))
      )
    }) |>
    bind_rows()
}
