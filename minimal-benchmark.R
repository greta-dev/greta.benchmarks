# Benchmark mcmc() and opt() on greta's example models, on three versions of
# greta, with {cross} and {bench}.
#
#   Rscript minimal-benchmark.R
#
# cross::bench_versions() installs each version into a temporary library, runs
# the expression in a fresh R session against it, and stacks the bench::press()
# results with a `pkg` column naming the version.
#
# Each expression's first iteration is that model's first mcmc() or opt() call
# in the session, so it includes tracing; the later iterations do not.
#
# CRAN (0.6.0), main and #843 all run two iterations per draw, so the same
# mcmc() arguments are the same work on each. A version with greta#850 runs
# one, and would need warmup and n_samples doubled to match.

results <- cross::bench_versions(
  pkgs = c(
    "greta",
    "greta-dev/greta",
    "greta-dev/greta@faster-hessians-i546"
  ),
  {
    library(greta)

    models <- list(
      linear = function() {
        int <- normal(0, 10)
        coef <- normal(0, 10)
        sd <- cauchy(0, 3, truncation = c(0, Inf))
        mu <- int + coef * attitude$complaints
        distribution(attitude$rating) <- normal(mu, sd)
        model(int, coef, sd)
      },
      multiple_linear = function() {
        design <- as.matrix(attitude[, 2:7])
        int <- normal(0, 10)
        coefs <- normal(0, 10, dim = ncol(design))
        sd <- cauchy(0, 3, truncation = c(0, Inf))
        mu <- int + design %*% coefs
        distribution(attitude$rating) <- normal(mu, sd)
        model(int, coefs, sd)
      },
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
      eight_schools = function() {
        y <- c(28, 8, -3, 7, -1, 1, 18, 12)
        sigma_y <- c(15, 10, 16, 11, 9, 11, 10, 18)
        sigma_eta <- inverse_gamma(1, 1)
        eta <- normal(0, sigma_eta, dim = 8)
        mu_theta <- normal(0, 100)
        xi <- normal(0, 5)
        distribution(y) <- normal(mu_theta + xi * eta, sigma_y)
        model(sigma_eta, eta, mu_theta, xi)
      }
    )

    bench::press(
      model_name = names(models),
      {
        m <- models[[model_name]]()
        bench::mark(
          mcmc = mcmc(
            m,
            warmup = 1000,
            n_samples = 1000,
            chains = 4,
            verbose = FALSE
          ),
          opt = opt(m),
          iterations = 5,
          check = FALSE,
          memory = FALSE,
          filter_gc = FALSE
        )
      }
    )
  },
  # cross runs the whole expression as one function, which R compiles when it
  # is first called, before library(greta) inside it has run. The compiler then
  # binds `%*%` to base R's, which returns an R matrix of NAs for a greta
  # array, so building multiple_linear fails. Not compiling it keeps greta's
  args_callr = list(env = c(callr::rcmd_safe_env(), R_ENABLE_JIT = "0"))
)

# every timed run, beside bench's summaries
results$runs <- vapply(
  results$time,
  function(times) paste(format(times), collapse = ", "),
  character(1)
)
print(
  results[, c("pkg", "model_name", "expression", "min", "median", "runs")],
  n = Inf
)
