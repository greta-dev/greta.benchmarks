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
# The cost is coupled invalidation - changing bench_repeats re-runs the
# sampling tier too - which is why the returned list is unpacked into separate
# targets rather than consumed whole.

#' Measure both tiers on every branch, in one pass per branch.
#'
#' `shas` is branch_shas()'s table of branches and their commits, so the
#' measurement depends on the commits, not only the names: a branch that moves
#' is measured again. A branch that moves while it is being measured would be
#' measured at a commit the results do not record, so that is an error.
#'
#' `current = FALSE` matters: cross defaults to TRUE, which silently prepends
#' whatever branch is checked out and mislabels it.
measure_branches <- function(
  shas,
  examples_file,
  target_file,
  iterations_file,
  greta_repo,
  bench_repeats,
  mcmc_repeats,
  warmup_iterations,
  sample_iterations,
  mcmc_chains,
  mcmc_cores,
  opt_iterations,
  target_ess,
  reps,
  time_limit,
  example_names
) {
  branches <- shas$branch
  stop_if_moved(shas, greta_repo)

  # cross installs every branch, then measures them one after another, so
  # anything that drifts over a run (heat, other load) falls on the branches
  # measured last. The order changes from run to run so that is not always the
  # same branch. targets fixes each target's random seed, so the order is drawn
  # from the clock
  run_order <- withr::with_seed(as.integer(Sys.time()), sample(branches))

  body <- bquote({
    library(greta)
    library(bench)
    source(.(examples_file))
    source(.(target_file))
    source(.(iterations_file))

    examples <- bench_examples()[.(example_names)]

    # mcmc() takes draws, not iterations, and versions differ in how many
    # iterations a draw costs, so every call below asks for the draws that
    # make the same number of iterations on every version
    iterations_per_kept_draw <- iterations_per_draw()
    warmup_draws <- as.integer(.(warmup_iterations) / iterations_per_kept_draw)
    sample_draws <- as.integer(.(sample_iterations) / iterations_per_kept_draw)

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
        chains = .(mcmc_chains),
        n_cores = .(as.integer(mcmc_cores)),
        verbose = FALSE
      ))
    }

    # building a model and opt() take tens of milliseconds, so bench::mark()
    # repeats them; the `model` task runs the example's whole code, ending in
    # its call to model()
    fast <- bench::press(
      example = names(built),
      {
        m <- built[[example]]
        bench::mark(
          model = examples[[example]](),
          opt = opt(m, optimiser = adam(), max_iterations = .(opt_iterations)),
          check = FALSE,
          filter_gc = FALSE,
          # mem_alloc comes from Rprofmem, which sees the R heap only - greta's
          # memory is in the TensorFlow graph, where it cannot look. RSS is
          # collected per run below instead.
          memory = FALSE,
          min_iterations = .(bench_repeats),
          max_iterations = .(bench_repeats) * 2L
        )
      }
    )
    timings <- bench::as_bench_mark(fast)

    # the same iterations on every branch, so each run is the same work and
    # its time is what one run costs. Timed by hand rather than by
    # bench::mark(), which discards what it times, so each run's draws give
    # their ESS too: efficiency at a fixed number of iterations
    run_mcmc_once <- function(example, run) {
      start <- bench::hires_time()
      draws <- mcmc(
        built[[example]],
        n_samples = sample_draws,
        warmup = warmup_draws,
        chains = .(mcmc_chains),
        n_cores = .(as.integer(mcmc_cores)),
        verbose = FALSE
      )
      seconds <- bench::hires_time() - start
      summ <- posterior_summary(draws)
      data.frame(
        example = example,
        run = run,
        seconds = seconds,
        ess_bulk_min = min(summ$ess_bulk),
        ess_bulk_median = stats::median(summ$ess_bulk),
        rhat_max = max(summ$rhat)
      )
    }
    mcmc_grid <- expand.grid(
      run = seq_len(.(mcmc_repeats)),
      example = names(built),
      stringsAsFactors = FALSE
    )
    mcmc_runs <- do.call(
      rbind,
      Map(run_mcmc_once, mcmc_grid$example, mcmc_grid$run)
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
            chains = .(mcmc_chains),
            warmup = warmup_draws,
            initial_samples = sample_draws,
            time_limit = .(time_limit),
            n_cores = .(as.integer(mcmc_cores))
          )
          row$mcmc_iterations <- row$mcmc_samples * iterations_per_kept_draw
          cbind(example = example, rep = rep, row)
        },
        grid$example,
        grid$rep
      )
    )

    # `reps` seeded fits per example, seeds 1 to reps, kept whole for the
    # report's convergence diagnostics and plots of draws and fitted values.
    # Run last, so they cannot disturb any timing above
    fit_once <- function(example_fn, seed) {
      m <- example_fn()
      fit <- attr(m, "fit")
      set.seed(seed)
      draws <- mcmc(
        m,
        n_samples = sample_draws,
        warmup = warmup_draws,
        chains = .(mcmc_chains),
        n_cores = .(as.integer(mcmc_cores)),
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
    }
    fits <- lapply(examples, function(example_fn) {
      lapply(seq_len(.(reps)), function(seed) fit_once(example_fn, seed))
    })

    list(
      timings = timings,
      mcmc_runs = mcmc_runs,
      sampling = sampling,
      rss_mb = rss_mb(),
      fits = fits,
      iterations_per_draw = iterations_per_kept_draw
    )
  })

  call <- bquote(
    cross::run_branches(
      .(body),
      current = FALSE,
      branches = .(run_order),
      args_callr = list(env = callr::rcmd_safe_env())
    )
  )

  measured <- with_dir(greta_repo, eval(call))
  stop_if_moved(shas, greta_repo)
  measured$measured_order <- seq_len(nrow(measured))
  # back in the order the pipeline lists the branches, which the report keeps
  measured <- measured[match(branches, measured$branch), ]
  measured$branch <- shas$label[match(measured$branch, shas$branch)]
  measured
}

#' The order each branch was measured in, in this run: 1 is first.
branch_run_order <- function(measured) {
  data.frame(
    branch = factor(measured$branch, levels = measured$branch),
    measured_order = measured$measured_order
  )
}

# checked before and after measuring, so the commits recorded in `shas` are
# the ones that were installed
stop_if_moved <- function(shas, greta_repo) {
  now <- branch_shas(shas$branch, greta_repo)
  moved <- now$sha != shas$sha
  if (any(moved)) {
    stop(
      paste(shas$branch[moved], collapse = ", "),
      " moved to a new commit while being measured; run tar_make() again",
      call. = FALSE
    )
  }
}

#' The model() and opt() timings, recombined across branches.
#'
#' bench_branches() is run_branches() plus this recombination; doing it here is
#' what lets one cross call serve both tiers. as_bench_mark() restores the
#' class so summary(relative = TRUE) and autoplot() keep working.
branch_timings <- function(measured) {
  parts <- lapply(measured$result, function(x) x$timings)
  out <- bind_rows(setNames(parts, measured$branch), .id = "branch")
  out$branch <- factor(out$branch, levels = measured$branch)
  out <- bench::as_bench_mark(out)
  out$task <- as.character(out$expression)
  out$engine <- c(model = NA_character_, opt = "adam")[out$task]
  out
}

#' Every fixed-length mcmc() run, with its time and its ESS, across branches.
branch_mcmc_runs <- function(measured) {
  parts <- lapply(measured$result, function(x) x$mcmc_runs)
  out <- bind_rows(setNames(parts, measured$branch), .id = "branch")
  out$branch <- factor(out$branch, levels = measured$branch)
  out
}

#' The sampling tier, recombined across branches.
branch_sampling <- function(measured) {
  parts <- lapply(measured$result, function(x) x$sampling)
  out <- bind_rows(setNames(parts, measured$branch), .id = "branch")
  out$branch <- factor(out$branch, levels = measured$branch)
  out$task <- "mcmc_to_target"
  out$engine <- "hmc"
  out
}

#' The seeded fits, per branch and example, one per seed: draws, fitted values,
#' and the data.
branch_fits <- function(measured) {
  setNames(lapply(measured$result, function(x) x$fits), measured$branch)
}

#' End-of-run resident set size per branch, in MB. See rss_mb().
branch_rss <- function(measured) {
  data.frame(
    branch = factor(measured$branch, levels = measured$branch),
    rss_mb = vapply(measured$result, function(x) x$rss_mb, numeric(1))
  )
}

#' How many iterations each branch ran per kept draw. See iterations_per_draw().
branch_iterations <- function(measured) {
  data.frame(
    branch = factor(measured$branch, levels = measured$branch),
    iterations_per_draw = vapply(
      measured$result,
      function(x) x$iterations_per_draw,
      numeric(1)
    )
  )
}

#' The SHAs actually measured. Captured here rather than at render time because
#' branches move, and a moved branch would record a commit never measured.
#'
#' `label` is the name the report uses for each git ref, such as "CRAN" for
#' v0.6.0; unnamed refs are their own label.
branch_shas <- function(branches, greta_repo) {
  data.frame(
    label = names(branches) %||% branches,
    branch = unname(branches),
    sha = vapply(branches, function(b) git_sha(greta_repo, b), character(1)),
    row.names = NULL
  )
}
