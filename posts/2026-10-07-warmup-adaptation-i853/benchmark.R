# What the tf-warmup-i547 branch of greta runs, in a fresh R session: run.R
# sources it once per session, and keeps the list it ends with. Each
# `# ---- label ----` line starts a section that index.qmd shows by that label.
#
# Run it alone to try it against whichever greta is installed, which needs the
# branch's internal adaptation field:
#
#   Rscript --quiet --vanilla posts/2026-10-07-warmup-adaptation-i853/benchmark.R

# ---- benchmark-setup ----
library(greta)
library(bench)
session <- as.integer(Sys.getenv("GRETA_BENCH_SESSION", "1"))
session_seed <- 2026 - 10 - 7 + session

# ---- benchmark-settings ----
# warmup and n_samples are mcmc()'s arguments, so they count draws; mcmc_calls
# counts timed calls. The schemes are the branch's internal choices of warmup
# tuning; the TFP kinds are TFP's own windowed adaptation, for HMC and NUTS
bench_settings <- list(
  warmup = 1000,
  n_samples = 1000,
  chains = 4,
  n_cores = 4,
  mcmc_calls = 2,
  schemes = c("greta", "greta_841", "windowed"),
  tfp_kinds = c("hmc", "nuts"),
  tfp_leapfrog_steps = 8L
)

# ---- model-normals ----
# greta-dev/greta#853's test: 20 independent normals with sds from 0.01 to 100
normals_sd <- 10^seq(-2, 2, length.out = 20)
build_normals <- function() {
  x <- normal(0, normals_sd)
  model(x)
}

# ---- model-linear ----
build_linear <- function() {
  int <- normal(0, 10)
  coef <- normal(0, 10)
  sd <- cauchy(0, 3, truncation = c(0, Inf))
  mu <- int + coef * attitude$complaints
  distribution(attitude$rating) <- normal(mu, sd)
  model(int, coef, sd)
}

# ---- model-multiple-linear ----
build_multiple_linear <- function() {
  design <- as.matrix(attitude[, 2:7])
  int <- normal(0, 10)
  coefs <- normal(0, 10, dim = ncol(design))
  sd <- cauchy(0, 3, truncation = c(0, Inf))
  mu <- int + design %*% coefs
  distribution(attitude$rating) <- normal(mu, sd)
  model(int, coefs, sd)
}

# ---- model-hierarchical-linear ----
build_hierarchical_linear <- function() {
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
build_eight_schools <- function() {
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

# ---- benchmark-schemes ----
# Runs mcmc() twice on a model under each warmup scheme: the first call traces,
# the second reuses the trace. press() gives one bench_mark with a scheme
# column; next to it go the second call's draws and its tuned epsilon and
# diag_sd. The scheme is a field of greta's sampler class, read when mcmc()
# makes its sampler.
run_schemes <- function(build) {
  draws <- list()
  tuned <- list()
  marks <- press(
    scheme = bench_settings$schemes,
    {
      greta:::sampler$set("public", "adaptation", scheme, overwrite = TRUE)
      model_for_scheme <- build()
      set.seed(session_seed)
      scheme_marks <- mark(
        scheme_draws <- mcmc(
          model_for_scheme,
          warmup = bench_settings$warmup,
          n_samples = bench_settings$n_samples,
          chains = bench_settings$chains,
          n_cores = bench_settings$n_cores,
          verbose = FALSE
        ),
        iterations = bench_settings$mcmc_calls,
        check = FALSE,
        memory = FALSE,
        filter_gc = FALSE
      )
      parameters <- attr(scheme_draws, "model_info")$samplers[[1]]$parameters
      # press() evaluates this in an environment of its own, so the draws and
      # tuned values go to the lists outside it
      draws[[scheme]] <<- posterior::as_draws_array(scheme_draws)
      tuned[[scheme]] <<- list(
        epsilon = parameters$epsilon,
        diag_sd = parameters$diag_sd
      )
      scheme_marks
    }
  )
  greta:::sampler$set("public", "adaptation", "greta", overwrite = TRUE)
  list(marks = marks, draws = draws, tuned = tuned)
}

# ---- benchmark-tfp ----
# TFP's own windowed adaptation (tfp$experimental$mcmc, as its
# windowed_adaptive_hmc() and windowed_adaptive_nuts() use it), driven from the
# model's log density with the setup windowed_adaptive_hmc() does for a joint
# distribution. Its HMC takes a fixed number of leapfrog steps. It samples the
# model's free state, which trace_values() turns into the values of the
# model's greta arrays, as mcmc() does. Each run function is traced once and
# called twice.
windowed_sampling <- reticulate::import(
  "tensorflow_probability.python.experimental.mcmc.windowed_sampling"
)
tfp <- reticulate::import("tensorflow_probability")
tf <- tensorflow::tf

tfp_windowed_run <- function(m, kind) {
  dag <- m$dag
  n_free <- length(greta:::unlist_tf(dag$example_parameters(free = TRUE)))
  float <- greta:::tf_float()
  # initial values drawn as mcmc() draws those it is not given: normal with sd
  # 0.1 on the free scale
  set.seed(session_seed)
  initial <- list(tf$constant(
    matrix(stats::rnorm(bench_settings$chains * n_free, 0, 0.1), ncol = n_free),
    dtype = float
  ))
  tensorflow::tf_function(function(seed) {
    proposal <- list(
      target_log_prob_fn = function(x) dag$tf_log_prob_function_adjusted(x),
      step_size = tf$constant(0.1, dtype = float),
      momentum_distribution = windowed_sampling$`_init_momentum`(
        initial,
        batch_shape = list(as.integer(bench_settings$chains)),
        shard_axis_names = NULL
      )
    )
    if (kind == "hmc") {
      proposal$num_leapfrog_steps <- bench_settings$tfp_leapfrog_steps
    }
    windowed_sampling$`_do_sampling`(
      kind = kind,
      proposal_kernel_kwargs = proposal,
      dual_averaging_kwargs = list(
        num_adaptation_steps = as.integer(bench_settings$warmup),
        target_accept_prob = tf$constant(0.651, dtype = float)
      ),
      num_draws = as.integer(bench_settings$n_samples),
      num_burnin_steps = as.integer(bench_settings$warmup),
      initial_position = initial,
      initial_running_variance = list(
        tfp$experimental$stats$RunningVariance$from_stats(
          num_samples = tf$zeros(list(), dtype = float),
          mean = tf$zeros_like(initial[[1]]),
          variance = tf$ones_like(initial[[1]])
        )
      ),
      bijector = tfp$bijectors$Identity(),
      trace_fn = function(...) reticulate::tuple(),
      return_final_kernel_results = FALSE,
      chain_axis_names = NULL,
      shard_axis_names = NULL,
      seed = seed
    )$all_states[[1]]
  })
}

# the free state draws, draws by chains by parameters, as a posterior draws
# array of the model's greta arrays
tfp_draws_array <- function(m, free_draws) {
  free_draws <- as.array(free_draws)
  chains <- lapply(seq_len(dim(free_draws)[2]), function(chain) {
    m$dag$trace_values(free_draws[, chain, , drop = TRUE])
  })
  values <- simplify2array(chains)
  posterior::as_draws_array(aperm(values, c(1, 3, 2)))
}

run_tfp <- function(build) {
  draws <- list()
  marks <- press(
    kind = bench_settings$tfp_kinds,
    {
      model_for_kind <- build()
      run <- tfp_windowed_run(model_for_kind, kind)
      seed <- tf$constant(as.integer(c(session_seed, 0)), dtype = tf$int32)
      kind_marks <- mark(
        free_draws <- run(seed),
        iterations = bench_settings$mcmc_calls,
        check = FALSE,
        memory = FALSE,
        filter_gc = FALSE
      )
      # press() evaluates this in an environment of its own
      draws[[kind]] <<- tfp_draws_array(model_for_kind, free_draws)
      kind_marks
    }
  )
  list(marks = marks, draws = draws)
}

# ---- bench-normals ----
normals_schemes <- run_schemes(build_normals)
normals_tfp <- run_tfp(build_normals)

# ---- bench-linear ----
linear_schemes <- run_schemes(build_linear)
linear_tfp <- run_tfp(build_linear)

# ---- bench-multiple-linear ----
multiple_linear_schemes <- run_schemes(build_multiple_linear)
multiple_linear_tfp <- run_tfp(build_multiple_linear)

# ---- bench-hierarchical-linear ----
hierarchical_linear_schemes <- run_schemes(build_hierarchical_linear)
hierarchical_linear_tfp <- run_tfp(build_hierarchical_linear)

# ---- bench-eight-schools ----
eight_schools_schemes <- run_schemes(build_eight_schools)
eight_schools_tfp <- run_tfp(build_eight_schools)

# ---- benchmark-provenance ----
session_info <- sessioninfo::session_info()
# greta_sitrep() reports through messages, so capture those
greta_sitrep_report <- utils::capture.output(greta_sitrep(), type = "message")

provenance <- data.frame(
  greta_version = as.character(packageVersion("greta")),
  r_version = paste(R.version$major, R.version$minor, sep = "."),
  tensorflow_version = tensorflow::tf$version$VERSION,
  tfp_version = tfp$`__version__`,
  machine = paste(
    Sys.info()[c("sysname", "release", "machine")],
    collapse = " "
  ),
  cores = parallel::detectCores()
)

# ---- benchmark-results ----
# the value source() returns to run.R: every bench_mark object as press() and
# mark() made it, with each run's draws and tuned values beside them
list(
  session_seed = session_seed,
  bench_settings = bench_settings,
  normals_sd = normals_sd,
  provenance = provenance,
  session_info = session_info,
  greta_sitrep_report = greta_sitrep_report,
  schemes = list(
    normals = normals_schemes,
    linear = linear_schemes,
    multiple_linear = multiple_linear_schemes,
    hierarchical_linear = hierarchical_linear_schemes,
    eight_schools = eight_schools_schemes
  ),
  tfp = list(
    normals = normals_tfp,
    linear = linear_tfp,
    multiple_linear = multiple_linear_tfp,
    hierarchical_linear = hierarchical_linear_tfp,
    eight_schools = eight_schools_tfp
  )
)
