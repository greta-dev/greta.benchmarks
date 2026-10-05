# Benchmarks a branch of greta against CRAN and main: building each model,
# opt() and mcmc(), and the posteriors mcmc() returns.
#
#   Rscript --quiet --vanilla posts/YYYY-MM-DD-short-name-iNNN/run.R
#
# Everything that is measured is in `benchmark` below. cross::run_versions()
# installs each version into a library of its own and evaluates `benchmark` in
# a fresh R session against it. Each session writes results/session-<n>.rds,
# and sessions already there are skipped, so a rerun after a crash carries on.

# pin main and the branch to commits: both move, and the post links each one
versions <- c(
  CRAN = "greta@0.6.0",
  main = "greta-dev/greta@REPLACE-WITH-MAIN-COMMIT",
  `#NNN` = "greta-dev/greta@REPLACE-WITH-BRANCH-COMMIT"
)
n_sessions <- 5
results_dir <- here::here("posts", "YYYY-MM-DD-short-name-iNNN", "results")

benchmark <- quote({
  library(greta)

  session <- as.integer(Sys.getenv("GRETA_BENCH_SESSION"))
  settings <- list(
    warmup = 1000,
    n_samples = 1000,
    chains = 4,
    n_cores = 4,
    build_iterations = 5,
    opt_iterations = 5,
    kept_draws_per_run = 250
  )

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
      theta <- mu_theta + xi * eta
      distribution(y) <- normal(theta, sigma_y)
      model(sigma_eta, eta, mu_theta, xi)
    },
    cjs = function() {
      set.seed(2026)
      n_obs <- 100
      n_time <- 20
      y <- matrix(
        sample(c(0, 1), size = n_obs * n_time, replace = TRUE),
        ncol = n_time
      )
      final_obs <- apply(y, 1, function(x) max(which(x > 0)))
      obs_id <- unlist(apply(
        y,
        1,
        function(x) seq(min(which(x > 0)), max(which(x > 0)), by = 1)[-1]
      ))
      capture_vec <- unlist(apply(
        y,
        1,
        function(x) x[min(which(x > 0)):max(which(x > 0))][-1]
      ))
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
      distribution(final_observation) <- bernoulli(chi[final_obs[
        not_seen_last
      ]])
      model(phi, p)
    }
  )

  # Iterations per kept draw. A random walk on a target far wider than its
  # steps accepts every proposal, so the variance between kept draws over one
  # step's variance counts the iterations between them. It is also the
  # session's first mcmc() call, so TensorFlow's start-up costs fall here
  # rather than on the first model.
  step_sd <- 0.1
  x <- normal(0, 1e6)
  walk <- mcmc(
    model(x),
    sampler = rwmh(epsilon = step_sd, diag_sd = 1),
    warmup = 0,
    n_samples = 4000,
    thin = 1,
    chains = 1,
    initial_values = initials(x = 0),
    verbose = FALSE
  )
  iterations_per_draw <- round(var(diff(as.vector(walk[[1]]))) / step_sd^2)

  build <- lapply(names(models), function(name) {
    mark <- bench::mark(
      models[[name]](),
      iterations = settings$build_iterations,
      check = FALSE,
      memory = FALSE,
      filter_gc = FALSE
    )
    data.frame(
      model = name,
      call = seq_len(settings$build_iterations),
      seconds = as.numeric(mark$time[[1]])
    )
  })

  opt_calls <- lapply(names(models), function(name) {
    m <- models[[name]]()
    mark <- bench::mark(
      opt(m),
      iterations = settings$opt_iterations,
      check = FALSE,
      memory = FALSE,
      filter_gc = FALSE
    )
    data.frame(
      model = name,
      call = seq_len(settings$opt_iterations),
      seconds = as.numeric(mark$time[[1]])
    )
  })

  # two mcmc() runs on each model: the first traces its functions, the second
  # reuses them
  mcmc_runs <- list()
  posterior_summaries <- list()
  kept_draws <- list()
  for (name in names(models)) {
    m <- models[[name]]()
    for (run in 1:2) {
      set.seed(session * 10 + run)
      elapsed <- bench::bench_time(
        draws <- mcmc(
          m,
          warmup = settings$warmup,
          n_samples = settings$n_samples,
          chains = settings$chains,
          n_cores = settings$n_cores,
          verbose = FALSE
        )
      )[["real"]]
      run_name <- paste(name, run)
      mcmc_runs[[run_name]] <- data.frame(
        model = name,
        run = run,
        seconds = as.numeric(elapsed)
      )
      posterior_summaries[[run_name]] <- data.frame(
        model = name,
        run = run,
        posterior::summarise_draws(
          draws,
          "mean",
          "sd",
          "mcse_mean",
          "rhat",
          "ess_bulk",
          "ess_tail"
        )
      )
      if (run == 1) {
        draws_matrix <- do.call(rbind, lapply(draws, as.matrix))
        kept_rows <- round(seq(
          1,
          nrow(draws_matrix),
          length.out = settings$kept_draws_per_run
        ))
        kept <- draws_matrix[kept_rows, , drop = FALSE]
        kept_draws[[name]] <- data.frame(
          model = name,
          variable = rep(colnames(kept), each = nrow(kept)),
          value = as.vector(kept)
        )
      }
    }
  }

  greta_sha <- packageDescription("greta")$RemoteSha
  provenance <- data.frame(
    greta_version = as.character(packageVersion("greta")),
    greta_sha = if (is.null(greta_sha)) NA_character_ else greta_sha,
    r_version = paste(R.version$major, R.version$minor, sep = "."),
    tensorflow_version = tensorflow::tf$version$VERSION,
    tfp_version = reticulate::import("tensorflow_probability")$`__version__`,
    machine = paste(
      Sys.info()[c("sysname", "release", "machine")],
      collapse = " "
    ),
    cores = parallel::detectCores()
  )

  list(
    session = session,
    settings = settings,
    provenance = provenance,
    iterations_per_draw = iterations_per_draw,
    build = do.call(rbind, build),
    opt = do.call(rbind, opt_calls),
    mcmc = do.call(rbind, mcmc_runs),
    posterior = do.call(rbind, posterior_summaries),
    draws = do.call(rbind, kept_draws)
  )
})

dir.create(results_dir, showWarnings = FALSE, recursive = TRUE)

for (session in seq_len(n_sessions)) {
  session_file <- file.path(results_dir, sprintf("session-%d.rds", session))
  if (file.exists(session_file)) {
    next
  }

  # a fresh order each session, so no version is always measured first or last
  order <- sample(names(versions))

  # rlang::inject() splices `benchmark` in, because run_versions() reads its
  # expression unevaluated. R_ENABLE_JIT = "0" stops R compiling that
  # expression before library(greta) inside it runs, which binds base R's %*%
  # and breaks multiple_linear (greta#854).
  measured <- rlang::inject(cross::run_versions(
    !!benchmark,
    pkgs = unname(versions[order]),
    args_callr = list(
      env = c(
        callr::rcmd_safe_env(),
        R_ENABLE_JIT = "0",
        GRETA_BENCH_SESSION = session
      )
    )
  ))

  saveRDS(
    list(
      session = session,
      versions = versions,
      order = order,
      results = setNames(measured$result, order)
    ),
    session_file
  )
}
