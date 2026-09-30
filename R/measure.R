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
  mcmc_iterations,
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
    # below, and first-use tracing is a different question from steady state.
    # The mcmc warm-up must use the same chain count as the timed call - the
    # sampler's trace is keyed on batch shape, so a different count retraces.
    built <- lapply(examples, function(f) f())
    for (m in built) {
      invisible(opt(m, optimiser = adam(), max_iterations = 5))
      invisible(mcmc(
        m,
        n_samples = 10,
        warmup = 10,
        chains = 4,
        n_cores = 4L,
        verbose = FALSE
      ))
    }

    # model() and opt() run in tens of milliseconds; a realistic mcmc() run
    # takes seconds. One bench::mark() applies a single iteration count to all
    # of them, so they are measured separately and recombined - otherwise the
    # count that suits the cheap tasks makes the tier unaffordable.
    fast <- bench::press(
      example = names(built),
      {
        m <- built[[example]]
        bench::mark(
          model = examples[[example]](),
          opt = opt(m, optimiser = adam(), max_iterations = 100),
          check = FALSE,
          filter_gc = FALSE,
          # mem_alloc comes from Rprofmem, which sees the R heap only - greta's
          # memory is in the TensorFlow graph, where it cannot look. RSS is
          # collected per run below instead.
          memory = FALSE,
          min_iterations = .(bench_iterations),
          max_iterations = .(bench_iterations) * 2L
        )
      }
    )

    # a FIXED number of iterations at greta's default shape, which is
    # deterministic work and so measures what one run costs. The sampling tier
    # below answers the different question of what reaching a quality target
    # costs, and cannot separate per-iteration cost from how well the chain
    # happened to mix.
    slow <- bench::press(
      example = names(built),
      {
        m <- built[[example]]
        bench::mark(
          mcmc = mcmc(
            m,
            n_samples = 1000,
            warmup = 1000,
            chains = 4,
            n_cores = 4L,
            verbose = FALSE
          ),
          check = FALSE,
          filter_gc = FALSE,
          memory = FALSE,
          min_iterations = .(mcmc_iterations),
          max_iterations = .(mcmc_iterations) * 2L
        )
      }
    )

    timings <- bench::as_bench_mark(rbind(fast, slow))

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

    # one seeded fit per example, kept whole for the report's plots of draws
    # and fitted values. Run last, so it cannot disturb any timing above
    fits <- lapply(examples, function(example_fn) {
      m <- example_fn()
      fit <- attr(m, "fit")
      set.seed(2026 - 09 - 30)
      draws <- mcmc(
        m,
        n_samples = 1000,
        warmup = 1000,
        chains = 4,
        verbose = FALSE
      )
      fitted_draws <- as.matrix(calculate(fit$fitted, values = draws))
      # 400 draws of each fitted value is plenty for ribbons and intervals
      kept <- round(seq(1, nrow(fitted_draws), length.out = 400))
      list(
        draws = posterior::as_draws_df(draws),
        fitted = data.frame(
          .draw = rep(kept, times = ncol(fitted_draws)),
          .row = rep(seq_len(ncol(fitted_draws)), each = length(kept)),
          value = as.vector(fitted_draws[kept, , drop = FALSE])
        ),
        observed = fit$observed,
        x = fit$x,
        group = fit$group,
        x_label = fit$x_label,
        style = fit$style
      )
    })

    list(
      timings = timings,
      sampling = sampling,
      rss_mb = rss_mb(),
      fits = fits
    )
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
  out$engine <- c(model = NA_character_, opt = "adam", mcmc = "hmc")[out$task]
  out
}

#' The sampling tier, recombined across branches.
branch_sampling <- function(measured) {
  parts <- lapply(measured$result, function(x) x$sampling)
  out <- bind_rows(setNames(parts, measured$branch), .id = "branch")
  out$task <- "mcmc_to_target"
  out$engine <- "hmc"
  out
}

#' One seeded fit per example, per branch: draws, fitted values, and the data.
branch_fits <- function(measured) {
  setNames(lapply(measured$result, function(x) x$fits), measured$branch)
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
