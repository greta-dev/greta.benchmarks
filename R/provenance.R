# Environment capture for a benchmark run.
#
# This is shared while each run's run.R is not, and the distinction is
# deliberate: what these functions return is written into a run's results.md at
# the moment it runs, so editing this file never changes what a past run
# recorded. Analysis code does not have that property, which is why it stays
# frozen inside its run directory.
#
# sessioninfo does the generic work - R version, OS, architecture, package
# versions and where each package came from. What is left here is the part it
# cannot reach, and which a benchmark cannot do without:
#
#   * the CPU model. sessioninfo reports "aarch64", not "Apple M3", and the
#     difference is most of the timing.
#   * the core count, which drives anything parallel.
#   * git SHAs. Branch names are not the record: main moves.
#
# The resolved Python stack per branch is the fourth such thing, but it is
# measured inside the run rather than here, and passed to write_results_md() as
# `extra`.

cpu_model <- function() {
  model <- switch(
    Sys.info()[["sysname"]],
    Darwin = try(
      system2("sysctl", c("-n", "machdep.cpu.brand_string"), stdout = TRUE),
      silent = TRUE
    ),
    Linux = try(
      sub(
        "^model name\\s*:\\s*",
        "",
        grep("^model name", readLines("/proc/cpuinfo"), value = TRUE)[1]
      ),
      silent = TRUE
    ),
    NA_character_
  )
  if (inherits(model, "try-error") || length(model) == 0) {
    return(NA_character_)
  }
  model[1]
}

git_sha <- function(repo, rev) {
  # expand here rather than trusting the caller: shQuote() puts the path in
  # single quotes, where the shell will not expand a leading ~, and the failure
  # is silent - the SHA column just reads NA
  repo <- normalizePath(path.expand(repo), mustWork = FALSE)
  sha <- try(
    system2(
      "git",
      c("-C", shQuote(repo), "rev-parse", rev),
      stdout = TRUE,
      stderr = FALSE
    ),
    silent = TRUE
  )
  if (inherits(sha, "try-error") || length(sha) == 0) {
    return(NA_character_)
  }
  sha[1]
}

# Numbers from a benchmark are bound to the machine that produced them, so the
# hardware is recorded as data rather than as something a reader could
# reproduce. Comparisons are only meaningful within a single run.
#
# greta is deliberately absent from the default packages: a branch comparison
# installs its own greta per branch, so the version in this session is not the
# one that was measured. The commit SHAs and the per-branch stacks are what
# describe that.
host_provenance <- function(
  packages = c("cross", "bench", "reticulate", "tensorflow")
) {
  list(
    run_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    cpu = cpu_model(),
    cores = parallel::detectCores(),
    platform = sessioninfo::platform_info(),
    packages = sessioninfo::package_info(packages, dependencies = FALSE)
  )
}

format_provenance <- function(provenance, extra = NULL) {
  platform <- provenance$platform
  packages <- as.data.frame(provenance$packages)

  rows <- c(
    list(
      c("run at", provenance$run_at),
      c("OS", platform$os),
      c("system", platform$system),
      c("CPU", provenance$cpu),
      c("cores detected", as.character(provenance$cores)),
      c("R", platform$version)
    ),
    lapply(
      seq_len(nrow(packages)),
      function(i) {
        c(
          paste("R package:", packages$package[i]),
          paste0(packages$ondiskversion[i], " (", packages$source[i], ")")
        )
      }
    ),
    lapply(names(extra), function(key) c(key, extra[[key]]))
  )

  body <- vapply(
    rows,
    function(row) paste0("| ", row[1], " | `", row[2], "` |"),
    character(1)
  )
  c("| | |", "|---|---|", body)
}

# One file per run, holding the question, the numbers, and the environment that
# produced them. Never overwritten by a later run: a NEWS entry linking here has
# to keep pointing at the numbers it was written about.
write_results_md <- function(
  path,
  title,
  question,
  body,
  provenance = host_provenance(),
  extra = NULL
) {
  lines <- c(
    paste("#", title),
    "",
    "## The question",
    "",
    question,
    "",
    "## Results",
    "",
    body,
    "",
    "## Environment",
    "",
    format_provenance(provenance, extra),
    "",
    paste(
      "Timings are bound to this machine. Ratios within this run are",
      "meaningful; the absolute numbers are not comparable with a run on",
      "different hardware."
    )
  )
  writeLines(lines, path)
  invisible(path)
}
