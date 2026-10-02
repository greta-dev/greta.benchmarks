# Every function greta traces, and what tracing costs opt(), on main and three
# versions of greta#843.
#
#   Rscript --quiet --vanilla 2026-09-30-trace-census-i546/01-measure.R
#
# Two questions:
#
#   1. The census. For each user-facing call, in a fresh process: how many
#      traced functions does greta create, and how many times is each traced?
#      tensorflow::tf_function() is wrapped to record every function greta
#      makes with it, so nothing is found by luck. A function traced more than
#      once is retracing; one created again on every call is tracing that
#      could be reused. Functions TensorFlow creates internally, such as
#      pfor's, are not counted.
#   2. The cost. The first opt() call in a fresh process pays for tracing; a
#      second does not. Both are timed on each of the five example models.
#
# The builds:
#
#   main       282944f5
#   branch     greta#843 as pushed, e57e4c98
#   fix        branch + fix.patch: opt() steps use a log-density function
#              traced for one row
#   fix_check  branch + fix-check.patch: fix, and checking initial values
#              uses that same function in opt()
#
# Timings use bench::hires_time(), which on macOS stops while the machine
# sleeps, so a closed lid pauses a measurement rather than inflating it.

library(here)
library(fs)

run_dir <- here("2026-09-30-trace-census-i546")
greta_repo <- path_expand(Sys.getenv("GRETA_REPO", "~/github/greta-dev/greta"))
source(here("R", "provenance.R"))

builds <- list(
  main = list(sha = "282944f572bb386ebf9b6bc21749336cbbea42b8", patch = NULL),
  branch = list(sha = "e57e4c981195da732a7f9156ce99463fc55c4b54", patch = NULL),
  fix = list(
    sha = "e57e4c981195da732a7f9156ce99463fc55c4b54",
    patch = "fix.patch"
  ),
  fix_check = list(
    sha = "e57e4c981195da732a7f9156ce99463fc55c4b54",
    patch = "fix-check.patch"
  )
)

install_build <- function(name, build) {
  source_dir <- path(tempdir(), paste0("greta-", name))
  dir_create(source_dir)
  extracted <- system(sprintf(
    "git -C %s archive %s | tar -x -C %s",
    shQuote(greta_repo),
    build$sha,
    shQuote(source_dir)
  ))
  stopifnot(extracted == 0)
  if (!is.null(build$patch)) {
    patched <- system2(
      "git",
      c("-C", shQuote(source_dir), "apply", shQuote(path(run_dir, build$patch)))
    )
    stopifnot(patched == 0)
  }
  lib <- path(run_dir, "libs", name)
  dir_create(lib)
  installed <- system2(
    "R",
    c("CMD", "INSTALL", "--no-test-load", paste0("--library=", lib), source_dir)
  )
  stopifnot(installed == 0)
  lib
}

libs <- Map(install_build, names(builds), builds)

census <- function(lib, scenario) {
  callr::r(
    function(scenario) {
      registry <- new.env()
      registry$made <- list()
      original <- tensorflow::tf_function
      utils::assignInNamespace(
        "tf_function",
        function(f, input_signature = NULL, ...) {
          traced <- original(f, input_signature = input_signature, ...)
          caller <- sys.call(-1)
          # the free state's rows, which tell the log-density function's
          # open-signature and one-row versions apart
          rows <- if (is.null(input_signature)) {
            "no signature"
          } else {
            n_rows <- input_signature[[1]]$shape$as_list()[[1]]
            if (is.null(n_rows)) "rows open" else paste(n_rows, "row")
          }
          registry$made[[length(registry$made) + 1]] <- list(
            traced = traced,
            made_by = paste(deparse(caller[[1]]), collapse = ""),
            rows = rows
          )
          traced
        },
        ns = "tensorflow"
      )

      library(greta)
      set.seed(2026 - 09 - 30)
      int <- normal(0, 10)
      coef <- normal(0, 10)
      sd <- cauchy(0, 3, truncation = c(0, Inf))
      mu <- int + coef * attitude$complaints
      distribution(attitude$rating) <- normal(mu, sd)
      m <- model(int, coef, sd)

      sample <- function() {
        mcmc(m, n_samples = 200, warmup = 200, chains = 4, verbose = FALSE)
      }
      switch(
        scenario,
        model = NULL,
        opt = opt(m),
        opt_adam = opt(m, optimiser = adam(), max_iterations = 100),
        opt_twice = {
          opt(m)
          opt(m)
        },
        opt_hessian = opt(m, hessian = TRUE),
        mcmc = sample(),
        extra_samples = extra_samples(sample(), n_samples = 200, verbose = FALSE),
        calculate_values = calculate(mu, values = sample()),
        calculate_nsim = calculate(mu, nsim = 10)
      )

      data.frame(
        made_by = vapply(registry$made, `[[`, "", "made_by"),
        rows = vapply(registry$made, `[[`, "", "rows"),
        traces = vapply(
          registry$made,
          function(x) as.integer(x$traced$experimental_get_tracing_count()),
          1L
        )
      )
    },
    args = list(scenario = scenario),
    libpath = c(lib, .libPaths())
  )
}

scenarios <- c(
  "model",
  "opt",
  "opt_adam",
  "opt_twice",
  "opt_hessian",
  "mcmc",
  "extra_samples",
  "calculate_values",
  "calculate_nsim"
)

census_rows <- list()
for (build in names(libs)) {
  for (scenario in scenarios) {
    rows <- census(libs[[build]], scenario)
    if (nrow(rows) > 0) {
      census_rows[[length(census_rows) + 1]] <- cbind(
        build = build,
        scenario = scenario,
        rows
      )
    }
  }
}
census_results <- do.call(rbind, census_rows)

first_opt <- function(lib, example) {
  callr::r(
    function(examples_file, example) {
      library(greta)
      source(examples_file)
      m <- bench_examples()[[example]]()
      fit <- function() opt(m, optimiser = adam(), max_iterations = 100)
      seconds <- function(expr) {
        start <- bench::hires_time()
        force(expr)
        as.numeric(bench::hires_time() - start)
      }
      c(first = seconds(fit()), second = seconds(fit()))
    },
    args = list(examples_file = here("R", "examples.R"), example = example),
    libpath = c(lib, .libPaths())
  )
}

examples <- c(
  "linear",
  "multiple_linear",
  "hierarchical_linear",
  "eight_schools",
  "cjs"
)
n_reps <- 3

timing_rows <- list()
for (rep in seq_len(n_reps)) {
  for (build in names(libs)) {
    for (example in examples) {
      times <- first_opt(libs[[build]], example)
      timing_rows[[length(timing_rows) + 1]] <- data.frame(
        build = build,
        example = example,
        rep = rep,
        first = times[["first"]],
        second = times[["second"]]
      )
    }
  }
}
timing_results <- do.call(rbind, timing_rows)

saveRDS(
  list(
    census = census_results,
    timings = timing_results,
    builds = builds,
    provenance = host_provenance(packages = c("tensorflow", "reticulate"))
  ),
  path(run_dir, "results.rds")
)
cat("wrote", path(run_dir, "results.rds"), "\n")
