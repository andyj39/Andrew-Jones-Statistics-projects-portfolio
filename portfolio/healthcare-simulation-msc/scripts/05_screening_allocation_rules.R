# 05_screening_allocation_rules.R
#
# Screening run: every allocation rule in every LGD for 20 simulated years, to see which rules
# perform best before spending time on the full 1000-year runs. Includes a single-LGD smoke
# test (Fermanagh) and the tables used in the dissertation.
#
# Needs : scripts 02 to 04
# Makes : results_all_rules_lgd_20, results_within_lgd_20, rule comparison tables (outputs/tables), lgd_ranking_fixed31


# ---- 1. Smoke test: one LGD (Fermanagh), 1000 simulated years, cost-effectiveness plane (slow) ---
df2_200 <- subset_first_sims(df2, 200)

fermanagh_rule <- "lambda_within_LGD"

system.time({
  test_ferm_200 <- run_rule_lgd(
    rule_name = fermanagh_rule,
    target_lgd = "95PP",
    df2_use = df2,
    seed = 123,
    return_sim_level = TRUE,
    max_sims = 1000
  )
})

test_ferm_200$summary
head(test_ferm_200$sim_level)

ferm_5yr_blocks <- make_five_year_blocks(test_ferm_200$sim_level)
ferm_5yr_blocks

threshold_lines <- tibble(
  threshold = c("£20,000", "£30,000", "£35,000"),
  slope = c(20000, 30000, 35000),
  intercept = 0
)

ggplot(ferm_5yr_blocks, aes(x = qalys_5yr, y = total_cost_5yr)) +
  geom_point(alpha = 0.5, colour = "#3FA9E2", size = 2.5) +
  geom_abline(
    data = threshold_lines,
    aes(slope = slope, intercept = intercept, colour = threshold, linetype = threshold),
    linewidth = 0.6
  ) +
  scale_colour_manual(
    name = NULL,
    values = c(
      "£20,000" = "#D55E00",
      "£30,000" = "#0072B2",
      "£35,000" = "#7B3294"
    )
  ) +
  scale_linetype_manual(
    name = NULL,
    values = c(
      "£20,000" = "longdash",
      "£30,000" = "longdash",
      "£35,000" = "longdash"
    )
  ) +
  scale_y_continuous(
    labels = scales::label_dollar(prefix = "£", big.mark = ",")
  ) +
  labs(
    x = "Incremental QALYs gained over 5 years",
    y = "Incremental total cost over 5 years (£)",
    title = "Cost-effectiveness plane: Fermanagh FRs assigned weighted by expected SCAs"
  ) +
  guides(
    colour = guide_legend(nrow = 1),
    linetype = "none"
  ) +
  theme_minimal() +
  theme(
    legend.position = "bottom"
  )

# ---- 2. Screening: all rules x all LGDs, 20 simulated years each ---------------------------
df2_20 <- subset_first_sims(df2, 20)

# The NI-wide random rule (B6) is added here so that all twelve rules are screened in the same run
all_rules <- c(all_rules, "random_across_NI")

results_all_rules_lgd_20 <- bind_rows(lapply(seq_along(all_rules), function(r) {

  rule_name <- all_rules[r]

  bind_rows(lapply(seq_along(lgds), function(i) {
    run_rule_lgd(
      rule_name = rule_name,
      target_lgd = lgds[i],
      df2_use = df2_20,
      seed = 10000 + 100 * r + i,
      return_sim_level = FALSE,
      max_sims = 20
    ) %>%
      dplyr::mutate(rule = rule_name)
  }))

}))

#Summarise across NI:
results_all_rules_summary_20 <- results_all_rules_lgd_20 %>%
  dplyr::group_by(rule) %>%
  dplyr::summarise(
    total_fr_ni = sum(n_vol, na.rm = TRUE),
    total_arrests = sum(n_arrests, na.rm = TRUE),
    mean_arrests_per_year_ni = sum(n_arrests, na.rm = TRUE) / 20,
    mean_lives_saved_per_year_ni = sum(mean_lives_saved_per_year, na.rm = TRUE),
    mean_qalys_gained_per_year_ni = sum(mean_qalys_gained_per_year, na.rm = TRUE),
    mean_survivor_cost_per_year_ni = sum(mean_survivor_cost_per_year, na.rm = TRUE),
    mean_scheme_cost_per_year_ni = sum(mean_scheme_cost_per_year, na.rm = TRUE),
    # scheme cost annualised over its 5-year life, as in the dissertation tables
    mean_total_cost_per_year_ni = sum(mean_survivor_cost_per_year, na.rm = TRUE) +
      sum(mean_scheme_cost_per_year, na.rm = TRUE) / 5,
    mean_ambulance_time = weighted.mean(avg_ambulance_time, w = n_arrests, na.rm = TRUE),
    mean_ambulance_plus_FR_time = weighted.mean(avg_ambulance_plus_FR_time, w = n_arrests, na.rm = TRUE),
    icer_from_means = (sum(mean_survivor_cost_per_year, na.rm = TRUE) +
                         sum(mean_scheme_cost_per_year, na.rm = TRUE) / 5) /
      sum(mean_qalys_gained_per_year, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  dplyr::arrange(icer_from_means)

results_all_rules_summary_20

# ---- 3. LGD comparison under the incidence-weighted within-LGD rule ------------------------
# Best LGD by response time improvement and proportion saved
# Using the lambda_within_LGD rule from the 20-sim screening

lgd_screening <- results_all_rules_lgd_20 %>%
  filter(rule == "lambda_within_LGD") %>%
  mutate(
    rt_improvement     = avg_ambulance_time - avg_ambulance_plus_FR_time,
    rt_improvement_pct = 100 * rt_improvement / avg_ambulance_time,
    prop_saved         = ifelse(mean_arrests_per_year > 0,
                                mean_lives_saved_per_year / mean_arrests_per_year,
                                NA_real_)
  ) %>%
  select(lgd_code, lgd_name,
         mean_arrests_per_year,
         avg_ambulance_time,
         avg_ambulance_plus_FR_time,
         rt_improvement,
         rt_improvement_pct,
         mean_lives_saved_per_year,
         prop_saved,
         mean_qalys_gained_per_year,
         icer_from_means) %>%
  arrange(desc(rt_improvement))

# Top 10 by response time improvement 
cat("=== Top 10 LGDs by absolute response time improvement ===\n")
print(lgd_screening %>% arrange(desc(rt_improvement)) %>%
        select(lgd_name, avg_ambulance_time,
               avg_ambulance_plus_FR_time,
               rt_improvement, rt_improvement_pct) %>%
        head(10), n = 10)

# Top 10 by % response time improvement
cat("\n=== Top 10 LGDs by percentage response time improvement ===\n")
print(lgd_screening %>% arrange(desc(rt_improvement_pct)) %>%
        select(lgd_name, avg_ambulance_time,
               avg_ambulance_plus_FR_time,
               rt_improvement, rt_improvement_pct) %>%
        head(10), n = 10)

# Top 10 by proportion of arrests saved 
cat("\n=== Top 10 LGDs by proportion of arrests saved ===\n")
print(lgd_screening %>% arrange(desc(prop_saved)) %>%
        select(lgd_name, mean_arrests_per_year,
               mean_lives_saved_per_year,
               prop_saved, mean_qalys_gained_per_year) %>%
        head(10), n = 10)

# Full table sorted by prop_saved 
cat("\n=== All 26 LGDs sorted by proportion saved ===\n")
print(lgd_screening %>%
        arrange(desc(prop_saved)) %>%
        select(lgd_name, avg_ambulance_time, rt_improvement,
               prop_saved, mean_qalys_gained_per_year),
      n = 26)

# ---- 4. Within-LGD rules only --------------------------------------------------------------
within_lgd_rules <- c(
  "lambda_within_LGD",
  "lambda_90_area_10_within_LGD",
  "lambda_80_area_20_within_LGD",
  "lambda_x_area_pow_0.25_within_LGD",
  "lambda_x_log_area_within_LGD",
  "random_within_LGD"
)

results_within_lgd_20 <- bind_rows(lapply(seq_along(within_lgd_rules), function(r) {

  rule_name <- within_lgd_rules[r]

  bind_rows(lapply(seq_along(lgds), function(i) {
    run_rule_lgd(
      rule_name = rule_name,
      target_lgd = lgds[i],
      df2_use = df2_20,
      seed = 10000 + 100 * r + i,
      return_sim_level = FALSE,
      max_sims = 20
    ) %>%
      dplyr::mutate(rule = rule_name)
  }))

}))

# Summarise across NI
results_within_lgd_summary_20 <- results_within_lgd_20 %>%
  dplyr::group_by(rule) %>%
  dplyr::summarise(
    total_fr_ni = sum(n_vol, na.rm = TRUE),
    total_arrests = sum(n_arrests, na.rm = TRUE),
    mean_arrests_per_year_ni = sum(n_arrests, na.rm = TRUE) / 20,
    mean_lives_saved_per_year_ni = sum(mean_lives_saved_per_year, na.rm = TRUE),
    mean_qalys_gained_per_year_ni = sum(mean_qalys_gained_per_year, na.rm = TRUE),
    mean_survivor_cost_per_year_ni = sum(mean_survivor_cost_per_year, na.rm = TRUE),
    mean_scheme_cost_per_year_ni = sum(mean_scheme_cost_per_year, na.rm = TRUE),
    # scheme cost annualised over its 5-year life, as in the dissertation tables
    mean_total_cost_per_year_ni = sum(mean_survivor_cost_per_year, na.rm = TRUE) +
      sum(mean_scheme_cost_per_year, na.rm = TRUE) / 5,
    mean_ambulance_time = weighted.mean(avg_ambulance_time, w = n_arrests, na.rm = TRUE),
    mean_ambulance_plus_FR_time = weighted.mean(avg_ambulance_plus_FR_time, w = n_arrests, na.rm = TRUE),
    icer_from_means = (sum(mean_survivor_cost_per_year, na.rm = TRUE) +
                         sum(mean_scheme_cost_per_year, na.rm = TRUE) / 5) /
      sum(mean_qalys_gained_per_year, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  dplyr::arrange(icer_from_means)

results_within_lgd_summary_20

# ---- 5. Tables for the report --------------------------------------------------------------
# TABLE 1: NI-wide allocation rules

rule_labels_ni <- c(
  "lambda_across_NI"       = "Incidence",
  "lambda_90_area_10"      = "90\\% incidence, 10\\% area",
  "lambda_80_area_20"      = "80\\% incidence, 20\\% area",
  "lambda_x_area_pow_0.25" = "Incidence $\\times$ area$^{0.25}$",
  "lambda_x_log_area"      = "Incidence $\\times$ log(area)",
  "random_across_NI"       = "Random"
)

tbl_ni_wide <- results_all_rules_summary_20 %>%
  filter(rule %in% names(rule_labels_ni)) %>%
  transmute(
    `Allocation rule`          = dplyr::recode(rule, !!!rule_labels_ni),
    `Mean QALYs/year`          = round(mean_qalys_gained_per_year_ni, 2),
    `Mean EMS+FR time (mins)`  = round(mean_ambulance_plus_FR_time, 3),
    `ICER (£/QALY)$^\\dagger$` = paste0("\\pounds", formatC(
                                    icer_from_means,
                                    format = "f", digits = 0,
                                    big.mark = ","))
  ) %>%
  arrange(`ICER (£/QALY)$^\\dagger$`)

tbl_ni_wide %>%
  kbl(
    format   = "latex",
    booktabs = TRUE,
    escape   = FALSE,
    caption  = "NI-wide FR allocation rules compared across 20 screening simulations. QALYs and response times are aggregated across all 26 LGDs. Rules are sorted by ICER.",
    label    = "tab:ni_wide_rules"
  ) %>%
  kable_styling(
    latex_options = c("hold_position", "scale_down"),
    font_size     = 10
  ) %>%
  column_spec(1, width = "7cm") %>%
  column_spec(2:4, width = "3cm") %>%
  footnote(
    general = c(
      "Results based on 20 simulated years per rule as a screening exercise.",
      "$^\\\\dagger$ ICERs are indicative screening values (scheme cost annualised over 5 years, 20 simulated years per rule and LGD).",
      "ICER = Incremental Cost-Effectiveness Ratio. QALYs = Quality-Adjusted Life Years."
    ),
    general_title  = "",
    escape         = FALSE,
    threeparttable = TRUE
  ) %>%
  save_kable(file = "outputs/tables/ni_wide_rules_table.tex")

# TABLE 2: Within-LGD allocation rules

rule_labels_lgd <- c(
  "lambda_within_LGD"                 = "Incidence",
  "lambda_90_area_10_within_LGD"      = "90\\% incidence, 10\\% area",
  "lambda_80_area_20_within_LGD"      = "80\\% incidence, 20\\% area",
  "lambda_x_area_pow_0.25_within_LGD" = "Incidence $\\times$ area$^{0.25}$",
  "lambda_x_log_area_within_LGD"      = "Incidence $\\times$ log(area)",
  "random_within_LGD"                 = "Random"
)

tbl_within_lgd <- results_within_lgd_summary_20 %>%
  transmute(
    `Allocation rule`          = dplyr::recode(rule, !!!rule_labels_lgd),
    `Mean QALYs/year`          = round(mean_qalys_gained_per_year_ni, 2),
    `Mean EMS+FR time (mins)`  = round(mean_ambulance_plus_FR_time, 3),
    `ICER (£/QALY)$^\\dagger$` = paste0("\\pounds", formatC(
                                    icer_from_means,
                                    format = "f", digits = 0,
                                    big.mark = ","))
  ) %>%
  arrange(`ICER (£/QALY)$^\\dagger$`)

tbl_within_lgd %>%
  kbl(
    format   = "latex",
    booktabs = TRUE,
    escape   = FALSE,
    caption  = "Within-LGD FR allocation rules compared across 20 screening simulations, with 31 first responders assigned per LGD. QALYs and response times are aggregated across all 26 LGDs. Rules are sorted by ICER.",
    label    = "tab:within_lgd_rules"
  ) %>%
  kable_styling(
    latex_options = c("hold_position", "scale_down"),
    font_size     = 10
  ) %>%
  column_spec(1, width = "7cm") %>%
  column_spec(2:4, width = "3cm") %>%
  footnote(
    general = c(
      "Results based on 20 simulated years per rule as a screening exercise.",
      "$^\\\\dagger$ ICERs are indicative screening values (scheme cost annualised over 5 years, 20 simulated years per rule and LGD).",
      "ICER = Incremental Cost-Effectiveness Ratio. QALYs = Quality-Adjusted Life Years."
    ),
    general_title  = "",
    escape         = FALSE,
    threeparttable = TRUE
  ) %>%
  save_kable(file = "outputs/tables/within_lgd_rules_table.tex")

# ---- 6. Which LGD and rule is best? (net monetary benefit) ---------------------------------
fixed31_rules <- c("lambda_within_LGD", "random_within_LGD")

results_fixed31_lgd_20 <- results_all_rules_lgd_20 %>%
  filter(rule %in% fixed31_rules)

#Note: Mean of simulation net monetary benefit (NMB) is the same as NMB from mean QALYs gained and cost

lgd_ranking_fixed31 <- results_fixed31_lgd_20 %>%
  filter(mean_qalys_gained_per_year > 0.001) %>%
  mutate(
    # scheme cost annualised over its 5-year life
    annual_cost = mean_survivor_cost_per_year + mean_scheme_cost_per_year / 5,
    icer_from_means = annual_cost / mean_qalys_gained_per_year,
    nmb_20000 = 20000 * mean_qalys_gained_per_year - annual_cost,
    nmb_30000 = 30000 * mean_qalys_gained_per_year - annual_cost,
    nmb_35000 = 35000 * mean_qalys_gained_per_year - annual_cost
  )

#Ranking
best_lgd_by_icer <- lgd_ranking_fixed31 %>%
  arrange(icer_from_means)

best_lgd_by_nmb_20 <- lgd_ranking_fixed31 %>%
  arrange(desc(nmb_20000))

best_lgd_by_nmb_30 <- lgd_ranking_fixed31 %>%
  arrange(desc(nmb_30000))

best_lgd_by_nmb_35 <- lgd_ranking_fixed31 %>%
  arrange(desc(nmb_35000))

best_lgd_by_icer
best_lgd_by_nmb_20
best_lgd_by_nmb_30
best_lgd_by_nmb_35
