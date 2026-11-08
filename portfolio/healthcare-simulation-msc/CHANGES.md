# What I changed in the code

The dissertation code was two R Markdown files: one for the model (about 3,000 lines) and one for the ambulance station distances. They are in [`original/`](original) exactly as submitted. The scripts in [`scripts/`](scripts) are the same code split into the order it runs, with the edits listed here. Everything not listed below is copied unchanged.

## Tidying (the code does the same thing)

- Eight numbered scripts, each starting with a short header saying what it needs and what it makes.
- File locations are set once in `config.R`. The `file.choose()` prompts are gone.
- Package installs are in `00_setup.R` and `01_station_distances.R`. This also removes a typo in the original (`install.packages("dpylr")`).
- `run_all.R` runs the scripts in order.
- Section titles and a few comments were added.

## Edits that can change what the code produces

1. **Number of simulated years.** `rpois(1000, ...)` became `rpois(n_sim_years, ...)` in script 02. The default is still 1,000, so a normal run is unchanged. It allows a quick test with fewer years.

2. **Markov horizon.** The original set `markov_horizon <- 40` near the top, but the function default and the `common_args` list both passed `markov_horizon = 70` into the model. The dissertation says 40, so `common_args` now uses the 40 set in script 03. The function's own default of 70 is left as it was, but `common_args` always overrides it. This does not move any result: the expected QALYs per extra survivor are 4.742 for either horizon, because almost every survivor has died well before year 40.

3. **Screening tables and ranking (scripts 05 and 07).** The original ICER for the rule tables, the net monetary benefit ranking and the maps applied the full £474,256 five-year scheme cost to every simulated year. The table footnote in the original said the ICERs were inflated for that reason. The dissertation tables say the scheme cost is annualised over five years, so these calculations now divide the scheme cost by 5 (`mean_scheme_cost_per_year / 5`). The footnote was reworded to match.

4. **Rule B6 in the screening (script 05).** The NI-wide random rule is added to `all_rules` so that all twelve rules are screened in one run on the same simulated arrests. The label `random_across_NI_true` in the table code became `random_across_NI` to match the rule name.

5. **Belfast case study (script 06).** In the original both runs took their rule from `best_lgd_by_nmb_35$rule[[1]]`, which would make them the same rule. The headings and the dissertation's Figure 4.8 describe two different rules, so the first run now uses `random_within_LGD` and the second `lambda_within_LGD`.

6. **Map and plot labels (script 07).** The title "under lambda_across_NI" became "under lambda_within_LGD", and the two map subtitles "Rule: Random across NI" became "Rule: incidence-weighted within LGD (31 responders per LGD)". The data being plotted comes from the within-district incidence run, so the old labels did not match it.

7. **Reading the census file (script 02).** `read.csv()` now has `fileEncoding = "UTF-8-BOM"`, so a byte-order mark at the start of the file cannot change the name of the first column. It makes no difference to a file without one.

8. **Where the tables are saved (script 05).** The two LaTeX tables are written to `outputs/tables/` (created by `00_setup.R`) instead of the working directory.

## New code

- `summarise_5yr()` at the end of script 06 gives the headline numbers for a set of five-year blocks: mean ICER, 2.5% and 97.5% quantiles of the block ICERs, and the share of blocks that are cost-effective at £20,000, £30,000 and £35,000. The original R Markdown had no code that produced the mean and range of the five-year ICERs quoted in the dissertation, so this is a new, short version of that step.
- A comment in script 04 explains that `sim_icer` and `mean_icer` are per-year figures that put the whole five-year scheme cost on every year, and that the ICERs to quote come from `make_five_year_blocks()`.
- Script 01 ends by writing `data/processed/coa_nearest_ambulance.csv` (the original wrote it earlier, before the distances were converted to log-miles) and script 02 checks that the file has the columns it needs.

## Left out

- The first geocoding pass in the station script (`geocode_one()` and `geo_results`), which was not used afterwards, and the unused `nngeo` package.
- `simulate_cairns_qalys()`, an older monthly QALY function that nothing called.
- The combined `allocation_rules_table.tex` chunk. The two separate tables for the within-district and NI-wide rules (`within_lgd_rules_table.tex` and `ni_wide_rules_table.tex`) are still made.
- A list of `exists(...)` checks and a stray `correct_icer` line.
- Packages that were loaded but that nothing in the code calls: `stringr`, `patchwork`, `officer`, `flextable`, `rvg` and `future.apply`.

## Discrete-event simulation (`des/ambulance_handover_des.Rmd`)

The script is in [`original/SOR4001_DES_as_submitted.Rmd`](original/SOR4001_DES_as_submitted.Rmd) as I wrote it. The model, parameters and plots are unchanged. What I changed:

- The NHS workbook is read from `data/raw/` instead of a `file.choose()` prompt.
- The simulations are wrapped in a small `cached()` helper. It runs a simulation and saves the result, or reads the saved result if there is one. The old version had chunks switched on and off by hand with `eval = FALSE`, and the `eval = TRUE` stress run always re-ran.
- Replication counts are set at the top (50 baseline, 10 stress, 8 per sensitivity scenario). `DES_QUICK=1` uses 3, 2 and 2 for a quick check, and `DES_RERUN=1` ignores saved results.
- The last chunk saved `scenario_runs` as `des_stress_run.rds` instead of `stress_run`. The `cached()` helper replaces that chunk.
- The subtitle "Baseline: 10 reps x 30 sim days" did not match the run (50 replications of 60 days), so it no longer gives numbers.
- Removed the unused `tinytex` package, three long dashes in comments, and a stale comment about 15 replications.
