# Runs benchmark-one-call.R against the two commits of the tf-sampler-i547
# branch that run.R compares, in a fresh R session per version, in six
# sessions:
#
#   Rscript --quiet --vanilla posts/2026-10-07-call-overhead-i547/run-one-call.R
#
# Each session writes results-one-call/session-<n>.rds, and sessions already
# there are skipped, so a rerun after a crash carries on. Each
# `# ---- label ----` line starts a section that index.qmd shows by that label.

# ---- one-call-versions ----
# The same two commits as run.R, which pak likewise installed from archives of
# the commits, so the saved results record local paths
versions <- c(
  earlier = "greta-dev/greta@11405935549722ecbf035a2712a007419e52af66",
  branch = "greta-dev/greta@f30ab1469ef9eafab8bb2ff48be10860cd3fd9ab"
)
n_sessions <- 6
post_dir <- here::here("posts", "2026-10-07-call-overhead-i547")

# ---- one-call-sessions ----
dir.create(file.path(post_dir, "results-one-call"), showWarnings = FALSE)

for (session in seq_len(n_sessions)) {
  session_file <- file.path(
    post_dir,
    "results-one-call",
    sprintf("session-%d.rds", session)
  )
  if (file.exists(session_file)) {
    next
  }

  # each version goes first in every other session, so neither is always
  # measured first: in run.R's random order, branch went first in four of
  # its five sessions
  order <- if (session %% 2 == 1) names(versions) else rev(names(versions))

  # as in run.R, the script's path and the session number reach the fresh
  # session through callr::r()'s `env`
  measured <- cross::run_versions(
    source(Sys.getenv("GRETA_BENCH_SCRIPT"), local = TRUE)$value,
    pkgs = unname(versions[order]),
    args_callr = list(
      env = c(
        callr::rcmd_safe_env(),
        GRETA_BENCH_SCRIPT = file.path(post_dir, "benchmark-one-call.R"),
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
