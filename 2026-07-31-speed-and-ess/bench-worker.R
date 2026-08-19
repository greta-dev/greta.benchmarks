# Benchmark ONE (branch, python stack) combination, in this R session.
#
# Not meant to be called directly -- `bench-compare.R` invokes it once per
# combination, in series. It must be a fresh session each time because
# reticulate initialises Python once per process, so a session cannot switch
# TF stacks, and a warm TF has different timings from a cold one.
#
# Workloads come from two places that already existed but were never committed
# as benchmarks:
#   * speed      -- touchstone/script.R (touchstone itself is retired)
#   * ESS/second -- greta issue #790, "code for comparing HMC to Adaptive HMC"
#                   (Golding): min(effectiveSize(draws)) / elapsed
#
# Env vars:
#   GRETA_SRC          path to a greta checkout/worktree     (required)
#   GRETA_LABEL        name for this row                     (required)
#   GRETA_OUT          .rds to write                         (required)
#   GRETA_TEST_PYTHON  python to use; omit for greta default (optional)
#   GRETA_REPS         speed reps, default 5
#   GRETA_CHAINS       mcmc chains for the ESS models, default 4
#   GRETA_WARMUP       warmup for the ESS models, default 1000
#   GRETA_QUICK        "true" to shrink the ESS workload for a smoke test

src <- Sys.getenv("GRETA_SRC")
label <- Sys.getenv("GRETA_LABEL")
out <- Sys.getenv("GRETA_OUT")
stopifnot(nzchar(src), nzchar(label), nzchar(out))

py <- Sys.getenv("GRETA_TEST_PYTHON")
if (nzchar(py)) Sys.setenv(RETICULATE_PYTHON = py)
Sys.setenv(TF_CPP_MIN_LOG_LEVEL = 2)

reps <- as.integer(Sys.getenv("GRETA_REPS", "5"))
n_chains <- as.integer(Sys.getenv("GRETA_CHAINS", "4"))
warmup <- as.integer(Sys.getenv("GRETA_WARMUP", "1000"))
quick <- identical(Sys.getenv("GRETA_QUICK"), "true")
if (quick) {
  reps <- 2
  n_chains <- 2
  warmup <- 200
}

suppressMessages(pkgload::load_all(src, quiet = TRUE))

stack <- tryCatch(
  {
    tf <- reticulate::py_to_r(reticulate::import("tensorflow")$`__version__`)
    tfp <- reticulate::py_to_r(reticulate::import("tensorflow_probability")$`__version__`)
    kr <- reticulate::py_to_r(reticulate::import("keras")$`__version__`)
    sprintf("tf%s/tfp%s/keras%s", tf, tfp, kr)
  },
  error = function(e) "unknown"
)

git_sha <- tryCatch(
  system2("git", c("-C", src, "rev-parse", "--short", "HEAD"), stdout = TRUE),
  error = function(e) NA_character_
)

cat(sprintf("\n[%s] %s @ %s\n", label, stack, git_sha))

rows <- list()
add_row <- function(task, metric, value, unit, note = NA_character_) {
  rows[[length(rows) + 1]] <<- data.frame(
    label = label, stack = stack, sha = git_sha,
    task = task, metric = metric, value = value, unit = unit,
    note = note, stringsAsFactors = FALSE
  )
  cat(sprintf("  %-28s %-14s %10.4f %s %s\n", task, metric, value, unit,
              if (is.na(note)) "" else paste0("(", note, ")")))
}

elapsed <- function(expr) system.time(force(expr))[["elapsed"]]

# ---------------------------------------------------------------- speed ----
# the four touchstone workloads, kept because they are cheap and they isolate
# graph construction from sampling

cat("\n-- speed (from touchstone/script.R) --\n")

med <- function(f, n = reps) stats::median(vapply(seq_len(n), function(i) elapsed(f()), numeric(1)))

add_row("create_normal", "median_time", med(function() normal(0, 1)), "s")
add_row("create_model", "median_time", med(function() model(normal(0, 1))), "s")
add_row(
  "run_mcmc_trivial", "median_time",
  med(function() mcmc(model(normal(0, 1)), verbose = FALSE)),
  "s"
)

set.seed(2026)
x_lin <- iris$Petal.Length
y_lin <- iris$Sepal.Length
basic_example <- function() {
  int <- normal(0, 5)
  coefficient <- normal(0, 3)
  sd_obs <- lognormal(0, 3)
  mean_obs <- int + coefficient * x_lin
  y <- as_data(y_lin)
  distribution(y) <- normal(mean_obs, sd_obs)
  m <- model(int, coefficient, sd_obs)
  mcmc(m, n_samples = 200, warmup = 200, chains = 1, verbose = FALSE)
}
add_row("basic_example_linear", "median_time", med(basic_example, max(2, reps %/% 2)), "s")

# ------------------------------------------------------ ESS per second ----
# from issue #790. The metric that matters for sampler work: effective samples
# per second of wall clock, for the WORST-sampled variable. Higher is better.

cat("\n-- efficiency (from issue #790) --\n")

worst_efficiency <- function(draws, secs) {
  min(coda::effectiveSize(draws)) / secs
}
worst_rhat <- function(draws) {
  rhats <- coda::gelman.diag(draws, autoburnin = FALSE, multivariate = FALSE)
  max(rhats$psrf[, 2])
}

# the knotty model: correlated multivariate normal with wildly different
# marginal variances. `hard` is what separates samplers; `easy` is the control.
mvn_model <- function(correlation, rel_sd_range, dim = 4) {
  C <- matrix(correlation, dim, dim)
  diag(C) <- 1
  sds <- seq(1, rel_sd_range, length.out = dim)
  Sigma <- diag(sds) %*% C %*% diag(sds)
  x <- multivariate_normal(mean = zeros(1, dim), Sigma = Sigma)
  model(x)
}

# only benchmark samplers this branch actually has -- adaptive_hmc() exists on
# some branches and not others, which is precisely what we want to compare
samplers <- list(hmc = function() hmc())
if (exists("adaptive_hmc")) {
  samplers$adaptive_hmc <- function() adaptive_hmc()
}
# hmc with too few leapfrog steps: stands in for a harder posterior
samplers$hmc_short_leapfrog <- function() hmc(Lmin = 1, Lmax = 3)

scenarios <- list(
  easy = list(correlation = 0, rel_sd_range = 1),
  hard = list(correlation = 0.99, rel_sd_range = 1e5)
)
if (quick) scenarios <- scenarios["easy"]

# ESS from a single MCMC run is far too noisy to compare branches with: an
# early run showed 6.2x between two branches whose sampling code is
# byte-identical, both converged (rhat 1.03 vs 1.00). greta's sampler is not
# seeded (#285/#427), so the only honest approach is to repeat and report
# spread. Anything claiming an efficiency difference smaller than this spread
# is claiming noise.
ess_reps <- as.integer(Sys.getenv("GRETA_ESS_REPS", if (quick) "2" else "5"))
cat(sprintf("   (%d replicate MCMC runs per cell)\n", ess_reps))

for (sc_name in names(scenarios)) {
  sc <- scenarios[[sc_name]]
  for (s_name in names(samplers)) {
    res <- tryCatch(
      {
        reps_eff <- numeric(ess_reps)
        reps_ess <- numeric(ess_reps)
        reps_secs <- numeric(ess_reps)
        reps_rhat <- numeric(ess_reps)
        for (k in seq_len(ess_reps)) {
          m <- mvn_model(sc$correlation, sc$rel_sd_range)
          secs <- elapsed(
            draws <- mcmc(
              m,
              warmup = warmup,
              chains = n_chains,
              sampler = samplers[[s_name]](),
              verbose = FALSE
            )
          )
          reps_secs[k] <- secs
          reps_ess[k] <- min(coda::effectiveSize(draws))
          reps_eff[k] <- worst_efficiency(draws, secs)
          reps_rhat[k] <- worst_rhat(draws)
        }
        list(
          ok = TRUE,
          secs = stats::median(reps_secs),
          eff = stats::median(reps_eff),
          eff_min = min(reps_eff),
          eff_max = max(reps_eff),
          rhat = max(reps_rhat),
          ess = stats::median(reps_ess)
        )
      },
      error = function(e) list(ok = FALSE, msg = conditionMessage(e))
    )

    task <- paste0("mvn_", sc_name, "/", s_name)
    if (!res$ok) {
      add_row(task, "ess_per_sec", NA_real_, "ess/s", substr(res$msg, 1, 60))
      next
    }

    # Convergence gate. An unconverged run produces a meaningless ESS, and
    # therefore a meaningless efficiency -- and because greta's sampler is not
    # seeded (#285/#427) it happens intermittently, especially with short
    # warmup. Reporting it as a number invites false comparisons: an early
    # smoke run showed rhat = 3.0 and a spurious 23x "speedup" between two
    # branches whose sampling code is byte-identical. Record the value but mark
    # it, and let the comparison drop it.
    converged <- is.finite(res$rhat) && res$rhat < 1.1
    flag <- if (converged) NA_character_ else "NOT CONVERGED - do not compare"

    # spread across replicates: the smallest difference worth believing
    spread <- if (res$eff_min > 0) res$eff_max / res$eff_min else NA_real_
    add_row(task, "ess_per_sec", res$eff, "ess/s", flag)
    add_row(
      task, "ess_per_sec_spread", spread, "max/min",
      "noise floor - ignore ratios below this"
    )
    add_row(task, "min_ess", res$ess, "ess", flag)
    add_row(task, "elapsed", res$secs, "s")
    add_row(task, "worst_rhat", res$rhat, "", "worst of replicates, <1.1 ideal")
    if (!converged) {
      cat(sprintf(
        "    !! %s did not converge (rhat %.2f) -- efficiency not comparable\n",
        task, res$rhat
      ))
    }
  }
}

saveRDS(do.call(rbind, rows), out)
cat(sprintf("\nwrote %s\n", out))
