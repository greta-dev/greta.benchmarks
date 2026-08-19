# Compare greta branches on speed and effective-samples-per-second.
#
# Runs `bench-worker.R` once per (branch, python stack) combination, each in a
# FRESH R SESSION and STRICTLY IN SERIES. Both matter:
#
#   * separate sessions -- reticulate initialises Python once per process, so a
#     session cannot switch TF stacks, and a warm TF times differently.
#   * in series -- these are wall-clock measurements. Running two R sessions
#     concurrently puts them in contention for the same cores and both numbers
#     become meaningless. Do NOT parallelise this, ever.
#
# Branches are checked out as `git worktree`s in a temp dir, so your working
# tree and its uncommitted changes are never touched.
#
# Usage:
#   Rscript bench-compare.R main keras3-optimisers
#   GRETA_QUICK=true Rscript bench-compare.R main add-snaper-hmc
#
# To also vary the Python stack, set GRETA_PYTHONS to a comma-separated list of
# `label=path/to/python` pairs; every branch is then run against every stack.

args <- commandArgs(trailingOnly = TRUE)
branches <- if (length(args)) args else c("main")

greta_repo <- Sys.getenv("GRETA_REPO", "~/github/greta-dev/greta")
greta_repo <- normalizePath(greta_repo, mustWork = TRUE)

# find the worker next to this script, however it was invoked
this_file <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
here <- if (length(this_file)) dirname(normalizePath(this_file)) else getwd()
worker <- file.path(here, "bench-worker.R")
stopifnot(file.exists(worker))

work_dir <- Sys.getenv("GRETA_BENCH_DIR", file.path(tempdir(), "greta-bench"))
dir.create(work_dir, showWarnings = FALSE, recursive = TRUE)

# python stacks: label=path, or a single empty entry meaning "greta's default"
pythons <- Sys.getenv("GRETA_PYTHONS")
if (nzchar(pythons)) {
  parts <- strsplit(strsplit(pythons, ",")[[1]], "=")
  stacks <- stats::setNames(vapply(parts, `[`, "", 2), vapply(parts, `[`, "", 1))
} else {
  stacks <- c(default = "")
}

git <- function(...) system2("git", c("-C", greta_repo, ...), stdout = TRUE, stderr = TRUE)

# --- set up one worktree per branch ---------------------------------------
worktrees <- character()
for (b in branches) {
  wt <- file.path(work_dir, paste0("wt-", gsub("[^A-Za-z0-9]+", "-", b)))
  if (!dir.exists(wt)) {
    message("creating worktree for ", b)
    res <- git("worktree", "add", "--detach", wt, b)
    if (!is.null(attr(res, "status")) && attr(res, "status") != 0) {
      stop("could not create worktree for ", b, ": ", paste(res, collapse = "\n"))
    }
  }
  worktrees[[b]] <- wt
}

# --- run every combination, in series -------------------------------------
outs <- character()
combos <- expand.grid(
  branch = branches, stack = names(stacks),
  stringsAsFactors = FALSE, KEEP.OUT.ATTRS = FALSE
)

message(sprintf(
  "\n%d combination(s), run one at a time. Do not use the machine meanwhile.\n",
  nrow(combos)
))

for (i in seq_len(nrow(combos))) {
  b <- combos$branch[i]
  s <- combos$stack[i]
  label <- if (identical(s, "default")) b else paste0(b, "@", s)
  out <- file.path(work_dir, paste0("bench-", gsub("[^A-Za-z0-9]+", "-", label), ".rds"))

  env <- c(
    paste0("GRETA_SRC=", worktrees[[b]]),
    paste0("GRETA_LABEL=", label),
    paste0("GRETA_OUT=", out),
    paste0("GRETA_REPS=", Sys.getenv("GRETA_REPS", "5")),
    paste0("GRETA_CHAINS=", Sys.getenv("GRETA_CHAINS", "4")),
    paste0("GRETA_WARMUP=", Sys.getenv("GRETA_WARMUP", "1000")),
    paste0("GRETA_QUICK=", Sys.getenv("GRETA_QUICK", ""))
  )
  if (nzchar(stacks[[s]])) {
    env <- c(env, paste0("GRETA_TEST_PYTHON=", stacks[[s]]))
  }

  message(sprintf("[%d/%d] %s", i, nrow(combos), label))
  # blocking call -- the next combination does not start until this returns
  status <- system2("Rscript", worker, env = env)
  if (status != 0) {
    warning("worker failed for ", label, " (status ", status, ")")
    next
  }
  outs <- c(outs, out)
}

# --- collect ---------------------------------------------------------------
if (!length(outs)) stop("no successful runs")

all <- do.call(rbind, lapply(outs, readRDS))
saveRDS(all, file.path(work_dir, "bench-all.rds"))

cat("\n\n================ comparison ================\n")

# Runs whose chains did not converge carry a flag from the worker. Their ESS,
# and so their efficiency, is not a measurement of anything -- surface them
# loudly and exclude them from ratios rather than quietly averaging noise in.
bad <- all[!is.na(all$note) & grepl("NOT CONVERGED", all$note), ]
if (nrow(bad)) {
  cat("\n!! Excluded from comparison -- chains did not converge (rhat >= 1.1):\n")
  for (i in seq_len(nrow(bad))) {
    if (bad$metric[i] != "ess_per_sec") next
    cat(sprintf("     %-28s %s\n", bad$task[i], bad$label[i]))
  }
  cat("   Re-run with a longer warmup / more chains. greta's sampler is not\n")
  cat("   seeded (#285/#427), so this varies between runs.\n")
}

reshape_metric <- function(df, metric) {
  sub <- df[df$metric == metric, ]
  # never compare a task where any branch failed to converge
  if (metric %in% c("ess_per_sec", "min_ess")) {
    tainted <- unique(bad$task)
    sub <- sub[!sub$task %in% tainted, ]
  }
  if (!nrow(sub)) return(invisible(NULL))
  wide <- reshape(
    sub[, c("task", "label", "value")],
    idvar = "task", timevar = "label", direction = "wide"
  )
  names(wide) <- sub("^value\\.", "", names(wide))
  cat("\n--", metric, "--\n")
  print(wide, row.names = FALSE, digits = 4)

  # ratio against the first label, which is the reference branch
  labels <- unique(sub$label)
  if (length(labels) > 1 && metric %in% c("median_time", "ess_per_sec", "elapsed")) {
    ref <- labels[1]
    for (l in labels[-1]) {
      r <- wide[[l]] / wide[[ref]]
      cat(sprintf(
        "   %s vs %s: %s\n", l, ref,
        paste(sprintf("%s=%.2fx", wide$task, r), collapse = "  ")
      ))
    }
    if (metric == "ess_per_sec") cat("   (ess_per_sec: higher is better)\n")
    if (metric %in% c("median_time", "elapsed")) cat("   (times: lower is better)\n")
  }
}

for (mm in c(
  "median_time", "ess_per_sec", "ess_per_sec_spread",
  "min_ess", "elapsed", "worst_rhat"
)) {
  reshape_metric(all, mm)
}

# the noise floor: a branch-to-branch efficiency ratio is only meaningful if it
# exceeds the run-to-run spread within a single branch
sp <- all[all$metric == "ess_per_sec_spread" & is.finite(all$value), ]
if (nrow(sp)) {
  cat(sprintf(
    "\nNoise floor: within-branch ess_per_sec varied by up to %.2fx across\nreplicates. Treat any branch-to-branch ratio below that as noise.\n",
    max(sp$value)
  ))
}

cat("\nraw results: ", file.path(work_dir, "bench-all.rds"), "\n")
cat("worktrees left in place for re-runs; remove with:\n")
cat("  git -C", greta_repo, "worktree remove <path>\n")
