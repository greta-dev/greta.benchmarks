# The report's plots of each example's fit: trace plots, posterior densities,
# and fitted values against the data, each with the two branches side by side.
# tidy_*() reshape branch_fits() into long data frames, which are targets;
# gg_*() build a ggplot from them and write nothing.

#' Every draw of every variable, one row per draw.
tidy_fit_draws <- function(fits) {
  parts <- list()
  for (branch in names(fits)) {
    for (example in names(fits[[branch]])) {
      draws <- as.data.frame(fits[[branch]][[example]]$draws)
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

#' Every kept draw of every fitted value, with the data point, predictor and
#' group it belongs to.
tidy_fitted <- function(fits) {
  parts <- list()
  for (branch in names(fits)) {
    for (example in names(fits[[branch]])) {
      fit <- fits[[branch]][[example]]
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

# the first few of an example's variables, since cjs has forty
first_variables <- function(fit_draws, example_name, max_variables) {
  one <- fit_draws[fit_draws$example == example_name, ]
  shown <- utils::head(unique(one$variable), max_variables)
  one[one$variable %in% shown, ]
}

#' Each chain's draws in order: a stuck or wandering chain shows here first.
gg_traces <- function(fit_draws, example_name, max_variables = 6) {
  first_variables(fit_draws, example_name, max_variables) |>
    ggplot(aes(x = .iteration, y = value, colour = factor(.chain))) +
    geom_line(linewidth = 0.2, alpha = 0.8) +
    facet_grid(variable ~ branch, scales = "free_y") +
    labs(x = "iteration", y = NULL, colour = "chain", title = example_name)
}

#' Each variable's posterior as a density with its median and 66% and 95%
#' intervals, one row per branch so the two can be read against each other.
gg_densities <- function(fit_draws, example_name, max_variables = 8) {
  first_variables(fit_draws, example_name, max_variables) |>
    ggplot(aes(x = value, y = branch, fill = branch)) +
    # each panel's densities scaled on their own, or one narrow variable
    # flattens every other panel to a line
    stat_slabinterval(alpha = 0.7, normalize = "panels") +
    facet_wrap(~variable, scales = "free_x") +
    labs(x = NULL, y = NULL, title = example_name) +
    theme(legend.position = "none")
}

#' Fitted values against the data they model: a ribbon over a continuous
#' predictor, one interval per unit for a discrete one, or fitted against
#' observed when there is no predictor.
gg_fit <- function(fitted_values, example_name) {
  one <- fitted_values[fitted_values$example == example_name, ]
  observed <- unique(
    one[!is.na(one$observed), c("branch", ".row", "x", "group", "observed")]
  )
  x_label <- one$x_label[[1]]

  if (all(is.na(one$x))) {
    return(
      ggplot(one, aes(x = observed, y = value, group = .row)) +
        stat_pointinterval(.width = c(0.5, 0.95), point_size = 0.8) +
        geom_abline(linetype = "dashed") +
        facet_wrap(~branch) +
        labs(x = "observed", y = "fitted", title = example_name)
    )
  }

  if (one$style[[1]] == "interval") {
    plot <- ggplot(one, aes(x = factor(x), y = value)) +
      stat_pointinterval(.width = c(0.5, 0.95))
    if (nrow(observed) > 0) {
      plot <- plot +
        geom_point(
          data = observed,
          aes(x = factor(x), y = observed),
          colour = "firebrick",
          shape = 4,
          size = 2.5
        )
    }
    return(
      plot +
        facet_wrap(~branch) +
        labs(x = x_label, y = "fitted", title = example_name)
    )
  }

  facets <- if (all(is.na(one$group))) {
    facet_wrap(~branch)
  } else {
    facet_grid(group ~ branch)
  }
  ggplot(one, aes(x = x, y = value)) +
    # a thin median line, so a narrow ribbon is not hidden underneath it
    stat_lineribbon(.width = c(0.5, 0.8, 0.95), linewidth = 0.5) +
    scale_fill_brewer() +
    geom_point(
      data = observed,
      aes(x = x, y = observed),
      inherit.aes = FALSE,
      size = 0.8,
      alpha = 0.6
    ) +
    facets +
    labs(x = x_label, y = "fitted", fill = "interval", title = example_name)
}
