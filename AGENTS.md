## This package

<!-- Insert package-specific content here. use_tidy_agents() will preserve this section when updating the rest of the file. -->

Benchmarks for greta, kept so a speed claim in `NEWS.md`, an issue, or a code
comment can point at the code that produced it.

### Never report a number you cannot re-run

- Any number being presented to the user (chat, issue, commit, PR), the
code that produced it must be **saved in the repository first**. Not in a
terminal, not in `Rscript -e`, not in a scratch file that gets deleted.
- Exploration in the console is fine. The moment its output is worth showing to
someone, the code goes in a file. It should be run in order for it to be reporetd.

### Run directories

- One directory per run, named for its date and its question. For example: "2026-09-20-tune-diag-sd" is so named because it was on the 20th September 2026, and it is related to the function tune_diag_sd(). If there is an issue number attached to it, that should be appended. So the pattern is:
- `YYYY-MM-DD-short-name-i-issue-number` so: `2026-09-21-tune-diag-sd-i841`.
- A run directory is a lab notebook entry: once written it is never edited, and a later run of the
same comparison gets a new directory.

It should have the following files:

- 01-measure.R: the exact script that produced the output: results.rds
- results.rds: raw output, so a different question can be asked without re-measuring
- 02-report.R: renders results.qmd
- results.qmd: the write-up; reads results.rds, computes every number it quotes, creates results.html (and also a markdown file)
- results.html: rendered output

- **Prose that mentions a number computes it inline.** A re-run then changes the
  prose; a hand-typed number silently stops matching the table above it.
- **Save the whole object**, not a summary. Subsetting a `bench_mark` to
  `min`/`median` drops the `time` and `gc` list-columns, and then
  `summary(relative = TRUE)` and `autoplot()` cannot work.
- **Capture anything mutable at measure time** — git SHAs especially. Branches
  move, so resolving one while rendering records a commit that was never
  measured.
- **A script that has never run to completion is a draft.** Smoke-run it with
  reduced settings before spending an hour; say so rather than describing what
  it will produce.

### One measurement, one process

**Each cell — branch, model, replicate — runs in its own fresh R process, start
to finish, and writes its own result.** Loop over cells in the shell, not inside
a session.

This is not tidiness. A long-lived session accumulates state that ruins exactly
the numbers being collected:

- greta and TensorFlow grow over a session, so a replicate measured late is
  measured on a fuller process than one measured early.
- Garbage collection lands wherever it lands. RSS measured as a delta around a
  GC produces **negative deltas of hundreds of MB**, which is what a run of this
  harness actually reported.
- Running branch A's cells then branch B's means B is always measured on a
  machine A just loaded up. That is a systematic order effect, and more
  replicates make it worse rather than better.
- TensorFlow traces and caches persist, so the second model to run in a session
  is not paying the same costs as the first.

**Measure peak RSS of the short-lived process**, not a delta inside a long one.
A fresh process has a meaningful high-water mark; a session forty models deep
does not.

**Interleaving is not a substitute.** It spreads session state around rather
than removing it.

### Do not quote a ratio that is not resolved

Every comparison reports its own noise floor, and the resolved/unresolved
verdict is read **before** the ratios. A median ratio sitting inside a spread an
order of magnitude wider than the effect is not a finding.

Two runs of the same comparison in this repository gave 1.03-1.08x and
1.39-1.83x for the same code. Neither was real: within-cell ranges spanned 4x.
When two runs disagree like that, distrust the harness before the code.

The noise floor is not a stable property to be measured once and reused - it has
varied by 233x between replicates of the same cell. Measure it inside every
comparison.

### Using {cross}

- `run_branches()` and `bench_branches()` default to `current = TRUE`, which
  prepends whatever is checked out. Always pass `current = FALSE` with both
  branches named, or a run will silently mislabel a branch.
- `run_branches()` returns a **tibble** with a `branch` column and a `result`
  list-column, one row per branch — not a list named by branch.
- It calls `usethis::proj_get()`, so usethis must be installed, and it refuses
  to run when the current branch is one being measured and has uncommitted
  changes. Branches must be committed, not pushed.
- **Everything the expression needs must arrive through the environment**, via
  `args_callr = list(env = ...)` and `Sys.getenv()` inside the expression. It
  runs in a subprocess and cannot see this session. Closing over a variable
  looks like it works and fails at run time.

### Choosing what to measure

- **Match the metric to the change.** Wall time for work removed. Effective
  samples per second for anything that changes how the sampler explores — a
  timing comparison would miss that entirely. Record wall time anyway, so a
  gain in ESS/sec is not really the sampler running slower.
- **Record ESS as min, median and mean**, plus a count of parameters at zero.
  `effectiveSize()` returns 0 for a parameter that never moved, which drags the
  minimum to zero however well everything else mixed and makes the cell useless
  for comparison.
- **Carry the diagnostics too** — Rhat, acceptance — so a gain in ESS is not
  mistaken for a chain that has quietly stopped mixing.
- **Benchmark real models.** Use `bench_examples()` in `R/examples.R`, which is
  greta's own `inst/examples`. `normal(0, 1)` gives artefacts: it suggested
  per-iteration cost is flat with model size, which it is not.
- **Check the posterior geometry before trusting an ESS comparison.** `linear`
  regresses on an uncentred predictor, so its intercept and slope correlate at
  -0.97 and both mix far more slowly than `sd`. At 4 chains x 1000 that reads
  as a broken sampler; at 4 x (2000 warmup + 4000) it clears comfortably. An
  example like that measures the shape of its own posterior, not greta.
- **Size the run before quoting a ratio.** A small run of a real effect looks
  exactly like no effect. One comparison gave 27 ms and 62 ms on separate runs
  against a within-branch sd of ~58 ms; it only resolved at n = 50. Check the
  spread against the effect. `median` and `min` agreeing is not evidence
  against noise — they come from the same samples.
- **Run branches sequentially, not in parallel.** greta processes grow over
  long loops, and three at once will exhaust memory and contend for CPU, which
  also makes the timings incomparable.
- **Log what was dropped.** If a run bounds coverage — top-N, no retry,
  sampling — say so. Silent truncation reads as "covered everything".
- **Gate on convergence before comparing anything.** Without a gate, two
  branches running byte-identical sampling code reported "23.55x faster",
  because one run had an Rhat of 3.0. A chain that did not converge is not a
  fast chain.
- **Rhat means `psrf[, 1]`, the point estimate.** Using the upper confidence
  limit `psrf[, 2]` inflates failure rates; that error is already recorded
  against #790. And ESS detects trouble here more reliably than Rhat does —
  runs with Rhat 1.03 to 1.04 had ESS of 20, 95 and 150.
- **`mcmc()` does not respect `set.seed()` alone** (#285, #427), which is why
  every `bench::mark()` call passes `check = FALSE` and why ESS needs so many
  replicates. Setting `set.seed()` **and** `tf$random$set_seed()` does make
  draws reproducible (#834). Fixing that would cut ESS comparison cost by about
  an order of magnitude.
- **Consider time-to-target rather than ESS-at-fixed-iterations.**
  `get_enough_draws()` in greta's `tests/testthat/helpers.R` already samples
  until min ESS >= 5000 and all Rhat < 1.01, with a time cap. For comparing
  sampler quality that is the better-conditioned question, and the code exists.

### What the MCMC literature says to use

Current practice, with sources, because greta's helpers predate most of it.

- **Use `posterior`, not `coda`.** `posterior::rhat()` is rank-normalised and
  folded; `ess_bulk()` and `ess_tail()` split the centre from the tails; and
  `mcse_*()` gives Monte Carlo standard errors. Vehtari, Gelman, Simpson,
  Carpenter & Bürkner (2021), *Bayesian Analysis* 16(2), doi:10.1214/20-BA1221.
  The operative failure: `coda::effectiveSize()` fits an AR model per chain with
  no between-chain information, so it reports a large ESS for chains stuck in
  **different modes** — exactly what a sampler regression test must catch. The
  `posterior` estimator returns roughly the number of modes found instead.
- **Thresholds**: Rhat < 1.01, ESS > 400, at least four chains. Read ESS > 400
  as the point where the *diagnostics* become trustworthy, not as sufficient
  accuracy — for that, check MCSE.
- **Report bulk-ESS and tail-ESS.** Bulk licenses a reported mean; tail licenses
  a credible interval. They diverge: the paper's Cauchy example has bulk 214,
  tail 43.
- **`rhat_nested()`** is for many short chains, which is greta's situation when
  chains are vectorised through TFP. Margossian et al. (2025), *Bayesian
  Analysis* 20(4), arXiv:2110.13017.
- **Report ESS, gradient count and wall time as three numbers, not one ratio.**
  ESS per gradient evaluation is the hardware-independent regression signal
  (Hoffman, Radul & Sountsov 2021, AISTATS); ESS per second is what users feel
  but depends on chain count, thermal state and device saturation. Three numbers
  let a change be attributed to "needs fewer gradients" versus "each gradient
  got cheaper"; a single ratio destroys that. Count warmup gradients.
- **The minimum is the right estimator for timing, and the wrong one for ESS.**
  Timing noise is one-sided, so the minimum is robust (Chen & Revels 2016,
  arXiv:1608.04295). ESS is a genuine random variable — report a mean with an
  interval across seeds.
- **Establish the noise floor with an A/A run** — benchmark identical code
  against itself — before trusting any A/B. Report effect-size confidence
  intervals, not significance tests (Kalibera & Jones 2013, ISMM).

### A KS test on chain draws rejects correct samplers

This is live in greta and worth stating plainly. A two-sample KS test assumes
both samples are iid. MCMC draws are autocorrelated, so the null distribution of
the statistic is wider than the tabulated one, p-values come out too small, and
**a correct sampler fails too often**.

`tests/testthat/helpers.R` runs `stats::ks.test()` on Geweke output, and
`test_posteriors_geweke.R` passes a hardcoded `thin = 5` for hmc and rwmh and
**nothing at all for slice**, where `check_geweke()` defaults to `thin = 1`.
A fixed 5 is not derived from the chain's autocorrelation; 1 is the pathological
case.

There are two defensible fixes and no third:

1. **Thin by `ceil(N / ESS)`**, computed on indicator functions at equispaced
   quantiles and taken as the maximum across quantities (Talts, Betancourt,
   Simpson, Vehtari & Gelman 2018, arXiv:1804.06788, §5.1). Note HMC can be
   antithetic, so thin by 2 first to clear negative odd-lag correlations.
2. **Drop the KS test** for Geweke's own moment-based z-statistic, which divides
   by a spectral-density-at-zero variance and so needs no thinning. Geweke
   (2004), *JASA* 99(467).

Also: `check_geweke()` thins the *iid* sample too, which throws away power for
nothing. Only the chain needs thinning.

SBC is the modern relative (Talts et al. 2018), and marginal-only SBC "could
never detect large classes of problems including when the posterior is equal to
the prior" — it needs data-dependent test quantities, of which the joint
likelihood is the most useful (Modrák et al. 2025, *Bayesian Analysis* 20(2)).
Use ECDF simultaneous confidence bands rather than histogram bins (Säilynoja,
Bürkner & Vehtari 2022, *Statistics and Computing* 32:32).

### Existing suites worth borrowing rather than rebuilding

- **Inference Gym** (TFP spinoff) shares greta's backend, so its targets and
  stored ground truth — mean, sd, and standard error per parameter, generated
  from 10 chains x 150,000 CmdStan draws — transfer directly.
- **posteriordb** (Magnusson et al. 2025, AISTATS, arXiv:2407.04967): 147
  posteriors, 46 with reference draws. Its acceptance standard is a good model
  for ours — >= 10,000 draws, mean lag-1 autocorrelation < 0.05, Rhat < 1.01,
  no divergences. Its coverage list is the gap analysis below, arrived at
  independently: funnels, multimodal, discrete and mixed, high-dimensional,
  large-data, and simple analytically tractable posteriors.
- Compare against a reference **in MCSE units**, `z = (est - ref) / sqrt(mcse^2
  + mcse_ref^2)`, or bias cannot be separated from Monte Carlo noise. The
  reference has error too, and it bounds what can be claimed.

### Coverage the model set still lacks

Recorded so it is not rediscovered. `R/examples.R` holds five models, all from
greta's 31 `inst/examples`, none above 40 variables. Not represented anywhere:

- **The cholesky path.** `hierarchical_slopes_corr` was the only example using
  `lkj_correlation()` and `chol()`, and it was removed on 2026-09-21 for
  costing 542 seconds per 1000 ESS - 20-80x everything else - while still
  failing to reach target. `CorrelationCholesky` gradients are the ones XLA
  cannot compile, so a speed regression there is now invisible to the suite.
  Correctness is still covered by greta's own tests.
- **Anything above 40 variables.** greta's examples are nearly all small. The
  only genuinely large one is `factor_analysis` at 210, and it is identified
  only up to an orthogonal rotation, so its Rhat is bad however well the
  sampler works - measured at minimum bulk-ESS 5.4 after 42,000 iterations. A
  size axis needs either a synthetic model, labelled as such, or a target from
  posteriordb or Inference Gym.

- **Chains as an axis.** The suite runs one chain. #294 reports 185 effective
  samples/sec at 4 chains against 12,980 at 1024 — about 70x, the largest
  recorded effect in greta, and entirely unbenchmarked.
- **Warmup as an axis.** Fixed at 100. #834's effect is invisible below ~200
  free parameters and grows with warmup.
- **`wishart()` and `cholesky_variable()`.** The only cholesky model uses
  `lkj_correlation()`. #642 records a ~250x regression on a wishart cholesky.
- **Mixtures, `joint()`, discrete marginalisation, any time series.**
- **Samplers other than `hmc()`**, and `calculate()`/`simulate()` as tasks.
- **The extension packages** — greta.gp, greta.gam, greta.dynamics are the only
  users of kernel algebra, `MatrixInverse` and the ODE solver, and none is
  benchmarked.
- **Deep graphs where node count, not parameter count, is the cost** —
  `cjs.Rmd` and `hierarchical_linear_marginal.Rmd` are the two existing cases.

### Reprexes

A reprex is code someone else runs, so:

- **Make it complete and self-contained.** `library(greta)` and
  `greta:::internal_thing`, not `devtools::load_all()` — a reader has an
  installed greta, not a checkout. Include the lines that print the result; it
  is easy to cut them when moving a script into an issue, and then the reprex
  produces no output at all.
- **Run it and paste the verbatim output.** Never hand-assemble a table from
  two separate prints. Numbers copied from a terminal look identical to real
  output and are not reviewable.
- **Say what it was run on**, and if the numbers are not reproducible run to
  run, say that too and give the range. greta's draws can drift by a draw or
  two even with `set.seed()` and `tf$random$set_seed()` both set.
- **Show the smallest thing that fails**, and state what is expected, what
  happens instead, what the fix is, and what it is worth.

### Running R

There are three possible ways to run code, listed in rough order of desirability:

- If you're running inside Posit Assistant or otherwise have an
  `executeCode()` tool available, use it to run code in a session that the
  user can also interact with.

- Otherwise, if an R REPL (e.g. `mcp__r__repl` or `btw::run_r`) is
  available, use that. Note that `mcp__r__repl` uses a sandbox that blocks
  network requests and reads/writes outside of the current directory.

- Otherwise, use `Rscript -e "code"`. On Windows, `Rscript -e` can segfault on
  multiline or complex code; in that case, write it to a temporary `.R` file
  and run `Rscript path/to/file.R`.

### Code style

- Follow the tidyverse style guide
- Always run `air format .` after generating code. (air is bundled with Positron so look there if you can't otherwise find it.)
- Use the base pipe operator (`|>`), not the magrittr pipe (`%>%`).
- Use `\() ...` for single-line anonymous functions. For all other cases, use `function() {...}`.

## Specialized skills

- Do you need to deprecate a function or argument? Read `usethis::learn_tidy_skill("deprecate")`.
- Are you adding input checking to an existing function or writing a new exported function? Read `usethis::learn_tidy_skill("arg-checking")`.
- Are you creating a new package? Read `usethis::learn_tidy_skill("package-setup")`.

## Git

- If the user asks you to commit, use markdown in the commit message, and don't line wrap.
- If the commit fixes an issue, include `Fixes #num.` on its own line.
- Only push when the user explicitly requests it.

## Writing

- Do not use em-dashes just use "-"
- Do not use cat() or sprintf() to render things inline, use inline R code if you want to use it in a sentence with `{r} <r_code_here>` or write a table.
- Use sentence case for headings.
- Use Australian English.

### Proofreading

If the user asks you to proofread a file, act as an expert proofreader and editor with a deep understanding of clear, engaging, and well-structured writing.

Work paragraph by paragraph, always starting by making a TODO list that includes individual items for each top-level section.

Fix spelling, grammar, and other minor problems without asking the user. Label any unclear, confusing, or ambiguous sentences with a FIXME comment.

Only report what you have changed.
