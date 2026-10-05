# The report's plots of each example's fit: posterior densities, and fitted
# values against the data, with every branch drawn on the same axes so they
# can be compared directly. tidy_*() reshape branch_fits() into long data
# frames, which are targets; gg_*() build a ggplot from them and write nothing.
#
# branch_fits() holds several seeded fits per example. The plots draw the first
# of them, seed 1; tidy_fit_diagnostics() covers every one.

#' Every draw of every variable from the seed 1 fit, one row per draw.
tidy_fit_draws <- function(fits) {
  parts <- list()
  for (branch in names(fits)) {
    for (example in names(fits[[branch]])) {
      draws <- as.data.frame(fits[[branch]][[example]][[1]]$draws)
      long <- pivot_longer(
        draws,
        -c(.chain, .iteration, .draw),
        names_to = "variable",
        values_to = "value"
      )
      long$branch <- branch
      long$example <- example
      parts[[length(parts) + 1]] <- long
    }
  }
  out <- bind_rows(parts)
  # the reference first, as the pipeline lists the branches
  out$branch <- factor(out$branch, levels = names(fits))
  out
}

#' Every kept draw of every fitted value from the seed 1 fit, with the data
#' point, predictor and group it belongs to.
tidy_fitted <- function(fits) {
  parts <- list()
  for (branch in names(fits)) {
    for (example in names(fits[[branch]])) {
      fit <- fits[[branch]][[example]][[1]]
      out <- fit$fitted
      out$branch <- branch
      out$example <- example
      out$x <- if (is.null(fit$x)) NA_real_ else fit$x[out$.row]
      out$group <- if (is.null(fit$group)) {
        NA_character_
      } else {
        as.character(fit$group[out$.row])
      }
      out$observed <- if (is.null(fit$observed)) {
        NA_real_
      } else {
        fit$observed[out$.row]
      }
      out$x_label <- fit$x_label %||% NA_character_
      out$style <- fit$style
      parts[[length(parts) + 1]] <- out
    }
  }
  out <- bind_rows(parts)
  out$branch <- factor(out$branch, levels = names(fits))
  out
}

#' Every seeded fit's worst R-hat, the minimum, median and maximum bulk ESS
#' over its variables, and its smallest tail ESS.
tidy_fit_diagnostics <- function(fits) {
  parts <- list()
  for (branch in names(fits)) {
    for (example in names(fits[[branch]])) {
      for (seed in seq_along(fits[[branch]][[example]])) {
        summ <- posterior::summarise_draws(
          fits[[branch]][[example]][[seed]]$draws,
          "rhat",
          "ess_bulk",
          "ess_tail"
        )
        parts[[length(parts) + 1]] <- data.frame(
          example = example,
          branch = branch,
          seed = seed,
          rhat_max = max(summ$rhat),
          ess_bulk_min = min(summ$ess_bulk),
          ess_bulk_median = median(summ$ess_bulk),
          ess_bulk_max = max(summ$ess_bulk),
          ess_tail_min = min(summ$ess_tail)
        )
      }
    }
  }
  out <- bind_rows(parts)
  out$branch <- factor(out$branch, levels = names(fits))
  out
}

# the first few of an example's variables, since cjs has forty
first_variables <- function(fit_draws, example_name, max_variables) {
  one <- fit_draws[fit_draws$example == example_name, ]
  shown <- utils::head(unique(one$variable), max_variables)
  one[one$variable %in% shown, ]
}

#' Each variable's posterior density, one line per branch.
gg_densities <- function(fit_draws, example_name, max_variables = 8) {
  first_variables(fit_draws, example_name, max_variables) |>
    ggplot(aes(x = value, colour = branch)) +
    geom_density(linewidth = 0.5) +
    facet_wrap(~variable, scales = "free") +
    labs(x = NULL, y = NULL, colour = NULL) +
    theme(axis.text.y = element_blank(), legend.position = "bottom")
}

#' Fitted values against the data they model, one colour per branch: a median
#' line and 95% band over a continuous predictor, a median and 50% and 95%
#' intervals per unit for a discrete one, or fitted against observed when there
#' is no predictor. The data are the black points.
gg_fit <- function(fitted_values, example_name) {
  one <- fitted_values[fitted_values$example == example_name, ]
  observed <- unique(
    one[!is.na(one$observed), c(".row", "x", "group", "observed")]
  )
  x_label <- one$x_label[[1]]
  has_predictor <- !all(is.na(one$x))
  one_value_per_unit <- one$style[[1]] == "interval"
  dodge <- position_dodge(width = 0.6)

  if (!has_predictor) {
    return(
      ggplot(one, aes(x = observed, y = value, colour = branch)) +
        stat_pointinterval(
          aes(group = interaction(.row, branch)),
          .width = c(0.5, 0.95),
          point_size = 0.8,
          position = dodge
        ) +
        geom_abline(linetype = "dashed") +
        labs(x = "observed", y = "fitted", colour = NULL) +
        theme(legend.position = "bottom")
    )
  }

  if (one_value_per_unit) {
    return(
      ggplot(one, aes(x = factor(x), y = value, colour = branch)) +
        stat_pointinterval(.width = c(0.5, 0.95), position = dodge) +
        geom_point(
          data = observed,
          aes(x = factor(x), y = observed),
          inherit.aes = FALSE,
          size = 2
        ) +
        labs(x = x_label, y = "fitted", colour = NULL) +
        theme(legend.position = "bottom")
    )
  }

  by_group <- if (all(is.na(one$group))) NULL else facet_wrap(~group)
  ggplot(one, aes(x = x, y = value, colour = branch, fill = branch)) +
    stat_ribbon(.width = 0.95, alpha = 0.15, colour = NA) +
    # drawn on its own, so the ribbon's transparency does not fade the line
    stat_summary(fun = median, geom = "line", linewidth = 0.6) +
    geom_point(
      data = observed,
      aes(x = x, y = observed),
      inherit.aes = FALSE,
      size = 0.8
    ) +
    by_group +
    labs(x = x_label, y = "fitted", colour = NULL, fill = NULL) +
    theme(legend.position = "bottom")
}
