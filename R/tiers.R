# Three levels of testing, sized from measurement rather than guessed.
#
# Costs are from `2026-09-21-tier-costs/`, which timed every example in both
# tiers at targets 200, 500 and 1000. Seconds:
#
#            examples  target_ess  reps  bench_iterations  determ.  sampling
#   quick           4         200     1                10       18        42
#   standard        5         500     1                30       66       122
#   thorough        5        1000     3                50       92       705
#
#            per branch   two-branch comparison
#   quick            60      120  (2.0 min)
#   standard        188      376  (6.3 min)
#   thorough        797     1594  (26.6 min)
#
# Two things those numbers do NOT include:
#
#   * {cross} installing each branch, which happens once per branch per tier
#     and has never been timed. Add it to every row.
#   * they are an over-estimate of the deterministic tier, because the run that
#     produced them gave every example its own process, so each paid its own
#     TensorFlow initialisation. The pipeline builds all the examples in one
#     process per branch and pays that once.
#
#   quick      before a commit. Four examples, low target, one replicate.
#              Catches a branch that broke something; too coarse to catch a
#              subtle shift, because at a 200 ESS target the Monte Carlo error
#              is large and the posterior comparison is correspondingly
#              insensitive. Read it as "did it run", not "did it converge".
#   standard   before a pull request. All five examples, moderate target.
#   thorough   before a CRAN release, to understand what a version did to
#              speed. All five, high target, three replicates - the only tier
#              where the sampling wall-time comparison can resolve anything,
#              because that needs spread across replicates.
#
# `reps` is the only setting the *sampling speed* comparison depends on, so
# quick and standard will both report "too few runs to say" there. That is
# correct rather than broken: the deterministic timings get their spread from
# bench_iterations, and the posterior comparison gets its uncertainty from
# MCSE within a single run, so both still work at reps = 1.
#
# `cjs` is in standard and thorough but not quick. It is the only deep-graph
# example and it earns its place, but it costs 38 s in the deterministic tier
# and 73-93 s in the sampling tier - roughly five times any other example, and
# more than half of a full pass. Quick exists to be run often, so it leaves it
# out; the moment a change might touch graph construction, that is what
# standard is for.
#
# The sampling cost is NOT proportional to the target. Every run pays 2000
# warmup and 2000 initial samples, so an example that reaches the target on
# that first pass costs the same at 200 as at 1000. Two consequences worth
# knowing before changing these numbers:
#
#   * cjs is flat across targets (89, 73, 93 s at 200, 500, 1000) because it
#     reaches bulk-ESS of 4700-8000 on the initial sample. Raising its target
#     is free.
#   * eight_schools is not. It costs ~10 s at targets 200 and 500, and 96 s at
#     1000, needing 64,180 iterations against 2,400. That is the funnel: cheap
#     until you ask for real precision, then expensive. It is the single
#     biggest reason thorough costs what it does, and the best argument for
#     keeping it.

tier_settings <- function(tier = c("quick", "standard", "thorough")) {
  tier <- rlang::arg_match(tier)

  settings <- list(
    quick = list(
      examples = c(
        "linear",
        "multiple_linear",
        "hierarchical_linear",
        "eight_schools"
      ),
      target_ess = 200,
      reps = 1,
      bench_iterations = 10,
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
      reps = 1,
      bench_iterations = 30,
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
      reps = 3,
      bench_iterations = 50,
      time_limit = 600
    )
  )

  settings[[tier]]
}
