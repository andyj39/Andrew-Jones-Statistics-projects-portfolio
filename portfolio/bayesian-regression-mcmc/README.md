# Bayesian Linear Regression with MCMC

Compares ways of estimating a Bayesian linear regression on simulated data (n = 100, known true parameters):

- Gibbs sampler, written from scratch
- Metropolis-Hastings, written from scratch
- Importance sampling, written from scratch
- MCMCpack and maximum likelihood as references

Assessed on accuracy, chain mixing (trace plots, autocorrelation, running means), effective sample size, coverage of 95% intervals and runtime. A repeated simulation over 1,000 datasets checks accuracy across samples. The full write-up is in [`report/SOR4008_report.pdf`](report/SOR4008_report.pdf).

## Results

From one knit of the file (seed 115, 100 observations, 50,000 iterations with 10,000 discarded as burn-in). True values: alpha 1.5, beta1 2, beta2 5, tau 1.

| Posterior mean | alpha | beta1 | beta2 | tau |
|---|---|---|---|---|
| My Gibbs sampler | 1.6715 | 1.9977 | 5.0125 | 1.0362 |
| MCMCpack | 1.6789 | 1.9972 | 5.0117 | 1.0369 |

The Gibbs sampler and MCMCpack agree to about two decimal places. The estimate of alpha is further from its true value than the others, but the 95% credible interval (1.13 to 2.21) contains 1.5.

Effective sample size after burn-in, which says how many independent draws a chain is worth:

| Method | alpha | beta1 | beta2 | tau |
|---|---|---|---|---|
| Gibbs | 3,454 | 6,064 | 4,485 | 35,425 |
| Metropolis-Hastings | 69 | 465 | 262 | 14 |

The Metropolis-Hastings chain is far less efficient, especially for tau.

Coverage over the 1,000 simulated datasets was 95.3%, 95.3%, 95.7% and 96.4% for alpha, beta1, beta2 and tau, close to the 95% intended.

Importance sampling from the prior is the least accurate method. Its estimate of tau is 0.49 against a true value of 1, and its 90% interval for alpha (-0.84 to 4.19) is far wider than the other methods give. With only 80,000 prior draws in four dimensions, most of the weight probably lands on a few draws.

## Run
Open `bayesian_regression_mcmc.Rmd` in RStudio and knit. The importance sampling and 1,000-dataset sections are slow. Packages: ggplot2, knitr, coda, MCMCpack, rmarkdown.

