# mcmc() on main and thinning-i318 (greta#318)


On main
([282944f5](https://github.com/greta-dev/greta/commit/282944f572bb386ebf9b6bc21749336cbbea42b8)),
greta passed `thin` to TensorFlow Probability as
`num_steps_between_results`, which keeps one draw in `thin + 1`: every
draw and every warmup step cost two HMC iterations at the default
`thin = 1`. thinning-i318
([8ddcdece](https://github.com/greta-dev/greta/commit/8ddcdeceee32d3252f6a25c38ab82e4dfb294288))
passes `thin - 1`.

## Fixed work: `mcmc()` with the same arguments

The deterministic task runs `mcmc()` with fixed settings on each branch.
The branch is 1.30 to 1.49 times faster across both tiers. Less than two
is expected, since each run also pays costs outside the HMC iterations -
tracing, and the R-to-TensorFlow round trip per burst - but this run
does not measure how much of each call they take.

| tier     | example             | main_s | branch_s | speedup |
|:---------|:--------------------|-------:|---------:|--------:|
| quick    | eight_schools       |   3.26 |     2.19 |    1.49 |
| quick    | hierarchical_linear |   4.18 |     2.94 |    1.42 |
| quick    | linear              |   2.58 |     1.93 |    1.34 |
| quick    | multiple_linear     |   2.76 |     2.05 |    1.35 |
| standard | cjs                 |  27.55 |    18.52 |    1.49 |
| standard | eight_schools       |   3.12 |     2.30 |    1.35 |
| standard | hierarchical_linear |   4.36 |     2.98 |    1.46 |
| standard | linear              |   2.67 |     2.04 |    1.30 |
| standard | multiple_linear     |   2.85 |     2.07 |    1.38 |

## Do the branches sample the same posterior?

Across 9 example-tier comparisons, 0 variables disagree beyond Monte
Carlo error.

| tier | example | variables | max_abs_z | n_disagree | verdict |
|:---|:---|---:|---:|---:|:---|
| quick | eight_schools | 11 | 2.19 | 0 | agree within Monte Carlo error |
| quick | hierarchical_linear | 6 | 0.43 | 0 | agree within Monte Carlo error |
| quick | linear | 3 | 1.89 | 0 | agree within Monte Carlo error |
| quick | multiple_linear | 8 | 2.31 | 0 | agree within Monte Carlo error |
| standard | cjs | 40 | 1.82 | 0 | agree within Monte Carlo error |
| standard | eight_schools | 11 | 1.76 | 0 | agree within Monte Carlo error |
| standard | hierarchical_linear | 6 | 1.96 | 0 | agree within Monte Carlo error |
| standard | linear | 3 | 1.08 | 0 | agree within Monte Carlo error |
| standard | multiple_linear | 8 | 1.58 | 0 | agree within Monte Carlo error |

## Sampling to a target ESS

One replicate per branch in both tiers, which `R/tiers.R` notes cannot
resolve a sampling-speed difference. These swing both ways by more than
the fix could cause, and the reason is the tuned step size: on the
linear example alone, `atelier/evidence/check-thinning-ess-i318.R` found
minimum bulk-ESS varying more than ten-fold across three seeds on the
same branch. Per HMC iteration actually run, the branches mix alike
there; per `n_samples`, the branch gives about half, since main ran two
iterations per draw.

|  | tier | example | branch | elapsed | mcmc_samples | seconds_per_1000_ess | ess_bulk_min | rhat_max |
|:---|:---|:---|:---|---:|---:|---:|---:|---:|
| eight_schools…1 | quick | eight_schools | main | 5.58 | 2000 | 11.46 | 487.24 | 1.00 |
| eight_schools…2 | quick | eight_schools | thinning-i318 | 14.84 | 16256 | 33.86 | 438.45 | 1.01 |
| hierarchical_linear…3 | quick | hierarchical_linear | main | 7.75 | 2000 | 16.37 | 473.57 | 1.01 |
| hierarchical_linear…4 | quick | hierarchical_linear | thinning-i318 | 32.57 | 9066 | 66.67 | 488.62 | 1.01 |
| linear…5 | quick | linear | main | 6.43 | 2000 | 1.59 | 4052.54 | 1.00 |
| linear…6 | quick | linear | thinning-i318 | 4.89 | 2500 | 11.74 | 416.02 | 1.01 |
| multiple_linear…7 | quick | multiple_linear | main | 21.26 | 7783 | 84.23 | 252.44 | 1.01 |
| multiple_linear…8 | quick | multiple_linear | thinning-i318 | 9.49 | 6474 | 44.01 | 215.60 | 1.01 |
| cjs…9 | standard | cjs | main | 301.44 | 11600 | 9.62 | 31328.58 | 1.02 |
| cjs…10 | standard | cjs | thinning-i318 | 300.22 | 11900 | 11.18 | 26846.82 | 1.02 |
| eight_schools…11 | standard | eight_schools | main | 296.03 | 162000 | 579.69 | 510.66 | 1.01 |
| eight_schools…12 | standard | eight_schools | thinning-i318 | 22.20 | 22000 | 16.94 | 1310.44 | 1.00 |
| hierarchical_linear…13 | standard | hierarchical_linear | main | 9.86 | 2000 | 19.55 | 504.16 | 1.01 |
| hierarchical_linear…14 | standard | hierarchical_linear | thinning-i318 | 36.61 | 29558 | 70.30 | 520.86 | 1.01 |
| linear…15 | standard | linear | main | 6.53 | 2000 | 6.04 | 1082.03 | 1.00 |
| linear…16 | standard | linear | thinning-i318 | 6.88 | 3907 | 13.04 | 527.89 | 1.00 |
| multiple_linear…17 | standard | multiple_linear | main | 11.96 | 7425 | 14.86 | 804.31 | 1.01 |
| multiple_linear…18 | standard | multiple_linear | thinning-i318 | 10.96 | 9959 | 20.97 | 522.86 | 1.01 |
