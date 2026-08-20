# What does the discarded warmup trace cost?
#
# greta's warmup loop calls self$trace() once per burst. With values = FALSE
# (the default, and what warmup uses) that appends the burst's free state onto
# traced_free_state by rbind. The accumulated result is then discarded wholesale
# the moment warmup ends, at the "scrub the free state trace" line in
# R/sampler_class.R. Nothing reads it in between.
#
# rbind copies the whole accumulated matrix each time, so the cost should grow
# with the square of the burst count and linearly in the number of free
# parameters - which is exactly the regime the existing benchmark suite cannot
# see, every model in it being 4 free parameters or fewer.
#
# Two measurements, because they answer different halves:
#
#   part 1  on one branch, how does runtime scale with warmup length and with
#           n_free? This needs no second branch and runs today.
#   part 2  what does removing the call actually buy? This is a deletion inside
#           the package, so it needs a branch and {cross}.
#
# Wall time, not ESS/sec, on purpose: the change deletes work whose result is
# thrown away, so the sampler behaves identically and the draws are unchanged.
# ESS is a stochastic estimate and would only add variance here. (It is also
# unavailable as a clean comparison anyway - mcmc() does not respect set.seed(),
# greta #285/#427.)

library(cross)
library(bench)
library(here)
library(withr)
library(fs)
library(dplyr)
library(tidyr)
library(purrr)

run_dir <- here("2026-08-20-warmup-trace")
source(here("provenance.R"))

greta_repo <- path_expand(Sys.getenv("GRETA_REPO", "~/github/greta-dev/greta"))

# the branch carrying the deletion. Part 2 is skipped if it does not exist,
# rather than failing the whole run, so part 1 still produces a record.
branch_fix <- Sys.getenv("GRETA_FIX_BRANCH", "drop-warmup-trace")
branch_reference <- "main"

results_rds <- path(run_dir, "results.rds")

# ---- part 1: scaling on the current checkout ---------------------------------

scaling <- local({
  library(greta)

  measure <- function(n_free, warmup, n_samples = 100, chains = 2) {
    x <- normal(0, 1, dim = n_free)
    m <- model(x)
    # one short run first: TensorFlow traces on the first call, and that
    # one-off cost is a different question from steady-state speed
    invisible(mcmc(
      m,
      n_samples = 20,
      warmup = 20,
      chains = chains,
      verbose = FALSE
    ))
    system.time(
      mcmc(
        m,
        n_samples = n_samples,
        warmup = warmup,
        chains = chains,
        verbose = FALSE
      )
    )[["elapsed"]]
  }

  expand_grid(
    n_free = c(1, 20, 200),
    warmup = c(500, 1000, 2000, 4000)
  ) |>
    mutate(elapsed = map2_dbl(n_free, warmup, measure))
})

# ---- part 1b: the accumulation on its own ------------------------------------

# greta out of the picture, so the growth pattern is attributable to rbind
# rather than to anything in the sampler. burst = 3 because warmup breaks a
# burst roughly every 3 iterations once tuning changepoints are included, so
# 167 / 334 / 667 bursts stand in for warmups of 500 / 1000 / 2000.
#
# labelled so results.qmd can show this source via knitr::read_chunk() rather
# than keeping a second copy of it
## ---- accumulate ----
accumulate <- function(n_bursts, n_free, burst = 3) {
  acc <- matrix(nrow = 0, ncol = n_free)
  for (i in seq_len(n_bursts)) {
    acc <- rbind(acc, matrix(0, nrow = burst, ncol = n_free))
  }
  nrow(acc)
}
## ---- end-accumulate ----

accumulation <- bench::press(
  n_bursts = c(167, 334, 667),
  bench::mark(accumulate(n_bursts, n_free = 200), check = FALSE)
)

# ---- part 2: branch comparison -----------------------------------------------

branch_exists <- local({
  refs <- with_dir(greta_repo, system2("git", c("branch", "--list", branch_fix), stdout = TRUE))
  length(refs) > 0 && nzchar(refs[1])
})

comparison <- if (!branch_exists) {
  message(
    "branch '", branch_fix, "' not found in ", greta_repo,
    " - skipping part 2. Create it with the self$trace() call removed from ",
    "the warmup loop in R/sampler_class.R, then re-run this script."
  )
  NULL
} else {
  # cross operates on the git repo in the working directory, so the run has to
  # happen inside the greta checkout. with_dir() restores the old directory on
  # the way out, including if bench_branches() errors.
  with_dir(
    greta_repo,
    bench_branches(
      {
        library(greta)
        x <- normal(0, 1, dim = 200)
        m <- model(x)
        invisible(mcmc(m, n_samples = 20, warmup = 20, chains = 2, verbose = FALSE))
        mcmc(m, n_samples = 100, warmup = 4000, chains = 2, verbose = FALSE)
      },
      # the branches draw different numbers - mcmc() does not respect
      # set.seed() - so results cannot be compared for equality
      check = FALSE,
      filter_gc = FALSE,
      min_iterations = 5,
      max_iterations = 10,
      branches = c(branch_reference, branch_fix)
    )
  )
}

saveRDS(
  list(
    scaling = scaling,
    accumulation = accumulation,
    comparison = comparison,
    provenance = host_provenance()
  ),
  results_rds,
  compress = "xz"
)

# 02-report.R renders these into results.md. Run it after this: the ordering is
# what keeps the numbers and the prose describing them together.
