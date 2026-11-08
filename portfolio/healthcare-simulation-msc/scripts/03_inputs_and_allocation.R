# 03_inputs_and_allocation.R
#
# Life tables, neurological-state probabilities, utilities and costs, Markov constants, the
# twelve first-responder (FR) allocation rules, and a bank of random home locations inside
# each Data Zone.
#
# Needs : script 02 objects, life-table and shapefile paths
# Makes : life_table_yearly, alloc_base, fr_alloc_all_rules, zone_point_bank, cost and utility inputs


# ---- 1. NI life tables ---------------------------------------------------------------------
# Male table: A:F
male_life <- read_excel(NI_lifetable_path
  ,
  sheet = "2021-2023",
  range = "A7:F107",
  col_names = c("age", "mx", "qx", "lx", "dx", "ex")
) %>%
  mutate(gender = "Male")

# Female table: H:M
female_life <- read_excel(
  NI_lifetable_path,
  sheet = "2021-2023",
  range = "H7:M107",
  col_names = c("age", "mx", "qx", "lx", "dx", "ex")
) %>%
  mutate(gender = "Female")

# Combine into one tidy table
life_table_raw <- bind_rows(male_life, female_life) %>%
  select(age, gender, ex, qx)

life_table_raw

life_table_raw <- bind_rows(male_life, female_life) %>%
  transmute(
    age = as.numeric(age),
    gender,
    remaining_le = as.numeric(ex),
    year_surv_rate = as.numeric(1 - qx)
  )

life_table_yearly <- life_table_raw %>%
  transmute(
    age = as.integer(age),
    gender = case_when(
      gender == "Female" ~ "1 (Female)",
      gender == "Male" ~ "2 (Male)",
      TRUE ~ as.character(gender)),
    year_surv_rate = year_surv_rate)%>%
  distinct(age, gender, .keep_all = TRUE)

life_table_band <- life_table_raw %>%
  mutate(
    age_band = case_when(
      age >= 0  & age <= 4  ~ "1 (0–4 years)",
      age >= 5  & age <= 9  ~ "2 (5–9 years)",
      age >= 10 & age <= 14 ~ "3 (10–14 years)",
      age >= 15 & age <= 19 ~ "4 (15–19 years)",
      age >= 20 & age <= 24 ~ "5 (20–24 years)",
      age >= 25 & age <= 29 ~ "6 (25–29 years)",
      age >= 30 & age <= 34 ~ "7 (30–34 years)",
      age >= 35 & age <= 39 ~ "8 (35–39 years)",
      age >= 40 & age <= 44 ~ "9 (40–44 years)",
      age >= 45 & age <= 49 ~ "10 (45–49 years)",
      age >= 50 & age <= 54 ~ "11 (50–54 years)",
      age >= 55 & age <= 59 ~ "12 (55–59 years)",
      age >= 60 & age <= 64 ~ "13 (60–64 years)",
      age >= 65 & age <= 69 ~ "14 (65–69 years)",
      age >= 70 & age <= 74 ~ "15 (70–74 years)",
      age >= 75 & age <= 79 ~ "16 (75–79 years)",
      age >= 80 & age <= 84 ~ "17 (80–84 years)",
      age >= 85 & age <= 89 ~ "18 (85–89 years)",
      age >= 90             ~ "19 (90+ years)"
    ),
    gender = case_when(
      gender == "Female" ~ "1 (Female)",
      gender == "Male"   ~ "2 (Male)"
    )
  ) %>%
  group_by(age_band, gender) %>%
  summarise(
    remaining_le = mean(remaining_le, na.rm = TRUE),
    year_surv_rate,
    .groups = "drop"
  )

#Joining onto the main data

#comparison <- comparison %>%
  #left_join(life_table_band, by = c("age_band", "gender"))

# ---- 2. First-responder allocation rules (NI-wide and 31 per LGD) --------------------------
zone_count <- zone_values %>%
  select("zone_code", "data_zone", "count", "lgd", "lgd_name")

total_vol_ni <- 806   # 31 x 26 LGDs

NI_shapefile <- st_read(NI_shapefile_path)

NI_shapefile <- NI_shapefile %>%
  rename("zone_code" = "DZ2021_cd")

# Base table
alloc_base <- zone_values %>%
  ungroup() %>%
  left_join(
    NI_shapefile %>%
      st_drop_geometry() %>%
      select(zone_code, Area_ha),
    by = "zone_code"
  ) %>%
  mutate(
    area_km2 = Area_ha / 100,
    lambda_std = lambda / sum(lambda, na.rm = TRUE),
    area_std   = area_km2 / sum(area_km2, na.rm = TRUE)
  )

# Helper: NI-wide total allocation 
make_alloc_ni <- function(data, score_var, rule_name, total_vol_ni = 806) {
  out <- data %>%
    mutate(
      score = {{ score_var }},
      raw_target = total_vol_ni * score / sum(score, na.rm = TRUE),
      fr_target = floor(raw_target),
      remainder = raw_target - fr_target,
      rule = rule_name
    )

  n_left <- total_vol_ni - sum(out$fr_target, na.rm = TRUE)

  if (n_left > 0) {
    add_idx <- order(out$remainder, decreasing = TRUE)[1:n_left]
    out$fr_target[add_idx] <- out$fr_target[add_idx] + 1
  }

  out
}

# Helper: 31 within each LGD 
make_alloc_lgd <- function(data, score_var, rule_name, fr_per_lgd = 31) {
  data %>%
    group_by(lgd) %>%
    mutate(
      score = {{ score_var }},
      raw_target = fr_per_lgd * score / sum(score, na.rm = TRUE),
      fr_target = floor(raw_target),
      remainder = raw_target - fr_target
    ) %>%
    group_modify(~{
      d <- .x
      n_left <- fr_per_lgd - sum(d$fr_target, na.rm = TRUE)
      if (n_left > 0) {
        add_idx <- order(d$remainder, decreasing = TRUE)[1:n_left]
        d$fr_target[add_idx] <- d$fr_target[add_idx] + 1
      }
      d
    }) %>%
    ungroup() %>%
    mutate(rule = rule_name)
}

# NI-wide exploratory rules 
fr_alloc_lambda_across_NI <- make_alloc_ni(
  alloc_base,
  score_var = lambda,
  rule_name = "lambda_across_NI",
  total_vol_ni = total_vol_ni
)

fr_alloc_lambda_area10 <- make_alloc_ni(
  alloc_base,
  score_var = 0.9 * lambda_std + 0.1 * area_std,
  rule_name = "lambda_90_area_10",
  total_vol_ni = total_vol_ni
)

fr_alloc_lambda_area20 <- make_alloc_ni(
  alloc_base,
  score_var = 0.8 * lambda_std + 0.2 * area_std,
  rule_name = "lambda_80_area_20",
  total_vol_ni = total_vol_ni
)

fr_alloc_lambda_area025 <- make_alloc_ni(
  alloc_base,
  score_var = lambda * (area_km2 ^ 0.25),
  rule_name = "lambda_x_area_pow_0.25",
  total_vol_ni = total_vol_ni
)

fr_alloc_lambda_logarea <- make_alloc_ni(
  alloc_base,
  score_var = lambda * log1p(area_km2),
  rule_name = "lambda_x_log_area",
  total_vol_ni = total_vol_ni
)

# Fixed 31 per LGD using lambda
fr_alloc_lambda_within_LGD <- make_alloc_lgd(
  alloc_base,
  score_var = lambda,
  rule_name = "lambda_within_LGD",
  fr_per_lgd = 31
)

# Fixed 31 per LGD using lambda + area 
fr_alloc_lambda_area10_within_LGD <- make_alloc_lgd(
  alloc_base,
  score_var = 0.9 * lambda_std + 0.1 * area_std,
  rule_name = "lambda_90_area_10_within_LGD",
  fr_per_lgd = 31
)

fr_alloc_lambda_area20_within_LGD <- make_alloc_lgd(
  alloc_base,
  score_var = 0.8 * lambda_std + 0.2 * area_std,
  rule_name = "lambda_80_area_20_within_LGD",
  fr_per_lgd = 31
)

fr_alloc_lambda_area025_within_LGD <- make_alloc_lgd(
  alloc_base,
  score_var = lambda * (area_km2 ^ 0.25),
  rule_name = "lambda_x_area_pow_0.25_within_LGD",
  fr_per_lgd = 31
)

fr_alloc_lambda_logarea_within_LGD <- make_alloc_lgd(
  alloc_base,
  score_var = lambda * log1p(area_km2),
  rule_name = "lambda_x_log_area_within_LGD",
  fr_per_lgd = 31
)

# Fixed 31 per LGD random/equal 
fr_alloc_random_within_LGD <- alloc_base %>%
  group_by(lgd) %>%
  mutate(
    score = 1,
    raw_target = 31 * score / sum(score, na.rm = TRUE),
    fr_target = floor(raw_target),
    remainder = raw_target - fr_target
  ) %>%
  group_modify(~{
    d <- .x
    n_left <- 31 - sum(d$fr_target, na.rm = TRUE)
    if (n_left > 0) {
      add_idx <- sample(seq_len(nrow(d)), size = n_left)
      d$fr_target[add_idx] <- d$fr_target[add_idx] + 1
    }
    d
  }) %>%
  ungroup() %>%
  mutate(rule = "random_within_LGD")


# Combine all 
fr_alloc_all_rules <- bind_rows(
  fr_alloc_lambda_across_NI,
  fr_alloc_lambda_area10,
  fr_alloc_lambda_area20,
  fr_alloc_lambda_area025,
  fr_alloc_lambda_logarea,
  fr_alloc_lambda_within_LGD,
  fr_alloc_lambda_area10_within_LGD,
  fr_alloc_lambda_area20_within_LGD,
  fr_alloc_lambda_area025_within_LGD,
  fr_alloc_lambda_logarea_within_LGD,
  fr_alloc_random_within_LGD
)

fr_alloc_all_rules %>%
  group_by(rule) %>%
  summarise(total_fr = sum(fr_target, na.rm = TRUE), .groups = "drop")

fr_alloc_all_rules %>%
  group_by(rule, lgd, lgd_name) %>%
  summarise(total_fr_lgd = sum(fr_target, na.rm = TRUE), .groups = "drop") %>%
  arrange(rule, desc(total_fr_lgd))

fr_alloc_all_rules %>%
  filter(grepl("within_LGD", rule)) %>%
  group_by(rule, lgd, lgd_name) %>%
  summarise(total_fr_lgd = sum(fr_target, na.rm = TRUE), .groups = "drop") %>%
  arrange(rule, lgd)

fixed_lgd_rules <- c(
  "lambda_within_LGD",
  "lambda_90_area_10_within_LGD",
  "lambda_80_area_20_within_LGD",
  "lambda_x_area_pow_0.25_within_LGD",
  "lambda_x_log_area_within_LGD",
  "random_within_LGD"
)

# ---- 3. Neurological outcome probabilities, utilities and costs ----------------------------
# Neurological outcome probabilities
p_no_mild <- 0.813
p_moderate <- (1 - 0.813) * 0.837
p_severe <- (1 - 0.813) * (1 - 0.837)

# Utilities
u_no_mild <- 0.8
u_moderate <- 0.2
u_severe <- 0.1

# Costs (£)
cost_scheme_5yr <- 474256
cost_hosp_no_mild <- 34540
cost_hosp_moderate <- 13040
cost_hosp_severe <- 10154
cost_weekly_moderate <- 398
cost_weekly_severe <- 424
cost_icd_yearly <- 6168

# ---- 4. Markov model constants -------------------------------------------------------------
# Simple Markov settings
markov_horizon <- 40
discount_rate <- 0.03

# Dillenbeck et al. 2024 hazard ratios
hr_no_mild <- 1.00
hr_moderate <- 1.57
hr_severe <- 2.46

target_surv5_no_mild <- 0.738   # Dillenbeck CPC 1 five-year survival

# ---- 5. Bank of 50 random home locations per Data Zone -------------------------------------
set.seed(123)

dz_all_main <- NI_shapefile %>%
    sf::st_make_valid() %>%
    dplyr::left_join(
      zone_count %>% dplyr::select(zone_code, count, lgd, lgd_name),
      by = "zone_code"
    ) 

zone_sf <- dz_all_main %>%
  select(zone_code, geometry) %>%
  distinct(zone_code, .keep_all = TRUE)

zone_point_bank_list <- lapply(seq_len(nrow(zone_sf)), function(i) {
  g <- st_geometry(zone_sf)[i]
  z <- zone_sf$zone_code[i]

  pts <- st_sample(g, size = 50)

  if (length(pts) == 0) {
    surf_pt <- st_point_on_surface(g)
    pts <- st_sfc(rep(list(surf_pt[[1]]), 50), crs = st_crs(zone_sf))
  } else {
    pts <- st_sfc(pts, crs = st_crs(zone_sf))
  }

  st_sf(
    zone_code = z,
    point_id = seq_along(pts),
    geometry = pts
  )
})

zone_point_bank <- do.call(rbind, zone_point_bank_list)

xy_bank <- st_coordinates(zone_point_bank)

zone_point_bank <- zone_point_bank %>%
  mutate(
    home_x = xy_bank[, 1],
    home_y = xy_bank[, 2]
  ) %>%
  st_drop_geometry()

zone_point_bank %>%
  count(zone_code) %>%
  summarise(
    min_points = min(n),
    max_points = max(n),
    mean_points = mean(n)
  )
