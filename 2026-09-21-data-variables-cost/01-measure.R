# What do tf$Variable-backed data nodes cost?
#
#   Rscript --quiet --vanilla 2026-09-21-data-variables-cost/01-measure.R \
#     <greta-checkout> <label>
#
# greta-dev/greta#739 gives every data node a persistent tf$Variable instead of
# baking its value into each trace. That buys swapping data without a retrace,
# and the Geweke checks drop from ~30 minutes to ~45 seconds. The question here
# is what it costs everyone who never swaps anything:
#
#   * memory. The value now lives in a variable for the life of the dag, where
#     before it existed only inside a trace. Models carrying real data are
#     where that would show, so this runs the whole suite model set rather than
#     a toy.
#   * time. Reading a variable is not free the way folding in a constant is,
#     and the optimiser now walks a graph containing variables it must ignore.
#
# Run once per checkout rather than through {cross}, because the change under
# test is uncommitted and cross installs from git.
#
# RSS, not bench::mark's mem_alloc: the allocation in question is TensorFlow's,
# on the Python side, which R's allocator never sees. RSS is noisy and includes
# whatever TF's allocator feels like holding, so read it for a step change
# rather than for a few percent.

library(here)
library(fs)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) {
  stop("usage: 01-measure.R <greta-checkout> <label>", call. = FALSE)
}
greta_checkout <- normalizePath(args[[1]], mustWork = TRUE)
label <- args[[2]]

run_dir <- here("2026-09-21-data-variables-cost")
models_file <- path(here("suite"), "models.R")

n_reps <- as.integer(Sys.getenv("GRETA_COST_REPS", "3"))
n_samples <- as.integer(Sys.getenv("GRETA_COST_SAMPLES", "200"))
warmup <- as.integer(Sys.getenv("GRETA_COST_WARMUP", "200"))
chains <- 2L

suppressMessages(pkgload::load_all(greta_checkout, quiet = TRUE))
source(models_file)

# resident set size of this process, in MB
rss_mb <- function() {
  kb <- system2("ps", c("-o", "rss=", "-p", Sys.getpid()), stdout = TRUE)
  as.numeric(trimws(kb)) / 1024
}

one_run <- function(model_name, rep) {
  builder <- greta_bench_models[[model_name]]

  gc(verbose = FALSE, full = TRUE)
  rss_start <- rss_mb()

  # dag construction is where the variables are created, so it is timed apart
  # from sampling rather than folded into it
  t_build <- system.time(m <- builder())[["elapsed"]]
  rss_built <- rss_mb()

  t_mcmc <- system.time(
    invisible(mcmc(
      m,
      n_samples = n_samples,
      warmup = warmup,
      chains = chains,
      verbose = FALSE
    ))
  )[["elapsed"]]
  rss_sampled <- rss_mb()

  data.frame(
    label = label,
    model = model_name,
    rep = rep,
    build_secs = t_build,
    mcmc_secs = t_mcmc,
    rss_start_mb = rss_start,
    rss_after_build_mb = rss_built,
    rss_after_mcmc_mb = rss_sampled,
    build_delta_mb = rss_built - rss_start,
    mcmc_delta_mb = rss_sampled - rss_built
  )
}

grid <- expand.grid(
  model_name = names(greta_bench_models),
  rep = seq_len(n_reps),
  stringsAsFactors = FALSE
)

results <- do.call(
  rbind,
  Map(one_run, grid$model_name, grid$rep)
)

out_rds <- path(run_dir, paste0("results-", label, ".rds"))
saveRDS(
  list(
    results = results,
    label = label,
    n_reps = n_reps,
    n_samples = n_samples,
    warmup = warmup,
    chains = chains,
    sha = system2(
      "git",
      c("-C", shQuote(greta_checkout), "rev-parse", "HEAD"),
      stdout = TRUE
    )
  ),
  out_rds,
  compress = "xz"
)

cat("\n==== ", label, " ====\n")
agg <- aggregate(
  cbind(build_secs, mcmc_secs, build_delta_mb, mcmc_delta_mb) ~ model,
  data = results,
  FUN = median
)
print(agg, row.names = FALSE, digits = 3)
cat("\nwrote", out_rds, "\n")
