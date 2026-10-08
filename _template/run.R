# Runs benchmark.R against CRAN, main and a branch of greta, in a fresh R
# session per version, in six sessions:
#
#   Rscript --quiet --vanilla posts/YYYY-MM-DD-short-name-iNNN/run.R
#
# Each session writes results/session-<n>.rds, and sessions already there are
# skipped, so a rerun after a crash carries on. Each `# ---- label ----` line
# starts a section that index.qmd shows by that label. Keep the machine idle
# while it runs, and on mains power, with the lid open: a session that
# overlaps other work, or a sleep, is not a measurement.

# ---- run-versions ----
# Pin every version to a commit: branches move, and the post links each one.
# The version the post is about goes last, which is where the page's colours
# expect it.
versions <- c(
  CRAN = "greta@0.6.0",
  main = "greta-dev/greta@REPLACE-WITH-MAIN-COMMIT",
  `#NNN` = "greta-dev/greta@REPLACE-WITH-BRANCH-COMMIT"
)
# a multiple of the number of versions, so each takes each place in the order
# equally often
n_sessions <- 6
post_dir <- here::here("posts", "YYYY-MM-DD-short-name-iNNN")

# ---- run-sessions ----
dir.create(file.path(post_dir, "results"), showWarnings = FALSE)

for (session in seq_len(n_sessions)) {
  session_file <- file.path(
    post_dir,
    "results",
    sprintf("session-%d.rds", session)
  )
  if (file.exists(session_file)) {
    next
  }

  # The version that runs first in a session tends to be the slower, so the
  # order rotates: each session starts one place further along. A random order
  # can put one version first in four sessions of five, which then reads as a
  # difference between the versions.
  start <- (session - 1) %% length(versions)
  order <- names(versions)[(seq_along(versions) + start - 1) %%
    length(versions) +
    1]

  # cross::run_versions() installs each version into a library of its own and
  # evaluates the expression in a fresh R session against it. That session
  # cannot see this one's variables, so the script's path and the session
  # number reach it as environment variables: args_callr is passed on to
  # callr::r(), whose `env` sets variables for the child process (see ?callr::r
  # and ?callr::rcmd_safe_env, whose defaults are kept).
  measured <- cross::run_versions(
    source(Sys.getenv("GRETA_BENCH_SCRIPT"), local = TRUE)$value,
    pkgs = unname(versions[order]),
    args_callr = list(
      env = c(
        callr::rcmd_safe_env(),
        GRETA_BENCH_SCRIPT = file.path(post_dir, "benchmark.R"),
        GRETA_BENCH_SESSION = session
      )
    )
  )

  saveRDS(
    list(
      session = session,
      versions = versions,
      order = order,
      results = setNames(measured$result, order)
    ),
    session_file,
    compress = "xz"
  )
}
