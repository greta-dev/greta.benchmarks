# report.qmd is the report template: rendered from the standing pipeline's
# store by the `report` target, and from a run directory's own store by
# render_report(). These are the pieces it calls, and the check that the code
# it shows is the code that was measured.

#' Render report.qmd from a targets store into a run directory, as report.html
#' and report.md. `further` is a child document of measurements particular to
#' the run, knitted into the report's section 6. Paths are relative to the
#' project root, where the report is rendered.
render_report <- function(store, out_dir, title, further = "") {
  report_params <- list(store = store, further = further)
  # quarto reads the title as YAML, where a colon would start a mapping
  stopifnot(!grepl(":", title))

  # quarto empties its --output-dir when a render fails: pointed at a run
  # directory, that deleted every file in it. So it renders into a new
  # temporary directory, and only the finished files are copied across
  staging <- fs::file_temp("report-")
  render_args <- c(
    "--output-dir",
    staging,
    "--metadata",
    paste0("title:", title)
  )

  # --output-dir also makes quarto append its own lines to the project's
  # .gitignore, so it is put back as it was
  gitignore <- here(".gitignore")
  gitignore_lines <- readLines(gitignore)
  on.exit(writeLines(gitignore_lines, gitignore), add = TRUE)

  # html first: embedding its figures deletes report_files/, which the
  # markdown version links to, so the markdown has to be rendered after it
  quarto::quarto_render(
    here("report.qmd"),
    output_format = "html",
    execute_params = report_params,
    quarto_args = render_args
  )
  quarto::quarto_render(
    here("report.qmd"),
    output_format = "gfm",
    execute_params = report_params,
    quarto_args = render_args
  )

  fs::file_copy(
    fs::path(staging, c("report.html", "report.md")),
    out_dir,
    overwrite = TRUE
  )

  # only the figures report.md links to: quarto also carries across whatever
  # an earlier render left in the project's own report_files/
  report_md <- readLines(fs::path(staging, "report.md"))
  figures <- unique(unlist(regmatches(
    report_md,
    gregexpr("report_files/[^)]+[.]png", report_md)
  )))
  previous_figures <- fs::path(out_dir, "report_files")
  if (fs::dir_exists(previous_figures)) {
    fs::dir_delete(previous_figures)
  }
  fs::dir_create(fs::path_dir(fs::path(out_dir, figures)))
  fs::file_copy(
    fs::path(staging, figures),
    fs::path(out_dir, figures),
    overwrite = TRUE
  )
}

#' Every timed run as its own row, in seconds: the model() and opt() repeats
#' from bench::mark(), and the fixed-length mcmc() runs.
timed_runs <- function(timings, mcmc_runs) {
  bench_runs <- timings |>
    as_tibble() |>
    mutate(seconds = lapply(time, as.numeric)) |>
    select(example, task, branch, seconds) |>
    unnest(seconds)
  mcmc_timed <- mcmc_runs |>
    mutate(task = "mcmc") |>
    select(example, task, branch, seconds)
  bind_rows(bench_runs, mcmc_timed)
}

#' A note for a model's subsection when the tier did not measure it, or nothing
#' when it did.
unmeasured_note <- function(name, example_names, tier) {
  if (name %in% example_names) {
    return("")
  }
  paste0("Not measured at the ", tier, " tier.")
}

#' A sentence giving an example's parameter count: the number of values
#' mcmc() returns for it, read from its seeded fit.
parameter_text <- function(fit_draws, name, tier) {
  if (!name %in% fit_draws$example) {
    return(paste0("Not measured at the ", tier, " tier."))
  }
  n_parameters <- n_distinct(fit_draws$variable[fit_draws$example == name])
  paste0("Parameters: ", n_parameters, ".")
}

#' An example's greta code, from R/examples.R, up to and including its call
#' to model(). What follows that only tells the report what to plot.
example_code <- function(name) {
  examples <- new.env()
  sys.source(here("R", "examples.R"), envir = examples, keep.source = TRUE)
  source_lines <- as.character(attr(
    examples$bench_examples()[[name]],
    "srcref"
  ))
  model_line <- grep("^\\s*m <- model\\(", source_lines)
  body_lines <- source_lines[2:model_line]
  indent <- min(nchar(sub("\\S.*", "", body_lines[nzchar(body_lines)])))
  substring(body_lines, indent + 1)
}

#' Stop if a chunk of model code written out in report.qmd differs from that
#' model in R/examples.R. `chunks` names each chunk label by its example.
#' Call it while knitting: knitr reads every chunk before running any.
check_shown_code <- function(chunks) {
  differs <- vapply(
    names(chunks),
    function(name) {
      shown <- as.character(knitr::knit_code$get(chunks[[name]]))
      !identical(shown, example_code(name))
    },
    logical(1)
  )
  if (any(differs)) {
    stop(
      "report.qmd shows different code from R/examples.R for: ",
      paste(names(chunks)[differs], collapse = ", "),
      call. = FALSE
    )
  }
}

#' A fenced R code block, for a chunk with `output: asis`.
code_block <- function(lines) {
  cat("```r", lines, "```", sep = "\n")
}
