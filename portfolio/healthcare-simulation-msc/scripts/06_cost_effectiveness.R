# 06_cost_effectiveness.R
#
# Full runs (1000 simulated years) for the cost-effectiveness analysis: all LGDs under the
# within-LGD and NI-wide incidence rules and the NI-wide random rule, five-year blocks, cost-
# effectiveness planes and acceptability curves (CEACs), and the Belfast case study.
#
# Needs : scripts 02 to 05
# Makes : lambda_within_sim, ni_lambda_across_sim, ni_random_sim, five-year block tables, CE planes and CEACs


# ---- 1. All LGDs, 31 responders each, incidence-weighted within LGD (1000 years) -----------
lgds <- sort(unique(zone_count$lgd))

lambda_within_sim <- bind_rows(lapply(seq_along(lgds), function(i) {
  run_rule_lgd(
    rule_name = "lambda_within_LGD",
    target_lgd = lgds[i],
    df2_use = df2,   
    seed = 5000 + i,
    return_sim_level = TRUE,
    max_sims = 1000
  )$sim_level %>%
    mutate(
      rule = "lambda_within_LGD",
      lgd_code = lgds[i]
    )
}))

# ---- 2. NI-wide incidence rule (806 responders), 1000 years --------------------------------
df2_500 <- subset_first_sims(df2, 500)

ni_lambda_across_sim <- bind_rows(lapply(seq_along(lgds), function(i) {
  out <- run_rule_lgd(
    rule_name = "lambda_across_NI",
    target_lgd = lgds[i],
    df2_use = df2,
    seed = 50000 + i,
    return_sim_level = TRUE,
    max_sims = 1000
  )

  out$sim_level %>%
    mutate(
      rule = "lambda_across_NI",
      lgd_code = lgds[i]
    )
}))

#Aggregate to NI level
ni_lambda_across_yearly <- ni_lambda_across_sim %>%
  group_by(sim) %>%
  summarise(
    sim_lives_saved_year = sum(sim_lives_saved_year, na.rm = TRUE),
    sim_qalys_year = sum(sim_qalys_year, na.rm = TRUE),
    sim_survivor_cost_year = sum(sim_survivor_cost_year, na.rm = TRUE),
    sim_scheme_cost_year = sum(sim_scheme_cost_year, na.rm = TRUE),
    sim_total_cost_year = sum(sim_total_cost_year, na.rm = TRUE),
    .groups = "drop"
  )

#Convert to 5 year block
ni_lambda_across_5yr <- make_five_year_blocks(
  ni_lambda_across_yearly,
  scheme_cost_is_already_5yr = TRUE
)

ni_lambda_across_5yr

# ---- 3. Survival and response-time intervals for Fermanagh, Carrickfergus and Belfast ------
# Survival and response time CIs for the 3 focal LGDs
lambda_within_sim %>%
  filter(lgd_code %in% c("95PP", "95HH", "95GG")) %>%
  group_by(lgd_code) %>%
  summarise(
    # EMS response time
    mean_amb      = mean(avg_ambulance_time,         na.rm = TRUE),
    lo_amb        = quantile(avg_ambulance_time,      0.025, na.rm = TRUE),
    hi_amb        = quantile(avg_ambulance_time,      0.975, na.rm = TRUE),
    # EMS + FR response time
    mean_fr       = mean(avg_ambulance_plus_FR_time,  na.rm = TRUE),
    lo_fr         = quantile(avg_ambulance_plus_FR_time, 0.025, na.rm = TRUE),
    hi_fr         = quantile(avg_ambulance_plus_FR_time, 0.975, na.rm = TRUE),
    # EMS survival
    mean_surv_ems = mean(sim_surv_base_year,          na.rm = TRUE),
    lo_surv_ems   = quantile(sim_surv_base_year,      0.025, na.rm = TRUE),
    hi_surv_ems   = quantile(sim_surv_base_year,      0.975, na.rm = TRUE),
    # EMS + FR survival
    mean_surv_fr  = mean(sim_surv_FR_year,            na.rm = TRUE),
    lo_surv_fr    = quantile(sim_surv_FR_year,        0.025, na.rm = TRUE),
    hi_surv_fr    = quantile(sim_surv_FR_year,        0.975, na.rm = TRUE),
    # Lives saved
    mean_lives    = mean(sim_lives_saved_year,        na.rm = TRUE),
    lo_lives      = quantile(sim_lives_saved_year,    0.025, na.rm = TRUE),
    hi_lives      = quantile(sim_lives_saved_year,    0.975, na.rm = TRUE),
    # QALYs
    mean_qalys    = mean(sim_qalys_year,              na.rm = TRUE),
    lo_qalys      = quantile(sim_qalys_year,          0.025, na.rm = TRUE),
    hi_qalys      = quantile(sim_qalys_year,          0.975, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  print(width = Inf)


# ---- 4. NI-wide random rule, 1000 years ----------------------------------------------------
ni_random_sim <- bind_rows(lapply(seq_along(lgds), function(i) {
  out <- run_rule_lgd(
    rule_name = "random_across_NI",
    target_lgd = lgds[i],
    df2_use = df2,
    seed = 50000 + i,
    return_sim_level = TRUE,
    max_sims = 1000
  )

  out$sim_level %>%
    mutate(
      rule = "random_across_NI",
      lgd_code = lgds[i]
    )
}))

#Aggregate to NI level
ni_random_yearly <- ni_random_sim %>%
  group_by(sim) %>%
  summarise(
    sim_lives_saved_year = sum(sim_lives_saved_year, na.rm = TRUE),
    sim_qalys_year = sum(sim_qalys_year, na.rm = TRUE),
    sim_survivor_cost_year = sum(sim_survivor_cost_year, na.rm = TRUE),
    sim_scheme_cost_year = sum(sim_scheme_cost_year, na.rm = TRUE),
    sim_total_cost_year = sum(sim_total_cost_year, na.rm = TRUE),
    .groups = "drop"
  )

#Convert to 5 year block
ni_random_5yr <- make_five_year_blocks(
  ni_random_yearly,
  scheme_cost_is_already_5yr = TRUE
)

ni_random_5yr

# ---- 5. NI-wide cost-effectiveness plane ---------------------------------------------------
threshold_lines <- tibble(
  threshold = c("£20,000", "£30,000", "£35,000"),
  slope = c(20000, 30000, 35000),
  intercept = 0
)

ggplot(ni_lambda_across_5yr, aes(x = qalys_5yr, y = total_cost_5yr)) +
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
    title = "Cost-effectiveness plane: NI FRs assigned weighted by expected SCAs"
  ) +
  guides(
    colour = guide_legend(nrow = 1),
    linetype = "none"
  ) +
  theme_minimal() +
  theme(
    legend.position = "bottom"
  )

# ---- 6. NI-wide acceptability curves -------------------------------------------------------
wtp_grid <- seq(0, 50000, by = 1000)

ni_lambda_ceac <- tibble(
  wtp = wtp_grid,
  prob_cost_effective = sapply(wtp_grid, function(k) {
    mean((k * ni_lambda_across_5yr$qalys_5yr -
            ni_lambda_across_5yr$total_cost_5yr) > 0,
         na.rm = TRUE)
  })
)

ni_random_ceac <- tibble(
  wtp = wtp_grid,
  prob_cost_effective = sapply(wtp_grid, function(k) {
    mean((k * ni_random_5yr$qalys_5yr -
            ni_random_5yr$total_cost_5yr) > 0,
         na.rm = TRUE)
  })
)


# Combine the two CEAC datasets
ceac_plot <- bind_rows(
  ni_random_ceac %>%
    mutate(series = "Base case"),
  ni_lambda_ceac %>%
    mutate(series = "Scenario 2")
)

# Colours
col_before <- "green"
col_after  <- "purple"

# Force threshold legend order
band_levels <- c(
  "New NICE willingness-to-pay threshold",
  "Old NICE willingness-to-pay threshold"
)

# Threshold regions:
# 20k–25k  = NICE up to Apr 2026 only
# 25k–30k  = overlap, shown as mixed/patterned
# 30k–35k  = NICE after Apr 2026 only
region_left <- tibble(
  xmin = 20000, xmax = 25000,
  ymin = 0, ymax = 1,
  band = factor("Old NICE willingness-to-pay threshold", levels = band_levels)
)

region_mid <- tibble(
  xmin = 25000, xmax = 30000,
  ymin = 0, ymax = 1
)

region_right <- tibble(
  xmin = 30000, xmax = 35000,
  ymin = 0, ymax = 1,
  band = factor("New NICE willingness-to-pay threshold", levels = band_levels)
)

# Dummy data just to create a clean threshold legend
threshold_legend <- tibble(
  xmin = c(0, 0),
  xmax = c(0, 0),
  ymin = c(0, 0),
  ymax = c(0, 0),
  band = factor(
    c(
      "New NICE willingness-to-pay threshold",
      "Old NICE willingness-to-pay threshold"
    ),
    levels = band_levels
  )
)

ggplot() +
  # Left region: old threshold only
  geom_rect(
    data = region_left,
    aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax, fill = band),
    inherit.aes = FALSE,
    alpha = 0.20,
    colour = NA,
    show.legend = FALSE
  ) +

  # Middle overlap region: mixed colours with diagonal stripes
  ggpattern::geom_rect_pattern(
    data = region_mid,
    aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax),
    inherit.aes = FALSE,
    fill = col_before,
    alpha = 0.20,
    pattern = "stripe",
    pattern_angle = 45,
    pattern_spacing = 0.03,
    pattern_density = 0.45,
    pattern_fill = col_after,
    pattern_colour = col_after,
    pattern_alpha = 0.20,
    colour = NA,
    show.legend = FALSE
  ) +

  # Right region: new threshold only
  geom_rect(
    data = region_right,
    aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax, fill = band),
    inherit.aes = FALSE,
    alpha = 0.20,
    colour = NA,
    show.legend = FALSE
  ) +

  # Dummy layer for proper threshold legend
  geom_rect(
    data = threshold_legend,
    aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax, fill = band),
    inherit.aes = FALSE,
    alpha = 0.20,
    colour = NA
  ) +

  # CEAC lines
  geom_line(
    data = ceac_plot,
    aes(x = wtp, y = prob_cost_effective, colour = series, linetype = series),
    linewidth = 1.5,
    alpha = 0.95
  ) +

  scale_y_continuous(
    limits = c(0, 1),
    labels = label_percent(accuracy = 1),
    expand = expansion(mult = c(0, 0.02))
  ) +
  scale_x_continuous(
    labels = label_dollar(prefix = "£", big.mark = ","),
    breaks = seq(10000, max(ceac_plot$wtp, na.rm = TRUE), by = 5000),
    expand = expansion(mult = c(0, 0.03))
  ) +
  coord_cartesian(xlim = c(10000, NA)) +

  scale_colour_manual(
    name = "Curve",
    values = c(
      "Base case" = "cyan",
      "Scenario 2" = "#FFD700"
    ),
    labels = c(
      "Base case" = "FRs randomly distributed",
      "Scenario 2" = "FRs distributed weighted by expected annual SCAs"
    )
  ) +
  scale_linetype_manual(
    name = "Curve",
    values = c(
      "Base case" = "solid",
      "Scenario 2" = "64"
    ),
    labels = c(
      "Base case" = "FRs randomly distributed",
      "Scenario 2" = "FRs distributed weighted by expected annual SCAs"
    )
  ) +
  scale_fill_manual(
    name = "Threshold region",
    limits = band_levels,
    values = c(
      "New NICE willingness-to-pay threshold" = col_after,
      "Old NICE willingness-to-pay threshold" = col_before
    )
  ) +

  labs(
    x = "Willingness-to-pay threshold (£ per QALY)",
    y = "Probability cost-effective",
    colour = "Curve",
    linetype = "Curve",
    fill = "Threshold region"
  ) +

  guides(
    linetype = "none"
  ) +

  theme_minimal(base_size = 13) +
  theme(
    plot.title = element_text(face = "bold", size = 16),
    plot.subtitle = element_text(size = 11, colour = "grey30"),
    axis.title = element_text(face = "bold"),
    legend.position = "bottom",
    legend.box = "vertical",
    legend.title = element_text(size = 10),
    legend.text = element_text(size = 8.5),
    legend.box.spacing = grid::unit(0.1, "lines"),
    legend.spacing.y = grid::unit(0.1, "lines"),
    legend.margin = margin(0, 0, 0, 0),
    legend.box.margin = margin(0, 0, 0, 0),
    panel.grid.minor = element_blank(),
    panel.grid.major.x = element_blank()
  )

# ---- 7. Belfast case study, 1000 years per rule --------------------------------------------
# Belfast case study (the LGD ranked best by net monetary benefit at GBP 35,000/QALY in script 05).
# Two allocation rules are compared, both with 31 responders in the LGD:
#   base case  = responders placed at random within the LGD
#   scenario 2 = responders placed in proportion to expected arrests (lambda) within the LGD
best_lgd      <- best_lgd_by_nmb_35$lgd_code[[1]]
best_lgd_name <- best_lgd_by_nmb_35$lgd_name[[1]]

best_lgd_ce <- run_rule_lgd(
  rule_name = "random_within_LGD",
  target_lgd = best_lgd,
  df2_use = df2,
  seed = 4001,
  return_sim_level = TRUE,
  max_sims = 1000
)

best_lgd_ce$summary
head(best_lgd_ce$sim_level)

#Convert to 5 year block
best_lgd_5yr <- make_five_year_blocks(
  best_lgd_ce$sim_level,
  scheme_cost_is_already_5yr = TRUE
)

best_lgd_2_ce <- run_rule_lgd(
  rule_name = "lambda_within_LGD",
  target_lgd = best_lgd,
  df2_use = df2,
  seed = 4001,
  return_sim_level = TRUE,
  max_sims = 1000
)

best_lgd_2_ce$summary
head(best_lgd_2_ce$sim_level)

#Convert to 5 year block
best_lgd_5yr_2 <- make_five_year_blocks(
  best_lgd_2_ce$sim_level,
  scheme_cost_is_already_5yr = TRUE
)

best_lgd_5yr
best_lgd_5yr_2


# ---- 8. Belfast headline numbers -----------------------------------------------------------
# Headline numbers for a set of 5-year blocks: mean ICER, 2.5% and 97.5% quantiles of the block ICERs,
# and the proportion of blocks that are cost-effective at each threshold (the CEAC read at that threshold).
summarise_5yr <- function(blocks, label) {
  blocks %>%
    dplyr::summarise(
      scenario = label,
      n_5yr_blocks = dplyr::n(),
      mean_icer = mean(icer_5yr, na.rm = TRUE),
      icer_2.5pct = quantile(icer_5yr, 0.025, na.rm = TRUE, names = FALSE),
      icer_97.5pct = quantile(icer_5yr, 0.975, na.rm = TRUE, names = FALSE),
      prob_ce_20k = mean(20000 * qalys_5yr - total_cost_5yr > 0, na.rm = TRUE),
      prob_ce_30k = mean(30000 * qalys_5yr - total_cost_5yr > 0, na.rm = TRUE),
      prob_ce_35k = mean(35000 * qalys_5yr - total_cost_5yr > 0, na.rm = TRUE)
    )
}

belfast_summary <- dplyr::bind_rows(
  summarise_5yr(best_lgd_5yr,   paste(best_lgd_name, "- random within LGD")),
  summarise_5yr(best_lgd_5yr_2, paste(best_lgd_name, "- incidence within LGD"))
)
belfast_summary


# ---- 9. Belfast cost-effectiveness plane ---------------------------------------------------
threshold_lines <- tibble(
  threshold = c("£20,000", "£30,000", "£35,000"),
  slope = c(20000, 30000, 35000),
  intercept = 0
)

ggplot(best_lgd_5yr, aes(x = qalys_5yr, y = total_cost_5yr)) +
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
    title = "Cost-effectiveness plane: Belfast FRs randomly assigned"
  ) +
  guides(
    colour = guide_legend(nrow = 1),
    linetype = "none"
  ) +
  theme_minimal() +
  theme(
    legend.position = "bottom"
  )

# ---- 10. Belfast acceptability curves ------------------------------------------------------
best_lgd_ceac <- tibble(
  wtp = wtp_grid,
  prob_cost_effective = sapply(wtp_grid, function(k) {
    mean((k * best_lgd_5yr$qalys_5yr -
            best_lgd_5yr$total_cost_5yr) > 0,
         na.rm = TRUE)
  })
)

best_lgd_2_ceac <- tibble(
  wtp = wtp_grid,
  prob_cost_effective = sapply(wtp_grid, function(k) {
    mean((k * best_lgd_5yr_2$qalys_5yr -
            best_lgd_5yr_2$total_cost_5yr) > 0,
         na.rm = TRUE)
  })
)

# Combine the two CEAC datasets
ceac_plot <- bind_rows(
  best_lgd_ceac %>%
    mutate(series = "Base case"),
  best_lgd_2_ceac %>%
    mutate(series = "Scenario 2")
)

# Colours
col_before <- "green"
col_after  <- "purple"

# Force threshold legend order
band_levels <- c(
  "New NICE willingness-to-pay threshold",
  "Old NICE willingness-to-pay threshold"
)

# Threshold regions:
# 20k–25k  = NICE up to Apr 2026 only
# 25k–30k  = overlap, shown as mixed/patterned
# 30k–35k  = NICE after Apr 2026 only
region_left <- tibble(
  xmin = 20000, xmax = 25000,
  ymin = 0, ymax = 1,
  band = factor("Old NICE willingness-to-pay threshold", levels = band_levels)
)

region_mid <- tibble(
  xmin = 25000, xmax = 30000,
  ymin = 0, ymax = 1
)

region_right <- tibble(
  xmin = 30000, xmax = 35000,
  ymin = 0, ymax = 1,
  band = factor("New NICE willingness-to-pay threshold", levels = band_levels)
)

# Dummy data just to create a clean threshold legend
threshold_legend <- tibble(
  xmin = c(0, 0),
  xmax = c(0, 0),
  ymin = c(0, 0),
  ymax = c(0, 0),
  band = factor(
    c(
      "New NICE willingness-to-pay threshold",
      "Old NICE willingness-to-pay threshold"
    ),
    levels = band_levels
  )
)

ggplot() +
  # Left region: old threshold only
  geom_rect(
    data = region_left,
    aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax, fill = band),
    inherit.aes = FALSE,
    alpha = 0.20,
    colour = NA,
    show.legend = FALSE
  ) +

  # Middle overlap region: mixed colours with diagonal stripes
  ggpattern::geom_rect_pattern(
    data = region_mid,
    aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax),
    inherit.aes = FALSE,
    fill = col_before,
    alpha = 0.20,
    pattern = "stripe",
    pattern_angle = 45,
    pattern_spacing = 0.03,
    pattern_density = 0.45,
    pattern_fill = col_after,
    pattern_colour = col_after,
    pattern_alpha = 0.20,
    colour = NA,
    show.legend = FALSE
  ) +

  # Right region: new threshold only
  geom_rect(
    data = region_right,
    aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax, fill = band),
    inherit.aes = FALSE,
    alpha = 0.20,
    colour = NA,
    show.legend = FALSE
  ) +

  # Dummy layer for proper threshold legend
  geom_rect(
    data = threshold_legend,
    aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax, fill = band),
    inherit.aes = FALSE,
    alpha = 0.20,
    colour = NA
  ) +

  # CEAC lines
  geom_line(
    data = ceac_plot,
    aes(x = wtp, y = prob_cost_effective, colour = series, linetype = series),
    linewidth = 1.5,
    alpha = 0.95
  ) +

  scale_y_continuous(
    limits = c(0, 1),
    labels = label_percent(accuracy = 1),
    expand = expansion(mult = c(0, 0.02))
  ) +
  scale_x_continuous(
    labels = label_dollar(prefix = "£", big.mark = ","),
    breaks = seq(10000, max(ceac_plot$wtp, na.rm = TRUE), by = 5000),
    expand = expansion(mult = c(0, 0.03))
  ) +
  coord_cartesian(xlim = c(10000, NA)) +

  scale_colour_manual(
    name = "Curve",
    values = c(
      "Base case" = "cyan",
      "Scenario 2" = "#FFD700"
    ),
    labels = c(
      "Base case" = "FRs randomly distributed",
      "Scenario 2" = "FRs distributed weighted by expected annual SCAs"
    )
  ) +
  scale_linetype_manual(
    name = "Curve",
    values = c(
      "Base case" = "solid",
      "Scenario 2" = "64"
    ),
    labels = c(
      "Base case" = "FRs randomly distributed",
      "Scenario 2" = "FRs distributed weighted by expected annual SCAs"
    )
  ) +
  scale_fill_manual(
    name = "Threshold region",
    limits = band_levels,
    values = c(
      "New NICE willingness-to-pay threshold" = col_after,
      "Old NICE willingness-to-pay threshold" = col_before
    )
  ) +

  labs(
    x = "Willingness-to-pay threshold (£ per QALY)",
    y = "Probability cost-effective",
    colour = "Curve",
    linetype = "Curve",
    fill = "Threshold region"
  ) +

  guides(
    linetype = "none"
  ) +

  theme_minimal(base_size = 13) +
  theme(
    plot.title = element_text(face = "bold", size = 16),
    plot.subtitle = element_text(size = 11, colour = "grey30"),
    axis.title = element_text(face = "bold"),
    legend.position = "bottom",
    legend.box = "vertical",
    legend.title = element_text(size = 10),
    legend.text = element_text(size = 8.5),
    legend.box.spacing = grid::unit(0.1, "lines"),
    legend.spacing.y = grid::unit(0.1, "lines"),
    legend.margin = margin(0, 0, 0, 0),
    legend.box.margin = margin(0, 0, 0, 0),
    panel.grid.minor = element_blank(),
    panel.grid.major.x = element_blank()
  )
