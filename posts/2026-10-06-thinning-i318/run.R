# Runs benchmark.R against CRAN, main and greta#850, in a fresh R session per
# version, in five sessions:
#
#   Rscript --quiet --vanilla posts/2026-10-06-thinning-i318/run.R
#
# Each session writes results/session-<n>.rds, and sessions already there are
# skipped, so a rerun after a crash carries on. Each `# ---- label ----` line
# starts a section that index.qmd shows by that label.

# ---- run-versions ----
# pin main and the branch to commits: both move, and the post links each one
versions <- c(
  CRAN = "greta@0.6.0",
  main = "greta-dev/greta@0a22f8c7e63ac32fa0926cdf67a85c9f69acd1d5",
  `#850` = "greta-dev/greta@5a02f6c5ff5497363ac4bf419368bb3c5925d5cb"
)
n_sessions <- 5
post_dir <- here::here("posts", "2026-10-06-thinning-i318")

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

  # a fresh order each session, so no version is always measured first or last
  order <- sample(names(versions))

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
