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
  bench_iterations,
  mcmc_iterations,
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
          opt = opt(m, optimiser = adam(), max_iterations = .(opt_iterations)),
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

    # the same iterations on every branch, which is deterministic work and so
    # measures what one run costs. The sampling tier
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
            n_samples = sample_draws,
            warmup = warmup_draws,
            chains = .(mcmc_chains),
            n_cores = .(as.integer(mcmc_cores)),
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
            warmup = warmup_draws,
            initial_samples = sample_draws,
            time_limit = .(time_limit)
          )
          row$mcmc_iterations <- row$mcmc_samples * iterations_per_kept_draw
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
    })

    list(
      timings = timings,
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
      branches = .(branches),
      args_callr = list(env = callr::rcmd_safe_env())
    )
  )

  measured <- with_dir(greta_repo, eval(call))
  stop_if_moved(shas, greta_repo)
  measured$branch <- shas$label[match(measured$branch, shas$branch)]
  measured
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

#' The deterministic tier, recombined across branches.
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
  out$engine <- c(model = NA_character_, opt = "adam", mcmc = "hmc")[out$task]
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

#' One seeded fit per example, per branch: draws, fitted values, and the data.
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
