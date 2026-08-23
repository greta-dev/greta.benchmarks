# The model set the suite benchmarks against.
#
# These are greta's own example models, from inst/examples/, which the
# example_models vignette renders. Using them rather than inventing something
# means the suite measures models people actually write, and models the
# maintainers already recognise.
#
# This file only defines functions, so it is safe to source before greta is
# attached - which matters, because {cross} runs the benchmark expression in a
# subprocess where this gets sourced by absolute path.
#
# Adding a model: give it a name, return a `model()`, and note in the comment
# which part of the stack it exercises that the others do not.

greta_bench_models <- list(

  # inst/examples/linear.Rmd - the cheapest real model, a floor for
  # per-iteration overhead
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

  # inst/examples/hierarchical_linear_slopes_corr.Rmd - THE ONLY MODEL HERE
  # THAT TOUCHES THE CHOLESKY PATH. lkj_correlation() and chol() go through
  # CorrelationCholesky, whose gradients XLA cannot compile, so this is the one
  # that catches breakage a plain regression never will. Do not drop it from a
  # subset.
  hierarchical_slopes_corr = function() {
    modmat <- model.matrix(~Sepal.Width, iris)
    jj <- as.numeric(iris$Species)
    M <- ncol(modmat)
    N <- max(jj)
    tau <- exponential(0.5, dim = M)
    Omega <- lkj_correlation(3, M)
    Omega_U <- chol(Omega)
    Sigma_U <- sweep(Omega_U, 2, tau, "*")
    z <- normal(0, 1, dim = c(N, M))
    ab <- z %*% Sigma_U
    mu <- rowSums(ab[jj, ] * modmat)
    sigma_e <- cauchy(0, 3, truncation = c(0, Inf))
    distribution(iris$Sepal.Length) <- normal(mu, sigma_e)
    model(tau, Omega, z, sigma_e)
  },

  # not from inst/examples: multiple_linear scaled until the gradient is real
  # work, so the suite can tell fixed overhead from model cost
  wide_linear = function() {
    n <- 2000
    p <- 200
    design <- matrix(rnorm(n * p), n, p)
    y_obs <- as.numeric(design %*% rnorm(p, sd = 0.2) + rnorm(n, sd = 0.5))
    int <- normal(0, 10)
    coefs <- normal(0, 10, dim = p)
    sd <- cauchy(0, 3, truncation = c(0, Inf))
    mu <- int + design %*% coefs
    distribution(y_obs) <- normal(mu, sd)
    model(int, coefs, sd)
  }
)
