# Three levels of testing, sized from measurement rather than guessed.
#
# Costs are from `2026-09-21-tier-costs/`, which timed every example in both
# tiers at targets 200, 500 and 1000, at the settings of the time: 1, 1 and 3
# sampling runs per example. Seconds:
#
#            examples  target_ess  runs  bench repeats  determ.  sampling
#   quick           4         200     1             10       18        42
#   standard        5         500     1             30       66       122
#   thorough        5        1000     3             50       92       705
#
#            per branch   two-branch comparison
#   quick            60      120  (2.0 min)
#   standard        188      376  (6.3 min)
#   thorough        797     1594  (26.6 min)
#
# Every tier now runs at least 3 of each sampling run (`reps`), so sampling
# costs about `reps` times the figure above. Three things those numbers do NOT
# include:
#
#   * {cross} installing each branch, which happens once per branch per tier
#     and has never been timed. Add it to every row.
#   * they are an over-estimate of the deterministic tier, because the run that
#     produced them gave every example its own process, so each paid its own
#     TensorFlow initialisation. The pipeline builds all the examples in one
#     process per branch and pays that once.
#   * the seeded fits, `reps` of them per example.
#
#   flash      a first look, in a few minutes. Only `linear`, low target, and
#              more runs than quick: five of each sampling measurement and ten
#              fixed-length mcmc() runs, so its one model has the most spread
#              to read.
#   quick      before a commit. Four examples, low target, three runs of each
#              sampling measurement. At a 200 ESS target the Monte Carlo error
#              is large and the posterior comparison is correspondingly
#              insensitive.
#   standard   before a pull request. All five examples, moderate target, five
#              runs.
#   thorough   before a CRAN release, to understand what a version did to
#              speed. All five, high target, five runs.
#
# `reps` is how many times each version runs each sampling measurement: time
# to a target ESS, and the seeded fit. `mcmc_repeats` is how many fixed-length
# mcmc() runs are timed, and `bench_repeats` the fewest repeats of model() and
# opt(); bench::mark() stops at twice that.
#
# `cjs` is in standard and thorough but not quick. It is the only deep-graph
# example and it earns its place, but it costs 38 s in the deterministic tier
# and 73-93 s in the sampling tier - roughly five times any other example, and
# more than half of a full pass. Quick exists to be run often, so it leaves it
# out; the moment a change might touch graph construction, that is what
# standard is for.
#
# The sampling cost is NOT proportional to the target. Every run pays its
# warmup and initial samples, so an example that reaches the target on that
# first pass costs the same at 200 as at 1000. Two consequences worth knowing
# before changing these numbers:
#
#   * cjs is flat across targets (89, 73, 93 s at 200, 500, 1000) because it
#     reaches bulk-ESS of 4700-8000 on the initial sample. Raising its target
#     is free.
#   * eight_schools is not. It costs ~10 s at targets 200 and 500, and 96 s at
#     1000, needing 64,180 iterations against 2,400. That is the funnel: cheap
#     until you ask for real precision, then expensive. It is the single
#     biggest reason thorough costs what it does, and the best argument for
#     keeping it.

tier_settings <- function(tier = c("flash", "quick", "standard", "thorough")) {
  tier <- rlang::arg_match(tier)

  settings <- list(
    flash = list(
      examples = "linear",
      target_ess = 200,
      reps = 5,
      bench_repeats = 10,
      mcmc_repeats = 10,
      time_limit = 60
    ),
    quick = list(
      examples = c(
        "linear",
        "multiple_linear",
        "hierarchical_linear",
        "eight_schools"
      ),
      target_ess = 200,
      reps = 3,
      bench_repeats = 10,
      mcmc_repeats = 5,
      time_limit = 120
    ),
    standard = list(
      examples = c(
        "linear",
        "multiple_linear",
        "hierarchical_linear",
        "eight_schools",
        "cjs"
      ),
      target_ess = 500,
      reps = 5,
      bench_repeats = 30,
      mcmc_repeats = 10,
      time_limit = 300
    ),
    thorough = list(
      examples = c(
        "linear",
        "multiple_linear",
        "hierarchical_linear",
        "eight_schools",
        "cjs"
      ),
      target_ess = 1000,
      reps = 5,
      bench_repeats = 50,
      mcmc_repeats = 20,
      time_limit = 600
    )
  )

  settings[[tier]]
}
