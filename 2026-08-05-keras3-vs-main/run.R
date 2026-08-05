# Does porting greta's optimisers to Keras 3 make greta slower?
#
# Run this from its own directory, with the greta repo at GRETA_REPO. cross
# works on the git repo in the working directory, so the run happens there and
# the results are written back here.
#
# Each branch resolves its own Python stack -- main pins TF 2.15.1, the Keras 3
# branch pins 2.21.0 -- so a ratio here blends the port with the version bump.
# Holding the stack fixed is not possible: main calls
# tf$keras$optimizers$legacy$*, which Keras 3 removed. The stack each branch
# actually resolved is recorded below.

library(cross)

run_dir <- normalizePath(".")
greta_repo <- Sys.getenv("GRETA_REPO", "~/github/greta-dev/greta")
greta_repo <- normalizePath(path.expand(greta_repo))
source(file.path(dirname(run_dir), "provenance.R"))

branch_current <- "use-keras3-i633"
branch_reference <- "main"

owd <- setwd(greta_repo)
on.exit(setwd(owd), add = TRUE)

# Reformatting the write-up should not cost another run of the benchmark, so an
# existing results.rds is reused. Delete it to measure again.
#
# The environment is captured alongside the measurements and stored with them,
# so a later reformat reports when the benchmark ran rather than when the
# markdown was rewritten.
results_rds <- file.path(run_dir, "results.rds")

measured <- if (file.exists(results_rds)) {
  readRDS(results_rds)
} else {
  raw <- run_branches(
    {
      library(greta)

      n <- 30
      x <- rnorm(n)
      m <- normal(0, 10)
      distribution(x) <- normal(m, 1)
      mod <- model(m)

      build_model <- function() {
        y <- rnorm(30)
        mu <- normal(0, 10)
        distribution(y) <- normal(mu, 1)
        model(mu)
      }

      # TensorFlow traces a graph on the first call, so one untimed run of each
      # task keeps compilation out of the measurements.
      invisible(opt(mod, optimiser = adam(), max_iterations = 5))
      invisible(opt(mod, optimiser = bfgs(), max_iterations = 5))
      invisible(calculate(m, nsim = 1))
      invisible(mcmc(
        mod,
        n_samples = 10,
        warmup = 10,
        chains = 1,
        verbose = FALSE
      ))

      timings <- bench::mark(
        build = build_model(),
        calculate = calculate(m, nsim = 1),
        opt_adam = opt(mod, optimiser = adam(), max_iterations = 100),
        opt_bfgs = opt(mod, optimiser = bfgs(), max_iterations = 100),
        mcmc_short = mcmc(
          mod,
          n_samples = 100,
          warmup = 100,
          chains = 1,
          verbose = FALSE
        ),
        # the branches draw different numbers, so results cannot be compared
        check = FALSE,
        filter_gc = FALSE,
        min_iterations = 5,
        max_iterations = 10
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
        timings = timings[, c("expression", "min", "median", "itr/sec")]
      )
    },
    branches = branch_reference
  )
  list(raw = raw, provenance = host_provenance())
}

setwd(owd)

saveRDS(measured, results_rds)

raw <- measured$raw

timings <- do.call(
  rbind,
  lapply(seq_len(nrow(raw)), function(i) {
    stamps <- raw$result[[i]]$timings
    data.frame(
      # bench_expr deparses to the whole call under as.character(); the short
      # labels given to bench::mark() are its names
      task = names(stamps$expression),
      min = as.numeric(stamps$min),
      median = as.numeric(stamps$median),
      branch = raw$branch[[i]]
    )
  })
)

as_ms <- function(x) round(x * 1000, 2)

comparison <- do.call(
  rbind,
  lapply(unique(timings$task), function(task) {
    current <- timings[
      timings$task == task & timings$branch == branch_current,
    ]
    reference <- timings[
      timings$task == task & timings$branch == branch_reference,
    ]
    data.frame(
      task = task,
      current_median_ms = as_ms(current$median),
      reference_median_ms = as_ms(reference$median),
      median_ratio = round(current$median / reference$median, 3),
      min_ratio = round(current$min / reference$min, 3)
    )
  })
)

names(comparison) <- c(
  "task",
  paste0(branch_current, " (ms)"),
  paste0(branch_reference, " (ms)"),
  "median ratio",
  "min ratio"
)

stacks <- vapply(
  seq_len(nrow(raw)),
  function(i) {
    stack <- raw$result[[i]]$stack
    sprintf(
      "python %s, tensorflow %s, tfp %s",
      stack[["python"]],
      stack[["tensorflow"]],
      stack[["tfp"]]
    )
  },
  character(1)
)
names(stacks) <- paste("stack,", raw$branch)

write_results_md(
  path = file.path(run_dir, "results.md"),
  title = "Keras 3 optimiser port versus main",
  question = paste(
    "Does porting greta's Keras optimisers to the Keras 3 API, and raising the",
    "pinned dependencies to TensorFlow 2.21, make greta slower? A ratio below",
    "1 means the branch is faster."
  ),
  body = c(
    knitr::kable(comparison, row.names = FALSE),
    "",
    paste(
      "`bench::mark()`, 5 to 10 iterations per cell. `min` is the statistic",
      "least contaminated by garbage collection and scheduling; where the two",
      "branches share byte-identical code, it is the one to read."
    )
  ),
  provenance = measured$provenance,
  extra = c(
    as.list(stacks),
    list(
      `greta, current` = git_sha(greta_repo, branch_current),
      `greta, reference` = git_sha(greta_repo, branch_reference)
    )
  )
)

cat("wrote", file.path(run_dir, "results.md"), "\n")
