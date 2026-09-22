# Every package the pipeline attaches, in one place.
#
# Sourced by _targets.R and by anything else that loads R/ on its own account,
# so every entry point resolves a bare verb the same way. Keeping this list
# here rather than in tar_option_set(packages = ) means there is one list, not
# two that drift.

library(targets)
library(tarchetypes)
library(conflicted)

library(cross)
library(bench)
library(here)
library(fs)
library(withr)
library(quarto)

library(dplyr)
library(tidyr)
library(ggplot2)

# kable() in report.qmd. The report sources this file rather than keeping its
# own library() calls, so anything it needs belongs here - one list, not two
library(knitr)

# posterior intervals in the report
library(ggdist)

# greta and posterior are deliberately NOT attached here. Every measurement runs
# in a {cross} subprocess that installs a particular branch of greta, so this
# session must not hold a greta of its own - and posterior is only ever used
# inside those subprocesses, where it is namespaced.

# last line, so nothing can attach the packages above without the declared
# winners that go with them
source(here::here("conflicts.R"))
