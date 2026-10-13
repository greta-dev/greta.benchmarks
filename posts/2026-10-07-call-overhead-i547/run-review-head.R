# Runs benchmark.R, unchanged, against #855 as the main run measured it
# (f30ab146) and as it stands after the PR's review (88e44dff), in a fresh R
# session per version, in four sessions:
#
#   Rscript --quiet --vanilla posts/2026-10-07-call-overhead-i547/run-review-head.R
#
# Each session writes results-review-head/session-<n>.rds, and sessions already
# there are skipped, so a rerun after a crash carries on. Each
# `# ---- label ----` line starts a section that index.qmd shows by that label.

# ---- review-versions ----
# measured is the commit the main run measured; reviewed is the PR's head after
# its review, which stores each optimiser's method as a closure and keeps the
# traced functions under rlang::hash() of their settings
versions <- c(
  measured = "greta-dev/greta@f30ab1469ef9eafab8bb2ff48be10860cd3fd9ab",
  reviewed = "greta-dev/greta@88e44dff569f01f4dcaea1bb9b3bb4aceccc33f8"
)
n_sessions <- 4
post_dir <- here::here("posts", "2026-10-07-call-overhead-i547")

# ---- review-sessions ----
dir.create(file.path(post_dir, "results-review-head"), showWarnings = FALSE)

for (session in seq_len(n_sessions)) {
  session_file <- file.path(
    post_dir,
    "results-review-head",
    sprintf("session-%d.rds", session)
  )
  if (file.exists(session_file)) {
    next
  }

  # the order rotates, so each version runs first in every other session
  start <- (session - 1) %% length(versions)
  order <- names(versions)[
    (seq_along(versions) + start - 1) %%
      length(versions) +
      1
  ]

  # cross::run_versions() installs each version into a library of its own and
  # runs the expression in a fresh R session against it; the script's path
  # and the session number reach that session as environment variables
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
