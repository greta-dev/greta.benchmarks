# What tf\$Variable-backed data nodes cost


greta-dev/greta#739 gives every data node a persistent `tf$Variable`
instead of folding its value into each trace. That buys swapping data
without a retrace. This is what it costs everyone who never swaps
anything.

20 reps per model, 200 warmup and 200 samples on 2 chains.

| branch         | sha        |
|:---------------|:-----------|
| data-variables | b24adc0df9 |
| main           | b24adc0df9 |

## Time

| model | build_data-variables | build_main | mcmc_data-variables | mcmc_main |
|:---|---:|---:|---:|---:|
| hierarchical_linear | 0.060 | 0.037 | 3.382 | 2.393 |
| hierarchical_slopes_corr | 0.050 | 0.036 | 3.704 | 2.453 |
| linear | 0.043 | 0.026 | 2.122 | 1.525 |
| multiple_linear | 0.041 | 0.027 | 2.161 | 1.409 |
| wide_linear | 0.053 | 0.034 | 5.633 | 3.071 |

Ratios, branch relative to main. Above 1 is slower.

| model                    | build_ratio | mcmc_ratio |
|:-------------------------|------------:|-----------:|
| hierarchical_linear      |        1.61 |       1.41 |
| hierarchical_slopes_corr |        1.40 |       1.51 |
| linear                   |        1.69 |       1.39 |
| multiple_linear          |        1.53 |       1.53 |
| wide_linear              |        1.54 |       1.83 |

## Memory

RSS deltas in MB: at dag construction, where the variables are created,
and across sampling. Total is what the process actually grew by.

| model | build_mb_data-variables | build_mb_main | mcmc_mb_data-variables | mcmc_mb_main | total_mb_data-variables | total_mb_main |
|:---|---:|---:|---:|---:|---:|---:|
| hierarchical_linear | 0.1 | 0.8 | 66.7 | 55.2 | 66.8 | 52.8 |
| hierarchical_slopes_corr | 0.2 | 0.0 | 69.4 | 25.1 | 69.6 | 14.3 |
| linear | 0.1 | 0.0 | 31.3 | 27.9 | 31.4 | 27.9 |
| multiple_linear | 0.1 | 0.0 | 32.9 | 28.6 | 33.0 | 28.6 |
| wide_linear | 9.3 | 0.0 | 33.6 | 119.1 | 42.1 | 119.1 |

## Is the spread small enough to read these?

Min and max across reps, so a ratio computed from medians can be judged
against the noise it sits in.

| model | label | mcmc_min | mcmc_max | total_mb_min | total_mb_max |
|:---|:---|---:|---:|---:|---:|
| hierarchical_linear | data-variables | 2.30 | 8.68 | -899.5 | 79.4 |
| hierarchical_linear | main | 2.03 | 7.01 | -577.0 | 442.8 |
| hierarchical_slopes_corr | data-variables | 2.33 | 8.03 | 19.0 | 116.3 |
| hierarchical_slopes_corr | main | 2.16 | 9.53 | -510.8 | 71.0 |
| linear | data-variables | 1.41 | 6.04 | -100.0 | 160.8 |
| linear | main | 1.23 | 4.26 | -383.9 | 319.4 |
| multiple_linear | data-variables | 1.39 | 4.91 | -259.0 | 38.0 |
| multiple_linear | main | 1.27 | 4.88 | -280.5 | 32.6 |
| wide_linear | data-variables | 2.74 | 14.49 | 31.0 | 88.7 |
| wide_linear | main | 2.57 | 10.80 | -347.6 | 226.9 |
