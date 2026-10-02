# Iterations per draw, and efficiency at equal iterations


CRAN is greta 0.6.0 (`v0.6.0`), main is `179021a8`, and \#850 is
`bcbbea4d`. Each was installed in its own library and run in its own R
process.

## The models

Normal and log-normal distributions are written with their mean and
standard deviation, as greta’s `normal()` and `lognormal()` take them;
$\text{Cauchy}^{+}$ is a Cauchy truncated to positive values.

### For timing: a large regression

The timing in `01-time-per-draw.R` needs each iteration to cost enough
to measure, so it uses a regression on 20,000 simulated observations,
with the residual standard deviation known.

$$\begin{aligned}
y_i &\sim \text{Normal}(\alpha + \beta \, x_i, 1), \quad i = 1, \dots, 20000 \\
\alpha, \beta &\sim \text{Normal}(0, 10)
\end{aligned}$$

``` r
set.seed(2026 - 10 - 01)
n_observations <- 20000
predictor <- rnorm(n_observations)
response <- 1 + 2 * predictor + rnorm(n_observations)

intercept <- normal(0, 10)
slope <- normal(0, 10)
distribution(response) <- normal(intercept + slope * predictor, 1)
m <- model(intercept, slope)
```

### For efficiency: four of greta’s example models

From greta’s `inst/examples/`, as the benchmark suite runs them.

#### linear

A regression of each department’s rating in `attitude` on its number of
complaints.

$$\begin{aligned}
\text{rating}_i &\sim \text{Normal}(\mu_i, \sigma), \quad i = 1, \dots, 30 \\
\mu_i &= \alpha + \beta \, \text{complaints}_i \\
\alpha, \beta &\sim \text{Normal}(0, 10) \\
\sigma &\sim \text{Cauchy}^{+}(0, 3)
\end{aligned}$$

``` r
int <- normal(0, 10)
coef <- normal(0, 10)
sd <- cauchy(0, 3, truncation = c(0, Inf))
mu <- int + coef * attitude$complaints
distribution(attitude$rating) <- normal(mu, sd)
m <- model(int, coef, sd)
```

#### multiple_linear

The same rating on all six of `attitude`’s other columns, $X$.

$$\begin{aligned}
\text{rating}_i &\sim \text{Normal}(\mu_i, \sigma), \quad i = 1, \dots, 30 \\
\mu_i &= \alpha + \sum_{j = 1}^{6} X_{ij} \, \beta_j \\
\alpha, \beta_j &\sim \text{Normal}(0, 10) \\
\sigma &\sim \text{Cauchy}^{+}(0, 3)
\end{aligned}$$

``` r
design <- as.matrix(attitude[, 2:7])
int <- normal(0, 10)
coefs <- normal(0, 10, dim = ncol(design))
sd <- cauchy(0, 3, truncation = c(0, Inf))
mu <- int + design %*% coefs
distribution(attitude$rating) <- normal(mu, sd)
m <- model(int, coefs, sd)
```

#### hierarchical_linear

Sepal length on sepal width in `iris`, with an offset for each species,
$s[i]$ being flower $i$’s. Setosa’s offset is zero and the other two
share a scale, $\tau$.

$$\begin{aligned}
\text{Sepal.Length}_i &\sim \text{Normal}(\mu_i, \sigma), \quad i = 1, \dots, 150 \\
\mu_i &= \alpha + \beta \, \text{Sepal.Width}_i + \gamma_{s[i]} \\
\gamma_1 &= 0, \qquad \gamma_2, \gamma_3 \sim \text{Normal}(0, \tau) \\
\tau &\sim \text{LogNormal}(0, 1) \\
\alpha, \beta &\sim \text{Normal}(0, 10) \\
\sigma &\sim \text{Cauchy}^{+}(0, 3)
\end{aligned}$$

``` r
int <- normal(0, 10)
coef <- normal(0, 10)
sd <- cauchy(0, 3, truncation = c(0, Inf))
species_sd <- lognormal(0, 1)
species_offset <- normal(0, species_sd, dim = 2)
species_effect <- rbind(0, species_offset)
species_id <- as.numeric(iris$Species)
mu <- int + coef * iris$Sepal.Width + species_effect[species_id]
distribution(iris$Sepal.Length) <- normal(mu, sd)
m <- model(int, coef, sd, species_sd, species_offset)
```

#### eight_schools

The effect of coaching in eight schools, $y_j$, each measured with a
known standard error, $\sigma_j$. The scale of the school effects is
itself a parameter, which makes the posterior a funnel.

$$\begin{aligned}
y_j &\sim \text{Normal}(\theta_j, \sigma_j), \quad j = 1, \dots, 8 \\
\theta_j &= \mu + \xi \, \eta_j \\
\eta_j &\sim \text{Normal}(0, \sigma_\eta) \\
\sigma_\eta &\sim \text{InverseGamma}(1, 1) \\
\mu &\sim \text{Normal}(0, 100) \\
\xi &\sim \text{Normal}(0, 5)
\end{aligned}$$

``` r
y <- c(28, 8, -3, 7, -1, 1, 18, 12)
sigma_y <- c(15, 10, 16, 11, 9, 11, 10, 18)
N <- length(y)
sigma_eta <- inverse_gamma(1, 1)
eta <- normal(0, sigma_eta, dim = N)
mu_theta <- normal(0, 100)
xi <- normal(0, 5)
theta <- mu_theta + xi * eta
distribution(y) <- normal(theta, sigma_y)
m <- model(sigma_eta, eta, mu_theta, xi)
```

## Iterations per draw

`01-time-per-draw.R` times `rwmh()` on a 20,000-row regression: one
chain, no warmup, three runs each of `n_samples = 3000` and
`n_samples = 12000`. Milliseconds per draw is the slope between the two
lengths, so each call’s fixed cost, mostly tracing the sampler, cancels
out.

If CRAN and main run `thin + 1` iterations per draw and \#850 runs
`thin`, then a draw costs 0.095 ms per iteration plus 0.022 ms for
keeping it. Those two numbers are fitted to main and \#850 at
`thin = 1`. Every other point below is a prediction from them, and lands
on the measurement.

<div id="fig-time-per-draw">

![](results_files/figure-commonmark/fig-time-per-draw-1.png)

Figure 1: Milliseconds per kept draw. The filled dot is measured; the
open circle is predicted from thin + 1 iterations per draw on CRAN and
main, and thin on \#850. Where the prediction is right, the dot sits
inside the circle.

</div>

<details>

<summary>

Table of time per draw, measured and predicted
</summary>

| version | thin | iterations per draw, if thin + 1 | ms per draw | predicted |
|:--------|-----:|---------------------------------:|------------:|----------:|
| CRAN    |    1 |                                2 |       0.212 |     0.212 |
| CRAN    |    3 |                                4 |       0.400 |     0.402 |
| main    |    1 |                                2 |       0.212 |     0.212 |
| main    |    3 |                                4 |       0.396 |     0.402 |
| \#850   |    1 |                                1 |       0.117 |     0.117 |
| \#850   |    3 |                                3 |       0.308 |     0.307 |

</details>

## Efficiency at equal iterations

`02-efficiency.R` runs each model 8 times, with seeds 1 to 8, as 4
chains of 2000 warmup and 2000 sampling iterations on every version:
`warmup = 1000, n_samples = 1000` on CRAN and main, and `2000, 2000` on
\#850. A run’s ESS is the smallest bulk ESS over the model’s variables.
Seconds include warmup. CRAN does not follow `set.seed()` in `mcmc()`,
so its runs differ by more than the seed.

<div id="fig-ess">

![](results_files/figure-commonmark/fig-ess-1.png)

Figure 2: Every run’s ESS, from 8000 sampling iterations: the small dots
are single runs and the large dot is their mean.

</div>

<div id="fig-ess-per-second">

![](results_files/figure-commonmark/fig-ess-per-second-1.png)

Figure 3: Every run’s ESS per second of mcmc(), warmup included: the
small dots are single runs and the large dot is their mean.

</div>

<details>

<summary>

Table of the minimum, median and maximum over the 8 runs
</summary>

| model | version | ESS min | ESS median | ESS max | seconds min | seconds median | seconds max | ESS per second, median | epsilon, median | runs with R-hat \> 1.01 |
|:---|:---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| eight_schools | CRAN | 96.58 | 243.22 | 333.91 | 3.11 | 3.43 | 3.83 | 72.64 | 5.52 | 5 |
| eight_schools | main | 24.80 | 238.93 | 385.98 | 3.12 | 3.33 | 3.88 | 64.38 | 5.61 | 6 |
| eight_schools | \#850 | 131.91 | 238.47 | 301.65 | 4.11 | 4.48 | 4.66 | 53.26 | 6.05 | 6 |
| hierarchical_linear | CRAN | 24.23 | 100.70 | 151.83 | 4.17 | 4.62 | 5.93 | 19.20 | 0.11 | 8 |
| hierarchical_linear | main | 11.93 | 50.38 | 180.87 | 4.50 | 4.77 | 5.46 | 10.76 | 0.11 | 8 |
| hierarchical_linear | \#850 | 13.89 | 156.39 | 829.51 | 5.72 | 6.06 | 6.39 | 25.50 | 0.11 | 8 |
| linear | CRAN | 34.22 | 213.10 | 1022.05 | 2.69 | 2.87 | 3.28 | 75.45 | 0.38 | 6 |
| linear | main | 74.63 | 277.74 | 1034.53 | 2.77 | 3.04 | 3.41 | 86.60 | 0.37 | 5 |
| linear | \#850 | 518.87 | 679.79 | 1587.28 | 3.72 | 3.93 | 4.21 | 178.00 | 0.58 | 1 |
| multiple_linear | CRAN | 19.92 | 48.95 | 206.44 | 2.72 | 2.92 | 3.37 | 15.51 | 0.28 | 8 |
| multiple_linear | main | 7.17 | 47.93 | 184.73 | 2.84 | 3.04 | 3.44 | 15.80 | 0.29 | 8 |
| multiple_linear | \#850 | 24.04 | 124.41 | 213.50 | 3.66 | 4.04 | 4.27 | 31.57 | 0.42 | 8 |

</details>

<details>

<summary>

Table of every run
</summary>

| example | version | seed | seconds | epsilon | ess_bulk_min | ess_tail_min | rhat_max | ess_per_second |
|:---|:---|---:|---:|---:|---:|---:|---:|---:|
| eight_schools | CRAN | 1 | 3.398 | 5.726 | 291.739 | 354.173 | 1.004 | 85.856 |
| eight_schools | CRAN | 2 | 3.811 | 5.050 | 297.568 | 381.959 | 1.004 | 78.081 |
| eight_schools | CRAN | 3 | 3.828 | 5.444 | 333.908 | 355.460 | 1.005 | 87.228 |
| eight_schools | CRAN | 4 | 3.110 | 5.568 | 227.545 | 158.361 | 1.015 | 73.165 |
| eight_schools | CRAN | 5 | 3.428 | 5.800 | 203.297 | 128.964 | 1.016 | 59.305 |
| eight_schools | CRAN | 6 | 3.433 | 5.472 | 96.581 | 38.214 | 1.032 | 28.133 |
| eight_schools | CRAN | 7 | 3.590 | 5.435 | 258.901 | 252.867 | 1.015 | 72.117 |
| eight_schools | CRAN | 8 | 3.197 | 5.856 | 188.137 | 68.112 | 1.035 | 58.848 |
| eight_schools | main | 1 | 3.248 | 5.591 | 35.650 | 14.109 | 1.083 | 10.976 |
| eight_schools | main | 2 | 3.681 | 5.510 | 299.792 | 310.879 | 1.016 | 81.443 |
| eight_schools | main | 3 | 3.528 | 5.540 | 214.640 | 218.847 | 1.018 | 60.839 |
| eight_schools | main | 4 | 3.121 | 5.636 | 24.798 | 12.964 | 1.108 | 7.946 |
| eight_schools | main | 5 | 3.272 | 4.967 | 310.866 | 269.187 | 1.013 | 95.008 |
| eight_schools | main | 6 | 3.396 | 5.821 | 385.975 | 540.332 | 1.005 | 113.656 |
| eight_schools | main | 7 | 3.875 | 5.638 | 263.224 | 138.269 | 1.007 | 67.929 |
| eight_schools | main | 8 | 3.255 | 5.769 | 133.085 | 58.603 | 1.019 | 40.886 |
| eight_schools | \#850 | 1 | 4.107 | 6.169 | 278.379 | 260.856 | 1.022 | 67.782 |
| eight_schools | \#850 | 2 | 4.293 | 6.003 | 229.657 | 114.240 | 1.010 | 53.496 |
| eight_schools | \#850 | 3 | 4.627 | 6.118 | 179.547 | 215.046 | 1.016 | 38.804 |
| eight_schools | \#850 | 4 | 4.654 | 6.042 | 301.649 | 284.034 | 1.018 | 64.815 |
| eight_schools | \#850 | 5 | 4.416 | 6.054 | 226.601 | 126.268 | 1.007 | 51.314 |
| eight_schools | \#850 | 6 | 4.553 | 6.148 | 131.910 | 40.533 | 1.043 | 28.972 |
| eight_schools | \#850 | 7 | 4.242 | 5.948 | 272.129 | 194.204 | 1.013 | 64.151 |
| eight_schools | \#850 | 8 | 4.664 | 5.724 | 247.290 | 310.395 | 1.012 | 53.021 |
| hierarchical_linear | CRAN | 1 | 4.351 | 0.135 | 151.827 | 283.346 | 1.014 | 34.895 |
| hierarchical_linear | CRAN | 2 | 4.363 | 0.112 | 62.155 | 150.027 | 1.067 | 14.246 |
| hierarchical_linear | CRAN | 3 | 4.167 | 0.126 | 128.321 | 192.258 | 1.033 | 30.795 |
| hierarchical_linear | CRAN | 4 | 4.590 | 0.098 | 77.492 | 169.450 | 1.077 | 16.883 |
| hierarchical_linear | CRAN | 5 | 5.517 | 0.107 | 86.069 | 123.873 | 1.034 | 15.601 |
| hierarchical_linear | CRAN | 6 | 5.928 | 0.105 | 127.507 | 153.210 | 1.046 | 21.509 |
| hierarchical_linear | CRAN | 7 | 4.818 | 0.129 | 115.332 | 99.959 | 1.047 | 23.938 |
| hierarchical_linear | CRAN | 8 | 4.643 | 0.096 | 24.230 | 57.258 | 1.134 | 5.219 |
| hierarchical_linear | main | 1 | 4.524 | 0.134 | 180.869 | 341.893 | 1.012 | 39.980 |
| hierarchical_linear | main | 2 | 4.861 | 0.111 | 52.682 | 58.524 | 1.079 | 10.838 |
| hierarchical_linear | main | 3 | 4.497 | 0.122 | 48.069 | 143.768 | 1.080 | 10.689 |
| hierarchical_linear | main | 4 | 4.688 | 0.090 | 11.926 | 48.294 | 1.241 | 2.544 |
| hierarchical_linear | main | 5 | 4.557 | 0.105 | 34.236 | 74.409 | 1.099 | 7.513 |
| hierarchical_linear | main | 6 | 5.464 | 0.095 | 63.941 | 123.780 | 1.071 | 11.702 |
| hierarchical_linear | main | 7 | 4.914 | 0.136 | 82.400 | 178.081 | 1.065 | 16.768 |
| hierarchical_linear | main | 8 | 5.054 | 0.100 | 27.493 | 50.881 | 1.138 | 5.440 |
| hierarchical_linear | \#850 | 1 | 6.358 | 0.145 | 171.577 | 476.208 | 1.029 | 26.986 |
| hierarchical_linear | \#850 | 2 | 5.880 | 0.114 | 141.209 | 311.720 | 1.028 | 24.015 |
| hierarchical_linear | \#850 | 3 | 6.388 | 0.129 | 454.222 | 710.680 | 1.030 | 71.106 |
| hierarchical_linear | \#850 | 4 | 6.298 | 0.091 | 118.215 | 111.923 | 1.023 | 18.770 |
| hierarchical_linear | \#850 | 5 | 5.880 | 0.114 | 224.359 | 270.790 | 1.018 | 38.156 |
| hierarchical_linear | \#850 | 6 | 5.720 | 0.094 | 13.894 | 20.911 | 1.206 | 2.429 |
| hierarchical_linear | \#850 | 7 | 6.230 | 0.138 | 829.510 | 1201.103 | 1.011 | 133.148 |
| hierarchical_linear | \#850 | 8 | 5.805 | 0.105 | 113.221 | 142.136 | 1.056 | 19.504 |
| linear | CRAN | 1 | 3.219 | 0.261 | 186.142 | 389.935 | 1.016 | 57.826 |
| linear | CRAN | 2 | 3.279 | 0.499 | 1022.050 | 1348.112 | 1.005 | 311.696 |
| linear | CRAN | 3 | 2.697 | 0.216 | 34.221 | 75.396 | 1.097 | 12.688 |
| linear | CRAN | 4 | 2.835 | 0.370 | 208.797 | 432.148 | 1.011 | 73.650 |
| linear | CRAN | 5 | 2.918 | 0.401 | 354.508 | 724.607 | 1.009 | 121.490 |
| linear | CRAN | 6 | 2.809 | 0.334 | 217.393 | 458.484 | 1.015 | 77.391 |
| linear | CRAN | 7 | 2.688 | 0.406 | 184.788 | 376.156 | 1.016 | 68.746 |
| linear | CRAN | 8 | 2.904 | 0.390 | 224.314 | 432.032 | 1.018 | 77.243 |
| linear | main | 1 | 3.340 | 0.294 | 329.581 | 487.370 | 1.010 | 98.677 |
| linear | main | 2 | 3.414 | 0.473 | 1034.533 | 1635.422 | 1.003 | 303.027 |
| linear | main | 3 | 2.826 | 0.250 | 74.627 | 171.300 | 1.061 | 26.407 |
| linear | main | 4 | 3.031 | 0.374 | 225.901 | 570.121 | 1.012 | 74.530 |
| linear | main | 5 | 3.043 | 0.498 | 482.894 | 829.613 | 1.007 | 158.690 |
| linear | main | 6 | 2.955 | 0.325 | 163.893 | 361.419 | 1.031 | 55.463 |
| linear | main | 7 | 2.771 | 0.376 | 119.429 | 346.107 | 1.041 | 43.100 |
| linear | main | 8 | 3.337 | 0.440 | 348.182 | 713.622 | 1.011 | 104.340 |
| linear | \#850 | 1 | 4.192 | 0.546 | 1587.280 | 2813.517 | 1.006 | 378.645 |
| linear | \#850 | 2 | 3.745 | 0.745 | 783.047 | 1789.681 | 1.005 | 209.091 |
| linear | \#850 | 3 | 4.138 | 0.423 | 573.482 | 846.785 | 1.015 | 138.589 |
| linear | \#850 | 4 | 3.918 | 0.583 | 711.096 | 1288.855 | 1.005 | 181.495 |
| linear | \#850 | 5 | 3.948 | 0.612 | 556.968 | 855.814 | 1.010 | 141.076 |
| linear | \#850 | 6 | 4.211 | 0.461 | 1037.375 | 1655.167 | 1.002 | 246.349 |
| linear | \#850 | 7 | 3.776 | 0.572 | 518.868 | 939.483 | 1.010 | 137.412 |
| linear | \#850 | 8 | 3.716 | 0.620 | 648.484 | 1221.087 | 1.007 | 174.511 |
| multiple_linear | CRAN | 1 | 3.205 | 0.282 | 66.741 | 91.757 | 1.061 | 20.824 |
| multiple_linear | CRAN | 2 | 3.299 | 0.262 | 62.039 | 126.303 | 1.072 | 18.805 |
| multiple_linear | CRAN | 3 | 2.771 | 0.290 | 32.123 | 112.548 | 1.140 | 11.593 |
| multiple_linear | CRAN | 4 | 2.902 | 0.274 | 19.921 | 92.511 | 1.152 | 6.865 |
| multiple_linear | CRAN | 5 | 3.371 | 0.369 | 206.443 | 297.793 | 1.020 | 61.241 |
| multiple_linear | CRAN | 6 | 2.935 | 0.241 | 35.861 | 84.745 | 1.107 | 12.218 |
| multiple_linear | CRAN | 7 | 2.862 | 0.341 | 72.413 | 120.519 | 1.062 | 25.301 |
| multiple_linear | CRAN | 8 | 2.718 | 0.269 | 20.189 | 83.332 | 1.169 | 7.428 |
| multiple_linear | main | 1 | 3.259 | 0.166 | 7.165 | 21.486 | 1.552 | 2.199 |
| multiple_linear | main | 2 | 3.160 | 0.296 | 83.507 | 194.261 | 1.050 | 26.426 |
| multiple_linear | main | 3 | 2.883 | 0.196 | 7.514 | 30.088 | 1.523 | 2.606 |
| multiple_linear | main | 4 | 2.986 | 0.352 | 50.497 | 208.867 | 1.076 | 16.911 |
| multiple_linear | main | 5 | 3.444 | 0.346 | 184.735 | 522.383 | 1.016 | 53.640 |
| multiple_linear | main | 6 | 3.087 | 0.299 | 45.372 | 147.613 | 1.098 | 14.698 |
| multiple_linear | main | 7 | 2.970 | 0.249 | 53.200 | 134.280 | 1.068 | 17.913 |
| multiple_linear | main | 8 | 2.838 | 0.289 | 19.282 | 33.094 | 1.159 | 6.794 |
| multiple_linear | \#850 | 1 | 3.660 | 0.380 | 64.662 | 102.311 | 1.054 | 17.667 |
| multiple_linear | \#850 | 2 | 4.064 | 0.453 | 147.448 | 438.752 | 1.038 | 36.282 |
| multiple_linear | \#850 | 3 | 3.744 | 0.325 | 24.035 | 111.519 | 1.109 | 6.420 |
| multiple_linear | \#850 | 4 | 4.144 | 0.471 | 213.500 | 393.198 | 1.023 | 51.520 |
| multiple_linear | \#850 | 5 | 4.014 | 0.493 | 200.702 | 421.992 | 1.021 | 50.001 |
| multiple_linear | \#850 | 6 | 4.272 | 0.314 | 193.524 | 460.833 | 1.035 | 45.301 |
| multiple_linear | \#850 | 7 | 4.149 | 0.294 | 93.660 | 234.392 | 1.039 | 22.574 |
| multiple_linear | \#850 | 8 | 3.775 | 0.461 | 101.381 | 255.561 | 1.030 | 26.856 |

</details>
