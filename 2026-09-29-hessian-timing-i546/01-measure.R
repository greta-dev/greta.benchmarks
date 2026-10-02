# How long does opt(hessian = TRUE) take, on main and on greta-dev/greta#843?
#
#   Rscript --quiet --vanilla 2026-09-29-hessian-timing-i546/01-measure.R
#
# #843 changes how greta takes hessians: one graph build for all targets instead
# of one per target, and TensorFlow's vectorised `pfor` jacobian only for
# targets of at least pfor_min_elements() (100) elements, a while loop below
# that. Its NEWS entry and the comment on pfor_min_elements() quote timings that
# had no run behind them. This is that run.
#
# Two questions:
#
#   1. main against the branch, at four target shapes: 5 and 20 scalar targets
#      (the case #546 reported, where main rebuilt the graph per target), and
#      one target of 100 or 400 elements (which still takes the pfor route).
#   2. on the branch only, pfor against the while loop at each shape, by
#      overriding pfor_min_elements(). This is what the threshold of 100 rests
#      on.
#
# One measurement, one process (AGENTS.md): every replicate builds its model
# and times opt(hessian = TRUE) in a fresh R process, so each pays its own
# TensorFlow start-up and first trace. The first call is the cost a user sees,
# and it includes tracing, which is what #546 is about. A second call in the
# same process is recorded too, as the cost once traced.

library(cross)
library(here)
library(withr)
library(fs)
library(dplyr)
library(purrr)

run_dir <- here("2026-09-29-hessian-timing-i546")
source(here("R", "provenance.R"))

greta_repo <- path_expand(Sys.getenv("GRETA_REPO", "~/github/greta-dev/greta"))

branch_reference <- "main"
branch_under_test <- Sys.getenv("GRETA_HESS_BRANCH", "faster-hessians-i546")
branches <- c(branch_reference, branch_under_test)

n_reps <- Sys.getenv("GRETA_HESS_REPS", "5")

subprocess_env <- c(
  callr::rcmd_safe_env(),
  GRETA_HESS_REPS = n_reps
)

# current = FALSE: record only the named branches, never whatever happens to be
# checked out
raw <- with_dir(
  greta_repo,
  run_branches(
    {
      n_reps <- as.integer(Sys.getenv("GRETA_HESS_REPS"))

      # one replicate, in its own process. `route` forces the jacobian method on
      # a branch that has pfor_min_elements(); NA leaves greta's own choice
      one_run <- function(shape, route) {
        callr::r(
          function(shape, route) {
            library(greta)
            if (!is.na(route)) {
              threshold <- if (route == "pfor") 0L else .Machine$integer.max
              utils::assignInNamespace(
                "pfor_min_elements",
                function() threshold,
                ns = "greta"
              )
            }

            set.seed(2026 - 09 - 29)
            y <- stats::rnorm(shape$n)
            if (shape$kind == "scalars") {
              # model() names its targets from the expressions it is called
              # with, so the call is built from symbols rather than do.call()
              # on the arrays themselves
              names <- paste0("b", seq_len(shape$n))
              for (name in names) {
                assign(name, variable())
              }
              distribution(y) <- normal(do.call(c, mget(names)), 1)
              m <- eval(as.call(c(quote(model), lapply(names, as.name))))
            } else {
              b <- variable(dim = shape$n)
              distribution(y) <- normal(b, 1)
              m <- model(b)
            }

            first <- system.time(opt(m, hessian = TRUE))[["elapsed"]]
            second <- system.time(opt(m, hessian = TRUE))[["elapsed"]]
            c(first = first, second = second)
          },
          args = list(shape = shape, route = route),
          libpath = .libPaths()
        )
      }

      shapes <- list(
        list(kind = "scalars", n = 5),
        list(kind = "scalars", n = 20),
        list(kind = "vector", n = 100),
        list(kind = "vector", n = 400)
      )
      has_threshold <- exists("pfor_min_elements", envir = asNamespace("greta"))
      routes <- if (has_threshold) c(NA, "pfor", "while") else NA

      grid <- expand.grid(
        shape = seq_along(shapes),
        route = routes,
        rep = seq_len(n_reps),
        stringsAsFactors = FALSE
      )

      rows <- Map(
        function(shape, route, rep) {
          times <- one_run(shapes[[shape]], route)
          data.frame(
            kind = shapes[[shape]]$kind,
            n = shapes[[shape]]$n,
            route = if (is.na(route)) "default" else route,
            rep = rep,
            first = times[["first"]],
            second = times[["second"]]
          )
        },
        grid$shape,
        grid$route,
        grid$rep
      )
      do.call(rbind, rows)
    },
    current = FALSE,
    branches = branches,
    args_callr = list(env = subprocess_env)
  )
)

results <- raw$result |>
  set_names(raw$branch) |>
  bind_rows(.id = "branch")

saveRDS(
  list(
    results = results,
    branches = list(reference = branch_reference, under_test = branch_under_test),
    shas = vapply(branches, \(b) git_sha(greta_repo, b), character(1)),
    design = list(n_reps = as.integer(n_reps)),
    provenance = host_provenance(packages = c("cross", "tensorflow", "reticulate"))
  ),
  path(run_dir, "results.rds"),
  compress = "xz"
)

cat("wrote", path(run_dir, "results.rds"), "\n")
