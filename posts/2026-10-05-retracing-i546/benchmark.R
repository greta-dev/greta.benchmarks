# What each version of greta runs, in a fresh R session of its own: run.R
# sources it once per version per session, and keeps the list it ends with.
# Each `# ---- label ----` line starts a section that index.qmd shows by that
# label.
#
# Run it alone to try it against whichever greta is installed:
#
#   Rscript --quiet --vanilla posts/2026-10-05-retracing-i546/benchmark.R

# ---- benchmark-setup ----
library(greta)
session <- as.integer(Sys.getenv("GRETA_BENCH_SESSION", "1"))

# ---- benchmark-settings ----
# warmup and n_samples are mcmc()'s arguments, so they count draws; the
# *_calls settings count timed calls
settings <- list(
  warmup = 1000,
  n_samples = 1000,
  chains = 4,
  n_cores = 4,
  build_calls = 5,
  opt_calls = 5,
  hessian_calls = 3,
  mcmc_calls = 2,
  keep_every_nth_draw = 10
)

models <- list()

# ---- model-linear ----
models$linear <- function() {
  int <- normal(0, 10)
  coef <- normal(0, 10)
  sd <- cauchy(0, 3, truncation = c(0, Inf))
  mu <- int + coef * attitude$complaints
  distribution(attitude$rating) <- normal(mu, sd)
  model(int, coef, sd)
}

# ---- model-multiple-linear ----
models$multiple_linear <- function() {
  design <- as.matrix(attitude[, 2:7])
  int <- normal(0, 10)
  coefs <- normal(0, 10, dim = ncol(design))
  sd <- cauchy(0, 3, truncation = c(0, Inf))
  mu <- int + design %*% coefs
  distribution(attitude$rating) <- normal(mu, sd)
  model(int, coefs, sd)
}

# ---- model-hierarchical-linear ----
models$hierarchical_linear <- function() {
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
}

# ---- model-eight-schools ----
models$eight_schools <- function() {
  y <- c(28, 8, -3, 7, -1, 1, 18, 12)
  sigma_y <- c(15, 10, 16, 11, 9, 11, 10, 18)
  sigma_eta <- inverse_gamma(1, 1)
  eta <- normal(0, sigma_eta, dim = 8)
  mu_theta <- normal(0, 100)
  xi <- normal(0, 5)
  theta <- mu_theta + xi * eta
  distribution(y) <- normal(theta, sigma_y)
  model(sigma_eta, eta, mu_theta, xi)
}

# ---- model-cjs ----
models$cjs <- function() {
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
  last_seen_before_the_end <- final_obs[not_seen_last]
  distribution(alive_data) <- bernoulli(phi[obs_id - 1])
  distribution(capture_vec) <- bernoulli(p[obs_id])
  distribution(final_observation) <- bernoulli(chi[last_seen_before_the_end])
  model(phi, p)
}

# ---- model-hessian ----
# the model greta#546 reported: twenty separate scalar parameters, each needing
# its own hessian
hessian_model <- function() {
  set.seed(2026 - 09 - 29)
  y <- rnorm(20)
  target_names <- paste0("b", 1:20)
  for (name in target_names) {
    assign(name, variable())
  }
  distribution(y) <- normal(do.call(c, mget(target_names)), 1)
  # model() names its targets from the expressions it is given, so the call is
  # built from the names: this is model(b1, b2, ..., b20)
  eval(as.call(c(quote(model), lapply(target_names, as.name))))
}

# ---- benchmark-tracing-helpers ----
# TensorFlow logs its retracing warning through Python's logging, which R does
# not see, so point that logger at stderr and capture stderr
count_retracing_warnings <- function(expr) {
  captured <- reticulate::py_capture_output(
    {
      reticulate::py_run_string(paste(
        "import sys",
        "from tensorflow.python.platform import tf_logging",
        "for _h in tf_logging.get_logger().handlers: _h.stream = sys.stderr",
        sep = "\n"
      ))
      force(expr)
    },
    type = "stderr"
  )
  sum(grepl("triggered tf.function retracing", strsplit(captured, "\n")[[1]]))
}

traces <- function(tf_function) {
  tryCatch(
    as.integer(tf_function$experimental_get_tracing_count()),
    error = function(e) NA_integer_
  )
}

# ---- benchmark-sampler-iterations ----
# A random walk on a target far wider than its steps accepts every proposal, so
# the variance between kept draws over one step's variance counts the sampler
# iterations between them. It is also the session's first mcmc() call, so
# TensorFlow's start-up costs fall here rather than on the first model.
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
sampler_iterations_per_draw <- round(
  var(diff(as.vector(walk[[1]]))) / step_sd^2
)

# ---- benchmark-build ----
# bench::mark()'s `iterations` is how many times it calls the expression
build_marks <- bench::press(
  model = names(models),
  bench::mark(
    models[[model]](),
    iterations = settings$build_calls,
    check = FALSE,
    memory = FALSE,
    filter_gc = FALSE
  )
)

# ---- benchmark-opt ----
opt_marks <- bench::press(
  model = names(models),
  {
    m <- models[[model]]()
    bench::mark(
      opt(m),
      iterations = settings$opt_calls,
      check = FALSE,
      memory = FALSE,
      filter_gc = FALSE
    )
  }
)

# ---- benchmark-hessian ----
m <- hessian_model()
hessian_warnings <- count_retracing_warnings(
  hessian_mark <- bench::mark(
    opt(m, hessian = TRUE),
    iterations = settings$hessian_calls,
    check = FALSE,
    memory = FALSE,
    filter_gc = FALSE
  )
)
hessian_mark$retracing_warnings <- hessian_warnings

# ---- benchmark-mcmc ----
# Both calls are on the same model: the first traces its TensorFlow functions
# and the second reuses them. `draws` keeps the second call's draws, and the
# columns added after bench::mark() describe the model after both calls.
mcmc_marks <- bench::press(
  model = names(models),
  {
    m <- models[[model]]()
    set.seed(session)
    retracing_warnings <- count_retracing_warnings(
      mark <- bench::mark(
        draws <- mcmc(
          m,
          warmup = settings$warmup,
          n_samples = settings$n_samples,
          chains = settings$chains,
          n_cores = settings$n_cores,
          verbose = FALSE
        ),
        iterations = settings$mcmc_calls,
        check = FALSE,
        memory = FALSE,
        filter_gc = FALSE
      )
    )
    sampler <- attr(draws, "model_info")$samplers[[1]]
    mark$retracing_warnings <- retracing_warnings
    mark$log_prob_traces <- traces(m$dag$tf_log_prob_function)
    mark$trace_values_traces <- traces(m$dag$tf_trace_values_batch)
    mark$sampler_traces <- traces(sampler$tf_evaluate_sample_batch)
    mark$posterior <- list(posterior::summarise_draws(
      draws,
      "mean",
      "sd",
      "mcse_mean",
      "rhat",
      "ess_bulk",
      "ess_tail"
    ))
    # every nth draw of each chain, numbered from the end of warmup
    kept <- seq(
      settings$keep_every_nth_draw,
      settings$n_samples,
      by = settings$keep_every_nth_draw
    )
    mark$kept_draws <- list(do.call(
      rbind,
      lapply(seq_along(draws), function(chain) {
        chain_draws <- as.matrix(draws[[chain]])[kept, , drop = FALSE]
        data.frame(
          chain = chain,
          draw = rep(kept, times = ncol(chain_draws)),
          variable = rep(colnames(chain_draws), each = length(kept)),
          value = as.vector(chain_draws)
        )
      })
    ))
    mark
  }
)

# ---- benchmark-provenance ----
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

# ---- benchmark-results ----
# the value source() returns to run.R: the bench_mark objects as bench made
# them, with the columns added above
list(
  session = session,
  settings = settings,
  provenance = provenance,
  sampler_iterations_per_draw = sampler_iterations_per_draw,
  build = build_marks,
  opt = opt_marks,
  hessian = hessian_mark,
  mcmc = mcmc_marks
)
