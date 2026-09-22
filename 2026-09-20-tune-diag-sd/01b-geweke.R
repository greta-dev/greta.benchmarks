# Does changing `n` in tune_diag_sd() break calibration?
#
#   Rscript --quiet --vanilla 2026-09-20-tune-diag-sd/01b-geweke.R \
#     <greta-checkout> <label> <output.rds>
#
# A Geweke test compares draws from the prior against draws from the Markov
# chain targeting the same joint distribution. If the sampler is correct the two
# are the same distribution, so a KS test of one against the other should not
# reject. greta's own test asserts `p >= 0.005` and reports nothing else; this
# records the statistic and p-value, so the three branches can be compared
# rather than each just saying "passed".
#
# Numbered 01b rather than 03: it is a measurement, like 01-measure.R, not a
# report. It takes one checkout per invocation so the three branches can run
# concurrently in detached worktrees.
#
# slice() is the control. It sets uses_metropolis = FALSE and never calls
# tune_diag_sd(), so it must be unaffected by any of these branches. hmc() and
# rwmh() both tune diag_sd and are the ones that can move.
#
# This is a stochastic test: a single p-value per sampler is weak evidence, and
# an occasional low p-value is expected rather than alarming. It is run here to
# catch a gross calibration break, not to certify correctness.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) {
  stop(
    "usage: 01b-geweke.R <greta-checkout> <label> [output.rds]",
    call. = FALSE
  )
}
greta_checkout <- normalizePath(args[[1]], mustWork = TRUE)
label <- args[[2]]

# defaults into this run directory, not a temporary one. results.qmd picks up
# every `geweke-*.rds` here, so the numbers live beside the script that made
# them rather than somewhere that gets cleaned up
out_rds <- if (length(args) >= 3) {
  args[[3]]
} else {
  file.path(
    here::here("2026-09-20-tune-diag-sd"),
    paste0("geweke-", label, ".rds")
  )
}

suppressMessages(pkgload::load_all(greta_checkout, quiet = TRUE))
source(file.path(greta_checkout, "tests", "testthat", "helpers.R"))

sha <- system2(
  "git",
  c("-C", shQuote(greta_checkout), "rev-parse", "HEAD"),
  stdout = TRUE
)

# the model greta's own Geweke test uses: theta ~ normal(mu1, sd1),
# x[i] ~ normal(theta, sd2). Seeded here so the three branches are compared on
# the same model rather than on three different draws of mu1/sd1/sd2
set.seed(2026 - 09 - 20)

n <- 10
mu1 <- rnorm(1, 0, 3)
sd1 <- rlnorm(1)
sd2 <- rlnorm(1)

p_theta <- function(n) rnorm(n, mu1, sd1)
p_x_bar_theta <- function(theta) rnorm(n, theta, sd2)

x <- as_data(rep(0, n))
greta_theta <- normal(mu1, sd1)
distribution(x) <- normal(greta_theta, sd2)
model <- model(greta_theta, precision = "single")

run_one <- function(sampler_name, sampler, ...) {
  started <- Sys.time()
  draws <- check_geweke(
    sampler = sampler,
    model = model,
    data = x,
    p_theta = p_theta,
    p_x_bar_theta = p_x_bar_theta,
    ...
  )
  ks <- geweke_ks(draws)

  list(
    summary = data.frame(
      branch = label,
      sha = sha,
      sampler = sampler_name,
      statistic = unname(ks$statistic),
      p_value = ks$p.value,
      elapsed_mins = as.numeric(difftime(Sys.time(), started, units = "mins")),
      # what greta's own test would have concluded
      passes_greta_threshold = ks$p.value >= 0.005
    ),
    # the two vectors check_geweke() compares: prior draws and chain draws.
    # Stored in full, because a summary answers one question and these answer
    # any of them -- QQ, ECDF, a different test -- without a 30-minute re-run.
    # A few hundred doubles per sampler, so there is no reason not to.
    draws = data.frame(
      branch = label,
      sampler = sampler_name,
      target_theta = draws$target_theta,
      greta_theta = draws$greta_theta
    )
  )
}

runs <- list(
  run_one("hmc", hmc(), thin = 5),
  run_one("rwmh", rwmh(), warmup = 2000, thin = 5),
  run_one("slice", slice())
)

results <- do.call(rbind, lapply(runs, \(r) r$summary))
draws <- do.call(rbind, lapply(runs, \(r) r$draws))

saveRDS(
  list(
    results = results,
    draws = draws,
    label = label,
    sha = sha,
    mu1 = mu1,
    sd1 = sd1,
    sd2 = sd2
  ),
  out_rds,
  compress = "xz"
)

print(results, row.names = FALSE)
cat("wrote", out_rds, "\n")
