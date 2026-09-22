# The posteriors the suite benchmarks against.
#
# greta's own example models, from inst/examples/, which the example_models
# vignette renders. Using them rather than inventing something means the suite
# measures models people actually write, and models the maintainers already
# recognise.
#
# Returned from a function rather than assigned at the top level, because a
# non-function global in R/ is a value hiding outside the pipeline. This file
# therefore only defines a function, which also makes it safe to source before
# greta is attached - and that matters, because {cross} sources it by absolute
# path inside a subprocess.
#
# These are the `example` column in the results. Not `model`, because `model`
# is the name of a task: model(), opt(), mcmc().
#
# Adding one: give it a name, return a `model()`, and note in the comment which
# part of the stack it exercises that the others do not. Check its posterior
# geometry too - see the note on `linear`.

bench_examples <- function() {
  list(
    # inst/examples/linear.Rmd - the cheapest real model, a floor for
    # per-iteration overhead.
    #
    # Its geometry is worth knowing before using it to judge a sampler. It
    # regresses on attitude$complaints uncentred, mean 66.6 against sd ~13, so
    # the intercept and slope come out correlated at -0.97. Both then mix far
    # more slowly than `sd`, which is uncorrelated with them - at 4 chains x
    # 1000 that read as "greta does not converge" when it only meant the chain
    # was too short. At 4 x (2000 warmup + 4000) all three clear comfortably.
    linear = function() {
      int <- normal(0, 10)
      coef <- normal(0, 10)
      sd <- cauchy(0, 3, truncation = c(0, Inf))
      mu <- int + coef * attitude$complaints
      distribution(attitude$rating) <- normal(mu, sd)
      model(int, coef, sd)
    },

    # inst/examples/multiple_linear.Rmd - matrix multiply in the gradient
    multiple_linear = function() {
      design <- as.matrix(attitude[, 2:7])
      int <- normal(0, 10)
      coefs <- normal(0, 10, dim = ncol(design))
      sd <- cauchy(0, 3, truncation = c(0, Inf))
      mu <- int + design %*% coefs
      distribution(attitude$rating) <- normal(mu, sd)
      model(int, coefs, sd)
    },

    # inst/examples/hierarchical_linear.Rmd - rbind and integer indexing, which
    # cost more per iteration than the parameter count suggests
    hierarchical_linear = function() {
      int <- normal(0, 10)
      coef <- normal(0, 10)
      sd <- cauchy(0, 3, truncation = c(0, Inf))
      species_sd <- lognormal(0, 1)
      species_offset <- normal(0, species_sd, dim = 2)
      species_effect <- rbind(0, species_offset)
      species_id <- as.numeric(iris$Species)
      mu <- int + coef * iris$Sepal.Width + species_effect[species_id]
      distribution(iris$Sepal.Length) <- normal(mu, sd)
      model(int, coef, sd, species_sd, species_offset)
    },

    # inst/examples/eight_schools.Rmd - the funnel.
    #
    # `eta ~ normal(0, sigma_eta)` with sigma_eta itself a parameter is Neal's
    # funnel: the scale of eta is estimated, so the posterior narrows to a
    # point as sigma_eta goes to zero and HMC with a fixed step size either
    # cannot get into the neck or gets stuck in it. Eleven parameters, so it is
    # cheap - it is here for geometry, not size, and it is the standard test of
    # whether a sampler handles hierarchical models at all.
    eight_schools = function() {
      y <- c(28, 8, -3, 7, -1, 1, 18, 12)
      sigma_y <- c(15, 10, 16, 11, 9, 11, 10, 18)
      N <- length(y)
      sigma_eta <- inverse_gamma(1, 1)
      eta <- normal(0, sigma_eta, dim = N)
      mu_theta <- normal(0, 100)
      xi <- normal(0, 5)
      theta <- mu_theta + xi * eta
      distribution(y) <- normal(theta, sigma_y)
      model(sigma_eta, eta, mu_theta, xi)
    },

    # inst/examples/cjs.Rmd - the deep graph.
    #
    # Forty parameters, but the `chi` recursion adds nodes on every one of 19
    # iterations, so node count rather than parameter count is what this costs.
    # Nothing else in the set exercises that, and it is the case where graph
    # construction can regress without any parameter count changing.
    #
    # The data is seeded because first_obs/final_obs are derived from it and
    # set the model's shape - unseeded, two runs would build different-sized
    # models and their timings would not be comparable.
    cjs = function() {
      set.seed(2026)
      n_obs <- 100
      n_time <- 20
      y <- matrix(
        sample(c(0, 1), size = n_obs * n_time, replace = TRUE),
        ncol = n_time
      )

      first_obs <- apply(y, 1, function(x) min(which(x > 0)))
      final_obs <- apply(y, 1, function(x) max(which(x > 0)))
      obs_id <- apply(
        y,
        1,
        function(x) {
          seq(min(which(x > 0)), max(which(x > 0)), by = 1)[-1]
        }
      )
      obs_id <- unlist(obs_id)
      capture_vec <- apply(
        y,
        1,
        function(x) x[min(which(x > 0)):max(which(x > 0))][-1]
      )
      capture_vec <- unlist(capture_vec)

      phi <- beta(1, 1, dim = n_time)
      p <- beta(1, 1, dim = n_time)

      chi <- ones(n_time)
      for (i in seq_len(n_time - 1)) {
        tn <- n_time - i
        chi[tn] <- (1 - phi[tn]) + phi[tn] * (1 - p[tn + 1]) * chi[tn + 1]
      }

      alive_data <- ones(length(obs_id))
      not_seen_last <- final_obs != n_time
      final_observation <- ones(sum(not_seen_last))

      distribution(alive_data) <- bernoulli(phi[obs_id - 1])
      distribution(capture_vec) <- bernoulli(p[obs_id])
      distribution(final_observation) <- bernoulli(
        chi[final_obs[not_seen_last]]
      )

      model(phi, p)
    }
  )
}

# Three examples were removed on 2026-09-21, after being measured rather than
# on suspicion. `2026-09-21-example-baseline/` holds the run:
#
# factor_analysis
#   210 variables, minimum bulk-ESS 5.4 and Rhat 1.98 after 42,000 iterations.
#   Identified only up to an orthogonal rotation, so separate chains explore
#   different rotations and no amount of sampling fixes it. 40,971 seconds per
#   1000 ESS, three orders of magnitude worse than anything kept.
#
# wide_linear
#   minimum bulk-ESS 1842, comfortably past target, but Rhat 1.028 across 202
#   variables. The maximum of that many Rhat estimates clears 1.01 routinely,
#   so it capped every run while sampling perfectly well. Also the only example
#   that was never from inst/examples.
#
# hierarchical_slopes_corr
#   542 seconds per 1000 ESS, 20-80x everything else, and still capped.
#
# Dropping the last one costs the suite its only cholesky path:
# lkj_correlation() and chol() go through CorrelationCholesky, whose gradients
# XLA cannot compile. Cholesky *correctness* is still covered by greta's own
# tests; cholesky *performance* is now uncovered here, and that is recorded in
# AGENTS.md under the coverage the model set lacks.
