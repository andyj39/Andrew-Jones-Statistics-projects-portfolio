# 07_maps_and_plots.R
#
# LGD-level summaries, QALYs against population and area, and maps of responders, QALYs gained
# and ICERs by LGD.
#
# Needs : scripts 02 to 06
# Makes : plots (shown on screen, not saved)


# ---- 1. LGD summary and 3D plot ------------------------------------------------------------
#LGD level summary of lambda across NI
lambda_within_summ <- lambda_within_sim %>%
  group_by(lgd_code, lgd_name) %>%
  summarise(
    mean_lives_saved_per_year = mean(sim_lives_saved_year, na.rm = TRUE),
    mean_qalys_gained_per_year = mean(sim_qalys_year, na.rm = TRUE),
    mean_survivor_cost_per_year = mean(sim_survivor_cost_year, na.rm = TRUE),
    mean_scheme_cost_per_year = mean(sim_scheme_cost_year, na.rm = TRUE),
    mean_total_cost_per_year = mean(sim_total_cost_year, na.rm = TRUE),
    mean_icer = mean(sim_icer, na.rm = TRUE),
    # scheme cost annualised over its 5-year life
    icer_from_means = (mean(sim_survivor_cost_year, na.rm = TRUE) +
                         mean(sim_scheme_cost_year, na.rm = TRUE) / 5) /
      mean(sim_qalys_year, na.rm = TRUE),
    mean_arrests_per_year = mean(n_arrests, na.rm = TRUE),
    mean_ambulance_time = mean(avg_ambulance_time, na.rm = TRUE),
    mean_ambulance_plus_FR_time = mean(avg_ambulance_plus_FR_time, na.rm = TRUE),
    n_vol = mean(n_vol, na.rm = TRUE),
    .groups = "drop"
  )

#Build LGD info again
lgd_meta <- zone_count %>%
  st_drop_geometry() %>%
  group_by(lgd, lgd_name) %>%
  summarise(
    lgd_population = sum(count, na.rm = TRUE),
    .groups = "drop"
  )

lgd_area <- NI_shapefile %>%
  st_make_valid() %>%
  left_join(
    zone_values %>%
      select(zone_code, lgd, lgd_name) %>%
      distinct(),
    by = "zone_code"
  ) %>%
  filter(!is.na(lgd)) %>%
  group_by(lgd, lgd_name) %>%
  summarise(.groups = "drop") %>%
  mutate(
    lgd_area_km2 = as.numeric(st_area(geometry)) / 1e6
  ) %>%
  st_drop_geometry() %>%
  select(lgd, lgd_name, lgd_area_km2)

lgd_meta <- lgd_meta %>%
  left_join(lgd_area, by = c("lgd", "lgd_name"))

lgd_meta

#Getting FR count for the lambda rule again (just double checking)

rule_to_plot <- "lambda_within_lgd"

fr_lgd <- fr_alloc_all_rules %>%
  filter(rule == rule_to_plot) %>%
   group_by(rule, lgd, lgd_name) %>%
  summarise(
    total_fr_lgd = sum(fr_target, na.rm = TRUE),
    .groups = "drop"
  )

#Build LGD master plotting table
plot_lgd_master <- lambda_within_summ %>%
  left_join(
    lgd_meta,
    by = c("lgd_code" = "lgd", "lgd_name")
  ) %>%
  left_join(
    fr_lgd,
    by = c("lgd_code" = "lgd", "lgd_name")
  )

#3d plot
library(plotly)

plot_ly(
  data = plot_lgd_master,
  x = ~lgd_population,
  y = ~lgd_area_km2,
  z = ~mean_qalys_gained_per_year,
  type = "scatter3d",
  mode = "markers+text",
  text = ~lgd_name,
  hovertemplate = paste(
    "<b>%{text}</b><br>",
    "Population: %{x}<br>",
    "Area (km²): %{y:.1f}<br>",
    "Mean QALYs/year: %{z:.2f}<extra></extra>"
  ),
  marker = list(size = 5)
) %>%
  layout(
    scene = list(
      xaxis = list(title = "Population"),
      yaxis = list(title = "Area (km²)"),
      zaxis = list(title = "Mean QALYs gained per year")
    ),
    title = "Population, area, and QALYs gained by LGD under lambda_within_LGD"
  )

# ---- 2. QALYs against population and area --------------------------------------------------
ggplot(plot_lgd_master, aes(x = lgd_population, y = mean_qalys_gained_per_year, label = lgd_name)) +
  geom_point(size = 3) +
  geom_text(nudge_y = 0.4, size = 3) +
  labs(
    x = "LGD population",
    y = "Mean QALYs gained per year",
    title = "Population and QALYs gained by LGD"
  ) +
  theme_minimal()

#Area vs QALYs

ggplot(plot_lgd_master, aes(x = lgd_area_km2, y = mean_qalys_gained_per_year, label = lgd_name)) +
  geom_point(size = 3) +
  geom_text(nudge_y = 0.4, size = 3) +
  labs(
    x = "LGD area (km²)",
    y = "Mean QALYs gained per year",
    title = "Area and QALYs gained by LGD"
  ) +
  theme_minimal()

# ---- 3. Responders by LGD under the NI-wide incidence rule ---------------------------------
# FR distribution under NI-wide incidence rule
fr_alloc_all_rules %>%
  filter(rule == "lambda_across_NI") %>%
  group_by(lgd, lgd_name) %>%
  summarise(total_fr = sum(fr_target, na.rm = TRUE), .groups = "drop") %>%
  arrange(desc(total_fr)) %>%
  print(n = 26)

# ---- 4. Maps -------------------------------------------------------------------------------
lgd_sf <- NI_shapefile %>%
  st_make_valid() %>%
  left_join(
    zone_values %>%
      select(zone_code, lgd, lgd_name) %>%
      distinct(),
    by = "zone_code"
  ) %>%
  filter(!is.na(lgd)) %>%
  group_by(lgd, lgd_name) %>%
  summarise(.groups = "drop") %>%
  st_make_valid()

#LGD level summary of lambda across NI
ni_lambda_lgd <- ni_lambda_across_sim %>%
  group_by(lgd_code, lgd_name) %>%
  summarise(
    mean_lives_saved_per_year = mean(sim_lives_saved_year, na.rm = TRUE),
    mean_qalys_gained_per_year = mean(sim_qalys_year, na.rm = TRUE),
    mean_survivor_cost_per_year = mean(sim_survivor_cost_year, na.rm = TRUE),
    mean_scheme_cost_per_year = mean(sim_scheme_cost_year, na.rm = TRUE),
    mean_total_cost_per_year = mean(sim_total_cost_year, na.rm = TRUE),
    mean_icer = mean(sim_icer, na.rm = TRUE),
    icer_from_means = (mean(sim_survivor_cost_year, na.rm = TRUE) +
                         mean(sim_scheme_cost_year, na.rm = TRUE) / 5) /
      mean(sim_qalys_year, na.rm = TRUE),
    mean_arrests_per_year = mean(n_arrests, na.rm = TRUE),
    mean_ambulance_time = mean(avg_ambulance_time, na.rm = TRUE),
    mean_ambulance_plus_FR_time = mean(avg_ambulance_plus_FR_time, na.rm = TRUE),
    n_vol = mean(n_vol, na.rm = TRUE),
    .groups = "drop"
  )


#Getting FR count for the lambda rule again

rule_to_plot <- "lambda_across_NI"

fr_lgd <- fr_alloc_all_rules %>%
  filter(rule == rule_to_plot) %>%
   group_by(rule, lgd, lgd_name) %>%
  summarise(
    total_fr_lgd = sum(fr_target, na.rm = TRUE),
    .groups = "drop"
  )

#Build LGD master plotting table
plot_lgd_master_maps <- ni_lambda_lgd %>%
  left_join(
    lgd_meta,
    by = c("lgd_code" = "lgd", "lgd_name")
  ) %>%
  left_join(
    fr_lgd,
    by = c("lgd_code" = "lgd", "lgd_name")
  )

map1_sf <- lgd_sf %>%
  left_join(
    plot_lgd_master_maps %>% select(lgd_code, lgd_name, total_fr_lgd),
    by = c("lgd" = "lgd_code", "lgd_name")
  )

ggplot(map1_sf) +
  geom_sf(aes(fill = total_fr_lgd), colour = "white", linewidth = 0.2) +
  scale_fill_viridis_c(name = "FRs") +
  labs(
    title = "Number of first responders by LGD"
  ) +
  theme_minimal()

map2_sf <- lgd_sf %>%
  left_join(
    plot_lgd_master %>% select(lgd_code, lgd_name, mean_qalys_gained_per_year),
    by = c("lgd" = "lgd_code", "lgd_name")
  )

ggplot(map2_sf) +
  geom_sf(aes(fill = mean_qalys_gained_per_year), colour = "white", linewidth = 0.2) +
  scale_fill_viridis_c(name = "Mean QALYs/year") +
  labs(
    title = "Mean QALYs gained per year by LGD",
    subtitle = "Rule: incidence-weighted within LGD (31 responders per LGD)"
  ) +
  theme_minimal()



map3_sf <- lgd_sf %>%
  left_join(
    plot_lgd_master %>% select(lgd_code, lgd_name, icer_from_means),
    by = c("lgd" = "lgd_code", "lgd_name")
  )

ggplot(map3_sf) +
  geom_sf(aes(fill = pmin(icer_from_means, 50000)), colour = "white", linewidth = 0.2) +
  scale_fill_viridis_c(
    name = "ICER (£/QALY)",
    labels = scales::label_dollar(prefix = "£", big.mark = ","),
    na.value = "grey80"
  ) +
  labs(
    title = "Cost-effectiveness by LGD",
    subtitle = "Rule: incidence-weighted within LGD (capped at £50,000/QALY)"
  ) +
  theme_minimal()
