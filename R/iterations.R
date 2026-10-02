# How many iterations a version of greta runs per kept draw, at thin = 1.
#
# greta 0.6.0, and main before #850, pass `thin` to TFP's sample_chain() as
# num_steps_between_results, which keeps one draw in thin + 1: two iterations
# per draw. #850 passes thin - 1: one. Measured rather than listed per version,
# so nothing has to be updated when a version changes.
#
# Only defines a function, so it is safe to source before greta is attached,
# which {cross} does by absolute path in a subprocess.

#' Iterations per kept draw, from a random walk that accepts every step.
#'
#' A target far wider than rwmh()'s steps accepts every proposal, so the change
#' between two kept draws is the sum of the steps between them, and its
#' variance over one step's variance counts them. Uses only greta's exported
#' functions, so it works on every version.
iterations_per_draw <- function(n_draws = 4000) {
  x <- normal(0, 1e6)
  m <- model(x)
  # for a single parameter, rwmh()'s step is epsilon * diag_sd / sum(diag_sd)
  step_sd <- 0.1
  draws <- mcmc(
    m,
    sampler = rwmh(epsilon = step_sd, diag_sd = 1),
    warmup = 0,
    n_samples = n_draws,
    thin = 1,
    chains = 1,
    initial_values = initials(x = 0),
    verbose = FALSE
  )
  between_draws <- diff(as.vector(draws[[1]]))
  round(stats::var(between_draws) / step_sd^2)
}
