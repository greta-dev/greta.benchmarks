# Does wiring model(compile=) through to tf_function(jit_compile=) make greta
# faster?
#
# `model(compile = TRUE)` is documented as applying XLA JIT compilation but has
# been inert since Jan 2023 (greta commit 7e3e81ac removed its last consumer,
# the TF1 session-config API, and nothing replaced it). The `wire-jit-compile`
# branch passes it through at the two tf_function() sites in dag_class.R.
#
# Both branches resolve the same Python stack, so a ratio here is the effect of
# the wiring alone rather than a version bump.
#
# The model is a plain regression on purpose. XLA cannot compile the gradients
# of FillScaleTriL or CorrelationCholesky, so anything using wishart(),
# lkj_correlation() or cholesky_variable() errors on the wired branch rather
# than producing a timing.
#
# An earlier attempt measured this by patching the working tree and comparing
# compile=TRUE against compile=FALSE in one session. That is not reproducible by
# anyone else, so it was discarded in favour of a branch comparison. It did
# suggest no steady-state speed difference and a one-off compilation cost on
# first run, on three replicates too noisy to conclude from.

library(cross)
library(here)
library(withr)
library(fs)

# here() anchors on greta.benchmarks, so these hold wherever the script is run
# from, and nothing depends on the working directory being the run directory
run_dir <- here("2026-08-19-jit-compile-vs-main")
source(here("provenance.R"))

greta_repo <- path_expand(Sys.getenv("GRETA_REPO", "~/github/greta-dev/greta"))

branch_current <- "wire-jit-compile"
branch_reference <- "main"

results_rds <- path(run_dir, "results.rds")

# cross operates on the git repo in the working directory, so the run has to
# happen inside the greta checkout. with_dir() restores the old directory on
# the way out, including if run_branches() errors - setwd() plus on.exit() is
# the same thing with more ways to get it wrong.
measured <- local({
  raw <- with_dir(
    greta_repo,
    run_branches(
      {
        library(greta)

        set.seed(2026 - 08 - 19)
        n <- 200
        x <- rnorm(n)
        y_obs <- 2 + 1.5 * x + rnorm(n, sd = 0.5)

        build_model <- function() {
          intercept <- normal(0, 10)
          slope <- normal(0, 10)
          sd_resid <- lognormal(0, 1)
          y <- as_data(y_obs)
          distribution(y) <- normal(intercept + slope * x, sd_resid)
          model(intercept, slope, sd_resid)
        }

        mod <- build_model()

        # TensorFlow traces on first call, and XLA compiles then too, so one
        # untimed run of each task keeps compilation out of the measurements.
        # The compilation cost is real but it is a separate question from
        # steady-state speed, and mixing them hides both.
        invisible(mcmc(
          mod,
          n_samples = 10,
          warmup = 10,
          chains = 1,
          verbose = FALSE
        ))
        invisible(calculate(mod$dag$target_nodes[[1]], nsim = 1))

        timings <- bench::mark(
          build = build_model(),
          mcmc_short = mcmc(
            mod,
            n_samples = 200,
            warmup = 200,
            chains = 1,
            verbose = FALSE
          ),
          # the branches draw different numbers, so results cannot be compared
          check = FALSE,
          filter_gc = FALSE,
          min_iterations = 10,
          max_iterations = 20
        )

        tfp_version <- tryCatch(
          as.character(
            reticulate::import("tensorflow_probability")$`__version__`
          ),
          error = function(e) NA_character_
        )

        list(
          stack = c(
            python = as.character(reticulate::py_config()$version),
            tensorflow = as.character(tensorflow::tf$`__version__`),
            tfp = tfp_version
          ),
          timings = timings[, c(
            "expression",
            "min",
            "median",
            "itr/sec",
            "mem_alloc"
          )]
        )
      },
      branches = branch_reference
    )
  )
  # SHAs captured here, not at report time: branches move, so resolving them
  # later would silently record a different commit than the one measured
  list(
    raw = raw,
    provenance = host_provenance(),
    shas = c(
      current = git_sha(greta_repo, branch_current),
      reference = git_sha(greta_repo, branch_reference)
    )
  )
})

saveRDS(measured, results_rds, compress = "xz")

# 02-report.R renders results.qmd from this. Run it after this script.
