# Every function greta traces, on main and greta#843


Four builds of greta: `main`; greta#843 as pushed (`branch`); \#843 with
`opt()`’s steps on a log-density function traced for one row (`fix`,
from `fix.patch`); and that, with `opt()`’s check of its initial values
using the same function (`fix_check`, from `fix-check.patch`).

## The census

Each call below ran in a fresh process on the linear example, with
`tensorflow::tf_function()` wrapped to record every function greta
created. “Functions” is how many it created, “traces” how many times
they were traced in total, and “most” the most any one function was
traced. A function traced more than once is retracing. `opt` is greta’s
default optimiser, `bfgs()`; `opt_adam` uses `adam()`, whose own traced
step calls the log-density function.

| scenario         | main      | branch    | fix       | fix_check |
|:-----------------|:----------|:----------|:----------|:----------|
| model            | 2 / 0 / 0 | 2 / 0 / 0 | 3 / 0 / 0 | 3 / 0 / 0 |
| opt              | 2 / 2 / 1 | 2 / 2 / 1 | 3 / 3 / 1 | 3 / 2 / 1 |
| opt_adam         | 3 / 4 / 2 | 3 / 3 / 1 | 4 / 4 / 1 | 4 / 3 / 1 |
| opt_twice        | 2 / 2 / 1 | 2 / 2 / 1 | 3 / 3 / 1 | 3 / 2 / 1 |
| opt_hessian      | 2 / 2 / 1 | 2 / 2 / 1 | 3 / 3 / 1 | 3 / 2 / 1 |
| mcmc             | 3 / 5 / 2 | 3 / 3 / 1 | 4 / 3 / 1 | 4 / 3 / 1 |
| extra_samples    | 3 / 5 / 2 | 3 / 3 / 1 | 4 / 3 / 1 | 4 / 3 / 1 |
| calculate_values | 5 / 6 / 2 | 6 / 4 / 1 | 8 / 4 / 1 | 8 / 4 / 1 |
| calculate_nsim   | 4 / 0 / 0 | 4 / 0 / 0 | 6 / 0 / 0 | 6 / 0 / 0 |

functions / traces / most traces of one function

Every function traced more than once, and every kind of function created
more than once within one call. `rows` is the free state’s number of
rows in the function’s signature: the log-density function’s
open-signature and one-row versions are made by the same method, and
this tells them apart.

| build | scenario | made_by | rows | created | most | traces |
|:---|:---|:---|:---|---:|---:|---:|
| main | opt_adam | define_tf_log_prob_function | no signature | 1 | 2 | 2 |
| main | mcmc | define_tf_log_prob_function | no signature | 1 | 2 | 2 |
| main | mcmc | define_tf_trace_values_batch | no signature | 1 | 2 | 2 |
| main | extra_samples | define_tf_log_prob_function | no signature | 1 | 2 | 2 |
| main | extra_samples | define_tf_trace_values_batch | no signature | 1 | 2 | 2 |
| main | calculate_values | define_tf_log_prob_function | no signature | 2 | 2 | 2 |
| main | calculate_values | define_tf_trace_values_batch | no signature | 2 | 2 | 3 |
| branch | calculate_values | define_tf_log_prob_function | rows open | 2 | 1 | 1 |
| branch | calculate_values | define_tf_trace_values_batch | rows open | 2 | 1 | 1 |
| fix | calculate_values | define_tf_log_prob_function | 1 row | 2 | 0 | 0 |
| fix | calculate_values | define_tf_log_prob_function | rows open | 2 | 1 | 1 |
| fix | calculate_values | define_tf_trace_values_batch | rows open | 2 | 1 | 1 |
| fix_check | calculate_values | define_tf_log_prob_function | 1 row | 2 | 0 | 0 |
| fix_check | calculate_values | define_tf_log_prob_function | rows open | 2 | 1 | 1 |
| fix_check | calculate_values | define_tf_trace_values_batch | rows open | 2 | 1 | 1 |
| main | calculate_nsim | define_tf_log_prob_function | no signature | 2 | 0 | 0 |
| main | calculate_nsim | define_tf_trace_values_batch | no signature | 2 | 0 | 0 |
| branch | calculate_nsim | define_tf_log_prob_function | rows open | 2 | 0 | 0 |
| branch | calculate_nsim | define_tf_trace_values_batch | rows open | 2 | 0 | 0 |
| fix | calculate_nsim | define_tf_log_prob_function | 1 row | 2 | 0 | 0 |
| fix | calculate_nsim | define_tf_log_prob_function | rows open | 2 | 0 | 0 |
| fix | calculate_nsim | define_tf_trace_values_batch | rows open | 2 | 0 | 0 |
| fix_check | calculate_nsim | define_tf_log_prob_function | 1 row | 2 | 0 | 0 |
| fix_check | calculate_nsim | define_tf_log_prob_function | rows open | 2 | 0 | 0 |
| fix_check | calculate_nsim | define_tf_trace_values_batch | rows open | 2 | 0 | 0 |

## What tracing costs opt()

Seconds for `opt(m, optimiser = adam(), max_iterations = 100)` on each
example, in a fresh process: the first call, which traces, and a second,
which reuses those traces. Medians of 3 replicates, with their range.

| build     | example             | first             | second              |
|:----------|:--------------------|:------------------|:--------------------|
| main      | cjs                 | 9.69 (9.54-10.06) | 0.618 (0.614-0.648) |
| branch    | cjs                 | 7.34 (7.33-7.49)  | 0.836 (0.829-0.850) |
| fix       | cjs                 | 9.51 (9.50-9.61)  | 0.619 (0.597-0.624) |
| fix_check | cjs                 | 7.02 (6.95-7.02)  | 0.606 (0.601-0.618) |
| main      | eight_schools       | 0.52 (0.52-0.54)  | 0.086 (0.085-0.088) |
| branch    | eight_schools       | 0.50 (0.49-0.50)  | 0.115 (0.114-0.115) |
| fix       | eight_schools       | 0.55 (0.54-0.55)  | 0.083 (0.083-0.084) |
| fix_check | eight_schools       | 0.42 (0.42-0.50)  | 0.084 (0.083-0.087) |
| main      | hierarchical_linear | 0.77 (0.74-0.77)  | 0.110 (0.110-0.111) |
| branch    | hierarchical_linear | 0.70 (0.70-0.72)  | 0.155 (0.151-0.163) |
| fix       | hierarchical_linear | 0.79 (0.78-0.79)  | 0.107 (0.107-0.111) |
| fix_check | hierarchical_linear | 0.58 (0.58-0.59)  | 0.106 (0.105-0.106) |
| main      | linear              | 0.46 (0.45-0.46)  | 0.079 (0.078-0.079) |
| branch    | linear              | 0.43 (0.43-0.44)  | 0.101 (0.101-0.102) |
| fix       | linear              | 0.47 (0.47-0.47)  | 0.076 (0.075-0.077) |
| fix_check | linear              | 0.37 (0.36-0.37)  | 0.075 (0.075-0.077) |
| main      | multiple_linear     | 0.45 (0.45-0.45)  | 0.078 (0.078-0.080) |
| branch    | multiple_linear     | 0.43 (0.42-0.43)  | 0.103 (0.102-0.114) |
| fix       | multiple_linear     | 0.47 (0.46-0.47)  | 0.075 (0.075-0.075) |
| fix_check | multiple_linear     | 0.36 (0.36-0.36)  | 0.076 (0.075-0.076) |

## Builds

| build     | commit                                   | patch           |
|:----------|:-----------------------------------------|:----------------|
| main      | 282944f572bb386ebf9b6bc21749336cbbea42b8 |                 |
| branch    | e57e4c981195da732a7f9156ce99463fc55c4b54 |                 |
| fix       | e57e4c981195da732a7f9156ce99463fc55c4b54 | fix.patch       |
| fix_check | e57e4c981195da732a7f9156ce99463fc55c4b54 | fix-check.patch |
