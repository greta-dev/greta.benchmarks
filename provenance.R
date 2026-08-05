# Environment capture for a benchmark run.
#
# This is shared while each run's run.R is not, and the distinction is
# deliberate: what these functions return is written into a run's results.md at
# the moment it runs, so editing this file never changes what a past run
# recorded. Analysis code does not have that property, which is why it stays
# frozen inside its run directory.

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

package_versions <- function(packages) {
  versions <- vapply(
    packages,
    function(pkg) {
      tryCatch(
        as.character(utils::packageVersion(pkg)),
        error = function(e) NA_character_
      )
    },
    character(1)
  )
  versions
}

git_sha <- function(repo, rev) {
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
    os = paste(Sys.info()[["sysname"]], Sys.info()[["release"]]),
    arch = R.version$arch,
    cpu = cpu_model(),
    cores = parallel::detectCores(),
    r_version = R.version.string,
    packages = package_versions(packages)
  )
}

format_provenance <- function(provenance, extra = NULL) {
  rows <- c(
    list(
      c("run at", provenance$run_at),
      c("OS", provenance$os),
      c("architecture", provenance$arch),
      c("CPU", provenance$cpu),
      c("cores detected", as.character(provenance$cores)),
      c("R", provenance$r_version)
    ),
    lapply(
      names(provenance$packages),
      function(pkg) c(paste("R package:", pkg), provenance$packages[[pkg]])
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
