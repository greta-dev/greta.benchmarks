# Sample until the chains are good enough, and report what that cost.
#
# Fixing the iterations and gating on quality throws away every run that misses
# the gate - at greta's defaults that was 47 runs in 50, leaving nothing to
# compare. Inverting it removes the gate: fix the quality, measure the cost. A
# branch that cannot get there is reported with `hit_cap` rather than dropped.
#
# This reimplements greta's own get_enough_draws() rather than sourcing it.
# That helper lives in the repo being measured, so using it would let the
# measuring instrument change with the branch under test. It also uses
# coda::effectiveSize(), which fits an AR model per chain with no between-chain
# information and so reports a large ESS for chains stuck in different modes -
# the failure a sampler comparison exists to catch (Vehtari et al. 2021).
#
# Only defines functions, so it is safe to source before greta is attached -
# which matters because {cross} sources it by absolute path in a subprocess.

# Resident set size: the physical RAM this process currently holds. Not
# residual sum of squares.
#
# It is the right memory number for greta because mem_alloc from bench sees the
# R heap only, and greta's memory is in the TensorFlow graph on the Python
# side. Measured 2026-09-22, the two rank `linear` and `cjs` in opposite order.
#
# This is end-of-run RSS, not a true peak - that needs getrusage(), which R
# does not expose, and macOS has no /proc to read VmHWM from. For a short-lived
# process doing monotonically growing work, where TensorFlow does not release
# memory back to the OS, the two are close. Do not read it as a high-water mark.
rss_mb <- function() {
  ps::ps_memory_info()[["rss"]] / 1024^2
}

# Per-variable summary. MCSE is the column that makes two branches comparable:
# posterior means always differ between runs, and only the Monte Carlo error
# says whether a difference means anything.
posterior_summary <- function(draws) {
  summ <- posterior::summarise_draws(
    posterior::as_draws_array(draws),
    "mean",
    "sd",
    "mcse_mean",
    "mcse_sd",
    # quantile2() names these q5, q25 ... rather than `5%`
    q = ~ posterior::quantile2(.x, probs = c(0.05, 0.25, 0.5, 0.75, 0.95)),
    "rhat",
    "ess_bulk",
    "ess_tail"
  )
  as.data.frame(summ)
}

# Rank-normalised Rhat and ess_bulk are not incrementally computable - adding a
# chunk re-ranks every existing draw - so this is a full pass each time. It is
# a couple of percent of a sampling run, and the loop needs the number to size
# the next chunk.
target_progress <- function(summ, target_ess) {
  ess_min <- min(summ$ess_bulk, na.rm = TRUE)
  rhat_max <- max(summ$rhat, na.rm = TRUE)

  list(
    ess_bulk_min = ess_min,
    ess_bulk_median = median(summ$ess_bulk, na.rm = TRUE),
    rhat_max = rhat_max,
    n_variables = nrow(summ),
    reached = ess_min >= target_ess && rhat_max < 1.01
  )
}

# Efficiency is ESS per iteration so far, extrapolated linearly with 20%
# headroom - efficiency is estimated from a short chain and is optimistic early.
next_chunk <- function(progress, n_iterations, target_ess, max_chunk) {
  efficiency <- progress$ess_bulk_min / n_iterations
  # a chain producing almost no effective samples gives an efficiency near zero
  # and would ask for an absurd number of iterations
  wanted <- 1.2 * (target_ess - progress$ess_bulk_min) / max(efficiency, 1e-6)
  as.integer(max(min(wanted, max_chunk), 100))
}

#' Sample until minimum bulk-ESS reaches `target_ess` and all Rhat are below
#' 1.01, or until `time_limit` seconds pass.
#'
#' Returns one row: what it cost, whether it got there, and a `posterior`
#' list-column of the per-variable summary, so two branches can be compared on
#' what they estimated and not only on how fast they got there.
sample_to_target <- function(
  model,
  target_ess = 1000,
  chains = 4,
  warmup = 2000,
  initial_samples = 2000,
  time_limit = 300,
  max_chunk = 20000,
  n_cores = 4L
) {
  # bench::hires_time() rather than Sys.time(): seconds as a plain double, so
  # the cap check is a subtraction. Not bench::mark() - that times a repeated
  # deterministic expression, and this is one run that grows until it is good
  # enough.
  start <- bench::hires_time()

  draws <- greta::mcmc(
    model,
    n_samples = initial_samples,
    warmup = warmup,
    chains = chains,
    n_cores = n_cores,
    verbose = FALSE
  )

  n_iterations <- initial_samples
  summ <- posterior_summary(draws)
  progress <- target_progress(summ, target_ess)

  while (!progress$reached && bench::hires_time() - start < time_limit) {
    chunk <- next_chunk(progress, n_iterations, target_ess, max_chunk)
    draws <- greta::extra_samples(
      draws,
      n_samples = chunk,
      n_cores = n_cores,
      verbose = FALSE
    )
    n_iterations <- n_iterations + chunk
    summ <- posterior_summary(draws)
    progress <- target_progress(summ, target_ess)
  }

  total <- bench::hires_time() - start

  out <- data.frame(
    elapsed = total,
    mcmc_samples = n_iterations,
    seconds_per_1000_ess = 1000 * total / progress$ess_bulk_min,
    ess_bulk_min = progress$ess_bulk_min,
    ess_bulk_median = progress$ess_bulk_median,
    rhat_max = progress$rhat_max,
    n_variables = progress$n_variables,
    # TRUE means the target was never reached, so `elapsed` is a floor and not
    # a measurement. Never drop these rows: a branch that cannot converge is
    # the most important thing a comparison can report.
    hit_cap = !progress$reached
  )

  out$posterior <- list(summ)
  out
}
