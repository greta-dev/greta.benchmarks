# How often an hmc() chain stops mixing on main

greta main at 179021a8, one chain per seed, seeds 1 to 50, `mcmc()` defaults (1000 warmup, 1000 samples, `hmc(Lmin = 5, Lmax = 10)`) with `verbose = FALSE`, on the one-parameter model from `test-data-swapping.R`. `01-measure.R` records the leapfrog count L that `hmc()` draws for the sampling phase; `theta` is the angle one leapfrog step turns a Gaussian posterior with sd 1 / sqrt(10.01).

- 8 of 50 chains have a bulk ESS below 100 from 1000 draws; 2 below 10.
- Every one of them has L * theta / pi within 0.063 of a whole number.
- Tuned epsilon ranges from 0.528 to 0.558, so theta barely changes between seeds and the same values of L land on whole numbers every time.

## The twelve chains with the lowest ESS

| seed| epsilon|  L| L * theta / pi| distance from whole number| lag-1 autocorrelation| bulk ESS|
|----:|-------:|--:|--------------:|--------------------------:|---------------------:|--------:|
|   34|   0.548|  6|          4.002|                      0.002|                 0.997|    1.422|
|   28|   0.545|  6|          3.966|                      0.034|                 0.956|    3.163|
|    7|   0.546|  6|          3.981|                      0.019|                 0.986|   10.585|
|   15|   0.548|  9|          6.013|                      0.013|                 0.990|   12.230|
|   21|   0.543|  6|          3.952|                      0.048|                 0.933|   25.482|
|   27|   0.546|  9|          5.965|                      0.035|                 0.950|   29.582|
|    9|   0.544|  6|          3.963|                      0.037|                 0.941|   47.380|
|   37|   0.542|  6|          3.937|                      0.063|                 0.884|   74.182|
|    4|   0.542|  9|          5.910|                      0.090|                 0.814|  118.885|
|   14|   0.543|  9|          5.912|                      0.088|                 0.775|  121.544|
|   18|   0.538|  6|          3.894|                      0.106|                 0.739|  151.644|
|    3|   0.540|  6|          3.906|                      0.094|                 0.781|  152.371|

## Chains by the L drawn for sampling

|   | ESS < 100| ESS >= 100|
|:--|---------:|----------:|
|5  |         0|          8|
|6  |         6|          2|
|7  |         0|          8|
|8  |         0|         10|
|9  |         2|          8|
|10 |         0|          6|
