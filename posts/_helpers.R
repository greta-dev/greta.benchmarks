# What every post's page uses to show its results: loading them, linking to
# the scripts that made them, formatting numbers, the raincloud figure, tables,
# and the "Run it yourself" code under each figure. A page sources this file at
# the top of its setup chunk:
#
#   source(here::here("posts", "_helpers.R"))
#
# Nothing here computes a statistic a post reports. A change to this file can
# change how an old post looks, never what it measured or concluded, so
# anything that summarises results (medians, ratios, ESS) stays in the post
# that reports it. Quarto skips files whose names start with an underscore, so
# this is not rendered as a page.

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(bench)
  library(here)
})

theme_set(theme_bw(base_size = 13))

# ---- results ----

# every session file a post's run.R wrote, read in session order
read_sessions <- function(post_path, results_dir = "results") {
  files <- list.files(
    here(post_path, results_dir),
    pattern = "^session-[0-9]+[.]rds$",
    full.names = TRUE
  )
  session_numbers <- as.integer(gsub("\\D", "", basename(files)))
  lapply(files[order(session_numbers)], readRDS)
}

# The versions as a page shows them. `labels` maps the names run.R gave the
# versions to the names the page uses. `on_github` maps those run.R names to
# the GitHub commit for any version pak installed from a local archive, which
# the results record as a local path.
display_versions <- function(versions, labels = NULL, on_github = NULL) {
  installed_locally <- startsWith(versions, "local::")
  versions[installed_locally] <- on_github[names(versions)[installed_locally]]
  if (!is.null(labels)) {
    names(versions) <- unname(labels[names(versions)])
  }
  versions
}

# the GitHub page of a version installed from a commit, such as
# "greta-dev/greta@1140593..."
commit_url <- function(installed_from) {
  paste0(
    "https://github.com/greta-dev/greta/commit/",
    sub(".*@", "", installed_from)
  )
}

pr_url <- function(number) {
  paste0("https://github.com/greta-dev/greta/pull/", number)
}

# a version as installed: a commit on GitHub as a link to it, a CRAN release as
# it is
version_link <- function(installed_from) {
  sha <- sub(".*@", "", installed_from)
  is_commit <- grepl("^[0-9a-f]{40}$", sha)
  ifelse(
    is_commit,
    paste0(
      "[",
      sub("@.*", "", installed_from),
      "@",
      substr(sha, 1, 8),
      "](",
      commit_url(installed_from),
      ")"
    ),
    installed_from
  )
}

# The first call on a model traces its TensorFlow functions; the calls after it
# on the same model can reuse them.
label_calls <- function(call) {
  factor(
    ifelse(call == 1, "first call", "calls after the first"),
    levels = c("first call", "calls after the first")
  )
}

# one row per timed call: bench keeps every call's time in a mark's `time`
# column, in the order the calls ran. `...` names the mark's columns to keep,
# such as a press() argument.
every_call <- function(marks, ...) {
  marks |>
    as_tibble() |>
    select(..., time) |>
    mutate(call = lapply(time, seq_along)) |>
    unnest(c(time, call)) |>
    mutate(
      seconds = as.numeric(time),
      calls = label_calls(call),
      .keep = "unused"
    )
}

# ---- links to the scripts ----

# The scripts on GitHub, at the commit being rendered when GitHub Actions
# renders the site, and on main otherwise. Quarto escapes markdown in an inline
# `{r}` result unless it is wrapped in I(), so both linkers return I().
github_file_url <- function(post_path, file) {
  paste0(
    "https://github.com/greta-dev/greta.benchmarks/blob/",
    Sys.getenv("GITHUB_SHA", "main"),
    "/",
    post_path,
    "/",
    file
  )
}

# the lines of a script's `# ---- label ----` section: from its heading to the
# line before the next one, without trailing blank lines
section_lines <- function(post_path, file, label) {
  lines <- readLines(here(post_path, file))
  headings <- grep("^# ---- .+ ----$", lines)
  start <- headings[lines[headings] == paste("# ----", label, "----")]
  if (length(start) != 1) {
    stop("no section `", label, "` in ", file, call. = FALSE)
  }
  end <- c(headings, length(lines) + 1)[match(start, headings) + 1] - 1
  while (end > start && !nzchar(trimws(lines[end]))) {
    end <- end - 1
  }
  c(start = start, end = end)
}

# a page's link helpers, for its own post: file_link("benchmark.R") and
# section_link("benchmark.R", "bench-linear")
file_linker <- function(post_path) {
  function(file) {
    I(paste0("[`", file, "`](", github_file_url(post_path, file), ")"))
  }
}

section_linker <- function(post_path) {
  function(file, label) {
    where <- section_lines(post_path, file, label)
    I(paste0(
      "[`",
      label,
      "`](",
      github_file_url(post_path, file),
      "#L",
      where[["start"]],
      "-L",
      where[["end"]],
      ")"
    ))
  }
}

# "Timed by `benchmark.R`'s `a` and `b` sections.", for under a figure
timed_by <- function(section_link, file, labels, verb = "Timed") {
  links <- vapply(labels, \(label) section_link(file, label), character(1))
  sections <- if (length(links) == 1) {
    paste(links, "section")
  } else {
    paste(
      paste(links[-length(links)], collapse = ", "),
      "and",
      links[length(links)],
      "sections"
    )
  }
  I(paste0(verb, " by `", file, "`'s ", sections, "."))
}

# ---- run it yourself ----

# The code a reader can run to repeat what a figure's data came from: the
# script sections it needs, in order, inside one cross::run_versions() call
# that installs each version in a library of its own and runs the code in a
# fresh R session against it. It is built from the script, so it is exactly
# the sections that ran. run_versions() returns the value of the code's last
# line for each version, and a greta model cannot leave its R session, so
# `returns` is a last line naming the timings to bring back.
#
# It returns the code as lines, for a chunk to show through knitr's `code`
# option, which Quarto then folds and highlights like any other code:
#
#   ```{r}
#   #| label: run-mcmc
#   #| eval: false
#   #| code-summary: "Run it yourself"
#   #| code: !expr run_it_yourself(post_path, "benchmark.R", labels, versions, "mcmc_linear")
#   ```
run_it_yourself <- function(post_path, file, labels, versions, returns) {
  sections <- lapply(labels, function(label) {
    where <- section_lines(post_path, file, label)
    readLines(here(post_path, file))[where[["start"]]:where[["end"]]]
  })
  sections <- c(unlist(sections), "# the timings to bring back", returns)
  body <- paste0("    ", sections)
  body[!nzchar(trimws(body))] <- ""
  pkgs <- paste0('    "', unname(versions), '"')
  pkgs[-length(pkgs)] <- paste0(pkgs[-length(pkgs)], ",")
  c(
    "# install.packages(c(\"pak\", \"bench\"))",
    "# pak::pak(\"DavisVaughan/cross\")",
    "results <- cross::run_versions(",
    "  {",
    body,
    "  },",
    "  pkgs = c(",
    pkgs,
    "  )",
    ")"
  )
}

# ---- numbers ----

# three significant figures, where format() would pad a vector to the decimal
# places of its smallest value; formatC() can pad with leading spaces, which
# trimws() removes
format_number <- function(x) {
  trimws(formatC(signif(x, 3), format = "fg", digits = 3, big.mark = ","))
}

# "a to b", or one number when the two round the same
format_range <- function(x) {
  ends <- format_number(range(x))
  if (ends[1] == ends[2]) {
    return(ends[1])
  }
  paste(ends, collapse = " to ")
}

# How long one version takes against another, naming the slower one, so the
# ratio is never below 1: "main takes 1.2 to 1.5 times as long as #855", or
# "#855 takes 1.1 times as long as main" when #855 is the slower. `ratios` are
# `version`'s times over `reference`'s, one per model or case. Where they fall
# on both sides of 1, the sentence gives each version's largest lead. The
# names can be markdown links, so like the linkers it returns I().
compare_times <- function(ratios, version, reference) {
  I(times_sentence(ratios, version, reference))
}

times_sentence <- function(ratios, version, reference) {
  if (all(ratios >= 1)) {
    paste(version, "takes", format_range(ratios), "times as long as", reference)
  } else if (all(ratios <= 1)) {
    paste(
      reference,
      "takes",
      format_range(1 / ratios),
      "times as long as",
      version
    )
  } else {
    paste0(
      "it varies: ",
      version,
      " takes up to ",
      format_number(max(ratios)),
      " times as long as ",
      reference,
      ", and ",
      reference,
      " up to ",
      format_number(max(1 / ratios)),
      " times as long as ",
      version
    )
  }
}

# The same for a measure where more is better, such as effective samples per
# second, naming the version that gives more: "#855 gives 2.3 to 6.5 times
# CRAN's". `ratios` are `version`'s values over `reference`'s.
compare_rates <- function(ratios, version, reference) {
  I(rates_sentence(ratios, version, reference))
}

rates_sentence <- function(ratios, version, reference) {
  if (all(ratios >= 1)) {
    paste0(version, " gives ", format_range(ratios), " times ", reference, "'s")
  } else if (all(ratios <= 1)) {
    paste0(
      reference,
      " gives ",
      format_range(1 / ratios),
      " times ",
      version,
      "'s"
    )
  } else {
    paste0(
      "it varies: ",
      version,
      " gives up to ",
      format_number(max(ratios)),
      " times ",
      reference,
      "'s, and ",
      reference,
      " up to ",
      format_number(max(1 / ratios)),
      " times ",
      version,
      "'s"
    )
  }
}

# ---- figures and tables ----

# The site's colours for versions, in run.R's order: the first (CRAN, by
# convention) is always orange and the last (the PR or branch the post is
# about) always pink, so the PR is the same colour in every post; any between,
# such as main or an earlier commit, take blue and green in turn.
version_colours <- function(version_levels) {
  n <- length(version_levels)
  between <- c("#56B4E9", "#009E73", "#0072B2")[seq_len(max(n - 2, 0))]
  palette <- c("#E69F00", between, if (n > 1) "#CC79A7")
  setNames(palette, version_levels)
}

# A raincloud for each version: the density of its calls above, their box
# plot in the middle, and every call as a dot below. The summaries are drawn
# first and faint, so the dots sit on top.
raincloud <- function(colours) {
  list(
    ggdist::stat_halfeye(
      aes(fill = version),
      width = 0.4,
      justification = -0.3,
      .width = 0,
      point_colour = NA,
      alpha = 0.3
    ),
    geom_boxplot(
      aes(fill = version),
      width = 0.25,
      outlier.shape = NA,
      alpha = 0.3
    ),
    # a fixed dot size, so a call looks the same size in every panel
    ggdist::stat_dots(
      aes(fill = version),
      side = "bottom",
      layout = "swarm",
      justification = 1.3,
      scale = 0.75,
      binwidth = unit(2.6, "mm"),
      overflow = "compress",
      colour = NA,
      alpha = 0.6
    ),
    scale_colour_manual(values = colours, guide = "none"),
    scale_fill_manual(values = colours, guide = "none")
  )
}

raincloud_caption <- "Each dot is one call, from every session. Above the dots, the curve is the density of the calls and the box marks their median and quartiles."

# a searchable table, its numbers rounded for reading
dt_table <- function(data, digits = 3) {
  table <- DT::datatable(
    data,
    rownames = FALSE,
    filter = "top",
    options = list(pageLength = 10, autoWidth = TRUE)
  )
  decimal_columns <- names(data)[vapply(data, is.double, logical(1))]
  if (length(decimal_columns) == 0) {
    return(table)
  }
  DT::formatRound(table, decimal_columns, digits)
}

# ---- session details ----

# A saved sessioninfo::session_info() prints as a plain list unless
# sessioninfo's print method is registered, which loading its namespace does.
invisible(loadNamespace("sessioninfo"))
