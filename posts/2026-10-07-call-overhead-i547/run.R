# Runs benchmark.R against CRAN and two commits of the tf-sampler-i547 branch
# of greta, in a fresh R session per version, in five sessions:
#
#   Rscript --quiet --vanilla posts/2026-10-07-call-overhead-i547/run.R
#
# Each session writes results/session-<n>.rds, and sessions already there are
# skipped, so a rerun after a crash carries on. Each `# ---- label ----` line
# starts a section that index.qmd shows by that label.

# ---- run-versions ----
# Pin every version to a commit: they move, and the post links each one.
# earlier is tf-sampler-i547 at 11405935, greta's sampler and opt() loops in
# TensorFlow. branch is its head at f30ab146, which also keeps opt()'s traced
# loop on the model, and the chain's state as tensors between the calls of a
# phase. Neither was on GitHub when this ran, so pak installed each from an
# archive of the commit, and the saved results record those local paths
versions <- c(
  CRAN = "greta@0.6.0",
  earlier = "greta-dev/greta@11405935549722ecbf035a2712a007419e52af66",
  branch = "greta-dev/greta@f30ab1469ef9eafab8bb2ff48be10860cd3fd9ab"
)
n_sessions <- 5
post_dir <- here::here("posts", "2026-10-07-call-overhead-i547")

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
