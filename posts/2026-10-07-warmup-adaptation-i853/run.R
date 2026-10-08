# Runs benchmark.R against the tf-warmup-i547 branch of greta, in a fresh R
# session, in five sessions:
#
#   Rscript --quiet --vanilla posts/2026-10-07-warmup-adaptation-i853/run.R
#
# Each session writes results/session-<n>.rds, and sessions already there are
# skipped, so a rerun after a crash carries on. Each `# ---- label ----` line
# starts a section that index.qmd shows by that label.

# ---- run-versions ----
# The warmup schemes are an internal choice on the tf-warmup-i547 branch at
# this commit, added in its ancestor 59da5cc9, so it is the only version.
# Sessions 1 to 3 ran before the branch was on GitHub, so pak installed this
# commit from its worktree, clean at the commit, and their saved results record
# that local path; sessions 4 and 5 installed it from GitHub
versions <- c(
  branch = "greta-dev/greta@92f34e3003c5db24f67534d4c9abe3255ee39ccf"
)
n_sessions <- 5
post_dir <- here::here("posts", "2026-10-07-warmup-adaptation-i853")

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

  # cross::run_versions() installs the version into a library of its own and
  # evaluates the expression in a fresh R session against it. That session
  # cannot see this one's variables, so the script's path and the session
  # number reach it as environment variables: args_callr is passed on to
  # callr::r(), whose `env` sets variables for the child process (see ?callr::r
  # and ?callr::rcmd_safe_env, whose defaults are kept).
  measured <- cross::run_versions(
    source(Sys.getenv("GRETA_BENCH_SCRIPT"), local = TRUE)$value,
    pkgs = unname(versions),
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
      results = setNames(measured$result, names(versions))
    ),
    session_file,
    compress = "xz"
  )
}
