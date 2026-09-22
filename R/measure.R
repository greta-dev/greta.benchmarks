# {cross} evaluates its expression in a callr subprocess that cannot see this
# session. Values cross that boundary inlined with bquote() - `.(x)` becomes a
# literal - rather than via Sys.getenv(), so types survive and the pipeline's
# parameters stay in targets. bquote() is needed rather than a plain variable
# because cross calls substitute() on `expr`.
#
# Both tiers run inside ONE cross call. run_branches() takes no shortcuts: per
# branch it does a gert worktree checkout of greta and a pak install into a
# temporary library that is discarded when the call returns, with no caching
# between calls. Two calls meant installing every branch twice per run.
#
# The cost is coupled invalidation - changing bench_iterations re-runs the
# sampling tier too - which is why the returned list is unpacked into separate
# targets rather than consumed whole.

#' Measure both tiers on every branch, in one pass per branch.
#'
#' `current = FALSE` matters: cross defaults to TRUE, which silently prepends
#' whatever branch is checked out and mislabels it.
measure_branches <- function(
  branches,
  examples_file,
  target_file,
  greta_repo,
  bench_iterations,
  target_ess,
  reps,
  time_limit,
  example_names
) {
  body <- bquote({
    library(greta)
    library(bench)
    source(.(examples_file))
    source(.(target_file))

    examples <- bench_examples()[.(example_names)]

    # construct and trace once outside the timing: model() is itself a task
    # below, and first-use tracing is a different question from steady state
    built <- lapply(examples, function(f) f())
    for (m in built) {
      invisible(opt(m, optimiser = adam(), max_iterations = 5))
    }

    timings <- bench::press(
      example = names(built),
      {
        m <- built[[example]]
        bench::mark(
          model = examples[[example]](),
          opt = opt(m, optimiser = adam(), max_iterations = 100),
          # mcmc() is not here: bench::mark() wants every iteration to be the
          # same work, and sampling is not.
          check = FALSE,
          filter_gc = FALSE,
          # mem_alloc comes from Rprofmem, which sees the R heap only - greta's
          # memory is in the TensorFlow graph, where it cannot look. Measured
          # 2026-09-22: it ranks `linear` and `cjs` in the opposite order to
          # process RSS. Peak RSS is collected per run below instead.
          memory = FALSE,
          min_iterations = .(bench_iterations),
          max_iterations = .(bench_iterations) * 2L
        )
      }
    )

    grid <- expand.grid(
      example = names(examples),
      rep = seq_len(.(reps)),
      stringsAsFactors = FALSE
    )

    sampling <- do.call(
      rbind,
      Map(
        function(example, rep) {
          row <- sample_to_target(
            examples[[example]](),
            target_ess = .(target_ess),
            time_limit = .(time_limit)
          )
          cbind(example = example, rep = rep, row)
        },
        grid$example,
        grid$rep
      )
    )

    list(timings = timings, sampling = sampling, rss_mb = rss_mb())
  })

  call <- bquote(
    cross::run_branches(
      .(body),
      current = FALSE,
      branches = .(branches),
      args_callr = list(env = callr::rcmd_safe_env())
    )
  )

  with_dir(greta_repo, eval(call))
}

#' The deterministic tier, recombined across branches.
#'
#' bench_branches() is run_branches() plus this recombination; doing it here is
#' what lets one cross call serve both tiers. as_bench_mark() restores the
#' class so summary(relative = TRUE) and autoplot() keep working.
branch_timings <- function(measured) {
  parts <- lapply(measured$result, function(x) x$timings)
  out <- bind_rows(setNames(parts, measured$branch), .id = "branch")
  out <- bench::as_bench_mark(out)
  out$task <- as.character(out$expression)
  out$engine <- c(model = NA_character_, opt = "adam")[out$task]
  out
}

#' The sampling tier, recombined across branches.
branch_sampling <- function(measured) {
  parts <- lapply(measured$result, function(x) x$sampling)
  out <- bind_rows(setNames(parts, measured$branch), .id = "branch")
  out$task <- "mcmc"
  out$engine <- "hmc"
  out
}

#' End-of-run resident set size per branch, in MB. See rss_mb().
branch_rss <- function(measured) {
  data.frame(
    branch = measured$branch,
    rss_mb = vapply(measured$result, function(x) x$rss_mb, numeric(1))
  )
}

#' The SHAs actually measured. Captured here rather than at render time because
#' branches move, and a moved branch would record a commit never measured.
branch_shas <- function(branches, greta_repo) {
  data.frame(
    branch = branches,
    sha = vapply(branches, function(b) git_sha(greta_repo, b), character(1)),
    row.names = NULL
  )
}
