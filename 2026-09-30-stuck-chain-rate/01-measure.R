# How often an hmc() chain stops mixing on main, and whether those are the
# chains whose one leapfrog count L for the whole sampling phase puts L * theta
# near a multiple of pi.
#
#   Rscript --vanilla ~/github/greta-dev/greta.benchmarks/2026-09-30-stuck-chain-rate/01-measure.R
#
# Run from a greta checkout on main (179021a8). Writes results.csv beside this
# file; 02-report.R summarises it into results.md.
#
# For a Gaussian posterior with sd sigma, one leapfrog step of size eps rotates
# the (position, momentum) pair by theta = acos(1 - (eps / sigma)^2 / 2), so an
# accepted proposal after L steps moves a draw x to cos(L * theta) * x plus
# fresh noise. Near a whole number of half-turns the proposal returns to x or
# -x with no energy error, so it is always accepted. greta's kept draws are two
# iterations apart on main (thin = 1 keeps one draw in two), so there the
# lag-1 autocorrelation of the kept draws should approach cos(L * theta)^2.
# Away from whole half-turns, rejections break that prediction.

pkgload::load_all(".", quiet = TRUE)

# record every leapfrog count hmc() draws, and which phase drew it
logged <- new.env()
original_values <- hmc_sampler$public_methods$sampler_parameter_values
hmc_sampler$set(
  "public",
  "original_values",
  original_values,
  overwrite = TRUE
)
hmc_sampler$set(
  "public",
  "sampler_parameter_values",
  function() {
    values <- self$original_values()
    logged$l <- c(logged$l, values$hmc_l)
    logged$phase <- c(logged$phase, logged$current_phase)
    values
  },
  overwrite = TRUE
)
for (phase in c("warmup", "sampling")) {
  method <- paste0("run_", phase)
  sampler$set(
    "public",
    paste0("original_", method),
    sampler$public_methods[[method]],
    overwrite = TRUE
  )
  sampler$set(
    "public",
    method,
    eval(bquote(function(...) {
      logged$current_phase <- .(phase)
      self[[.(paste0("original_", method))]](...)
    })),
    overwrite = TRUE
  )
}

# the model from test-data-swapping.R: posterior sd 1 / sqrt(10 + 1 / 100)
one_parameter <- function() {
  x <- as_data(rep(0, 10))
  z <- normal(0, 10)
  distribution(x) <- normal(z, 1)
  model(z)
}
posterior_sd <- 1 / sqrt(10 + 1 / 100)

run_one <- function(seed) {
  logged$l <- integer()
  logged$phase <- character()
  logged$current_phase <- "setup"
  set.seed(seed)
  draws <- mcmc(one_parameter(), chains = 1, verbose = FALSE)
  kept <- as.vector(as.matrix(draws))
  epsilon <- attr(draws, "model_info")$samplers[[1]]$parameters$epsilon
  sampling_l <- logged$l[logged$phase == "sampling"]
  theta <- acos(1 - (epsilon / posterior_sd)^2 / 2)
  data.frame(
    seed = seed,
    epsilon = epsilon,
    sampling_l = paste(sampling_l, collapse = " "),
    turns = sampling_l[1] * theta / pi,
    predicted_lag1 = cos(sampling_l[1] * theta)^2,
    observed_lag1 = stats::acf(kept, lag.max = 1, plot = FALSE)$acf[2],
    sd_ratio = stats::sd(kept) / posterior_sd,
    ess_bulk = posterior::ess_bulk(kept)
  )
}

runs <- do.call(rbind, lapply(1:50, run_one))
utils::write.csv(
  runs,
  "~/github/greta-dev/greta.benchmarks/2026-09-30-stuck-chain-rate/results.csv",
  row.names = FALSE
)
print(runs, digits = 3)
