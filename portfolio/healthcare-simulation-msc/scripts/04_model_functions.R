# 04_model_functions.R
#
# All the functions of the Monte Carlo model: Markov microsimulation of additional survivors,
# five-year blocks for the cost-effectiveness analysis, random allocation rules, weekly first-
# responder paging and response, and the main function that runs one LGD for one allocation
# rule (run_one_lgd_vary_qaly) with its wrapper run_rule_lgd.
#
# Needs : objects from scripts 02 and 03
# Makes : functions only (plus common_args and a few allocation objects)


# ---- 1. Markov microsimulation helpers: starting age, life-table survival, QALYs and cost ---
sample_age_from_band <- function(age_band) {
  dplyr::case_when(
    age_band == "1 (0–4 years)"   ~ sample(0:4, 1),
    age_band == "2 (5–9 years)"   ~ sample(5:9, 1),
    age_band == "3 (10–14 years)" ~ sample(10:14, 1),
    age_band == "4 (15–19 years)" ~ sample(15:19, 1),
    age_band == "5 (20–24 years)" ~ sample(20:24, 1),
    age_band == "6 (25–29 years)" ~ sample(25:29, 1),
    age_band == "7 (30–34 years)" ~ sample(30:34, 1),
    age_band == "8 (35–39 years)" ~ sample(35:39, 1),
    age_band == "9 (40–44 years)" ~ sample(40:44, 1),
    age_band == "10 (45–49 years)" ~ sample(45:49, 1),
    age_band == "11 (50–54 years)" ~ sample(50:54, 1),
    age_band == "12 (55–59 years)" ~ sample(55:59, 1),
    age_band == "13 (60–64 years)" ~ sample(60:64, 1),
    age_band == "14 (65–69 years)" ~ sample(65:69, 1),
    age_band == "15 (70–74 years)" ~ sample(70:74, 1),
    age_band == "16 (75–79 years)" ~ sample(75:79, 1),
    age_band == "17 (80–84 years)" ~ sample(80:84, 1),
    age_band == "18 (85–89 years)" ~ sample(85:89, 1),
    age_band == "19 (90+ years)"   ~ sample(90:100, 1),
    TRUE ~ 60L
  )
}

get_year_surv <- function(age_val, sex_val, life_table_yearly) {
  out <- life_table_yearly %>%
    filter(age == age_val, gender == sex_val) %>%
    pull(year_surv_rate)

  if (length(out) == 0 || is.na(out)) return(0.5)
  out
}

simulate_markov_micro <- function(age_band,
                                  gender,
                                  neuro_status,
                                  life_table_yearly,
                                  discount_rate = 0.03,
                                  horizon_years = 40,
                                  target_surv5_no_mild = 0.738,
                                  hr_no_mild = 1.00,
                                  hr_moderate = 1.57,
                                  hr_severe = 2.46,
                                  u_no_mild,
                                  u_moderate,
                                  u_severe,
                                  cost_hosp_no_mild,
                                  cost_hosp_moderate,
                                  cost_hosp_severe,
                                  cost_weekly_moderate,
                                  cost_weekly_severe,
                                  cost_icd_yearly) {

  age_start <- sample_age_from_band(age_band)

  utility <- dplyr::case_when(
    neuro_status == "no_mild" ~ u_no_mild,
    neuro_status == "moderate" ~ u_moderate,
    neuro_status == "severe" ~ u_severe,
    TRUE ~ 0
  )

  annual_cost <- dplyr::case_when(
    neuro_status == "no_mild" ~ cost_icd_yearly,
    neuro_status == "moderate" ~ 52 * cost_weekly_moderate,
    neuro_status == "severe" ~ 52 * cost_weekly_severe,
    TRUE ~ 0
  )

  hosp_cost <- dplyr::case_when(
    neuro_status == "no_mild" ~ cost_hosp_no_mild,
    neuro_status == "moderate" ~ cost_hosp_moderate,
    neuro_status == "severe" ~ cost_hosp_severe,
    TRUE ~ 0
  )

  hr_state <- dplyr::case_when(
    neuro_status == "no_mild" ~ hr_no_mild,
    neuro_status == "moderate" ~ hr_moderate,
    neuro_status == "severe" ~ hr_severe,
    TRUE ~ 1
  )

  # Calibrate a fixed post-arrest excess hazard at baseline so the no/mild group matches Dillenbeck's 5-year survival for CPC 1.
  base_surv5_start <- prod(sapply(0:4, function(k) {
    get_year_surv(min(age_start + k, 100L), gender, life_table_yearly)
  }))

  hr_post_arrest <- log(target_surv5_no_mild) / log(pmax(base_surv5_start, 1e-6))
  hr_post_arrest <- max(hr_post_arrest, 1)

  qaly <- 0
  cost <- hosp_cost
  alive <- TRUE

  for (t in seq_len(horizon_years)) {
    if (!alive) break

    age_t <- min(age_start + (t - 1), 100L)
    base_surv_t <- get_year_surv(age_t, gender, life_table_yearly)

    p_surv_year <- base_surv_t^(hr_post_arrest * hr_state)
    disc <- 1 / ((1 + discount_rate)^(t - 1))

    survive_full_year <- rbinom(1, 1, p_surv_year) == 1
    year_weight <- ifelse(survive_full_year, 1, 0.5)  # half-cycle correction

    qaly <- qaly + utility * disc * year_weight
    cost <- cost + annual_cost * disc * year_weight

    alive <- survive_full_year
  }

  c(qaly_gain = qaly, survivor_cost = cost)
}

# ---- 2. Keep the first n simulated years ---------------------------------------------------
subset_first_sims <- function(df, n_sims) {
  sims_keep <- sort(unique(df$sim))[seq_len(min(n_sims, n_distinct(df$sim)))]
  df %>%
    dplyr::filter(sim %in% sims_keep)
}

# ---- 3. Combine yearly results into 5-year blocks ------------------------------------------
make_five_year_blocks <- function(sim_level_df, scheme_cost_is_already_5yr = TRUE) {
  
  sim_lookup <- tibble::tibble(
    sim = sort(unique(sim_level_df$sim)),
    sim_index = seq_along(sort(unique(sim_level_df$sim)))
  ) %>%
    dplyr::mutate(block_id = ceiling(sim_index / 5))

  sim_level_df %>%
    dplyr::left_join(sim_lookup, by = "sim") %>%
    dplyr::group_by(block_id) %>%
    dplyr::summarise(
      n_years_in_block = dplyr::n_distinct(sim),
      lives_saved_5yr = sum(sim_lives_saved_year, na.rm = TRUE),
      qalys_5yr = sum(sim_qalys_year, na.rm = TRUE),
      survivor_cost_5yr = sum(sim_survivor_cost_year, na.rm = TRUE),
      scheme_cost_5yr = if (scheme_cost_is_already_5yr) {
        dplyr::first(sim_scheme_cost_year)
      } else {
        sum(sim_scheme_cost_year, na.rm = TRUE)
      },
      total_cost_5yr = scheme_cost_5yr + survivor_cost_5yr,
      icer_5yr = ifelse(qalys_5yr > 0, total_cost_5yr / qalys_5yr, NA_real_),
      .groups = "drop"
    )
}

# ---- 4. Random allocation rules ------------------------------------------------------------
set.seed(123)

random_zone_assignments <- sample(
  alloc_base$zone_code,
  size = total_vol_ni,
  replace = TRUE
)

fr_alloc_random_across_NI_true <- tibble(zone_code = random_zone_assignments) %>%
  count(zone_code, name = "fr_target") %>%
  right_join(alloc_base, by = "zone_code") %>%
  mutate(
    fr_target = ifelse(is.na(fr_target), 0L, fr_target),
    rule = "random_across_NI_true"
  )

make_random_within_lgd_alloc <- function(alloc_base, fr_per_lgd = 31) {
  alloc_base %>%
    dplyr::group_by(lgd) %>%
    dplyr::mutate(
      score = 1,
      raw_target = fr_per_lgd / dplyr::n(),
      fr_target = floor(raw_target),
      remainder = raw_target - fr_target
    ) %>%
    dplyr::group_modify(~{
      d <- .x
      n_left <- fr_per_lgd - sum(d$fr_target, na.rm = TRUE)
      if (n_left > 0) {
        add_idx <- sample(seq_len(nrow(d)), size = n_left)
        d$fr_target[add_idx] <- d$fr_target[add_idx] + 1
      }
      d
    }) %>%
    dplyr::ungroup() %>%
    dplyr::mutate(rule = "random_within_LGD")
}

make_random_across_ni_alloc <- function(alloc_base, total_vol_ni = 806) {
  random_zone_assignments <- sample(
    alloc_base$zone_code,
    size = total_vol_ni,
    replace = TRUE
  )

  tibble::tibble(zone_code = random_zone_assignments) %>%
    dplyr::count(zone_code, name = "fr_target") %>%
    dplyr::right_join(alloc_base, by = "zone_code") %>%
    dplyr::mutate(
      fr_target = ifelse(is.na(fr_target), 0L, fr_target),
      rule = "random_across_NI"
    )
}


generate_random_allocations_by_sim <- function(rule_name,  #here
                                               alloc_base,
                                               sim_ids,
                                               total_vol_ni = 806,
                                               fr_per_lgd = 31,
                                               seed = 1) {

  out <- vector("list", length(sim_ids))
  names(out) <- as.character(sim_ids)

  for (i in seq_along(sim_ids)) {
    set.seed(seed + i)

    out[[i]] <- switch(
      rule_name,
      "random_within_LGD" = make_random_within_lgd_alloc(
        alloc_base = alloc_base,
        fr_per_lgd = fr_per_lgd
      ),
      "random_across_NI" = make_random_across_ni_alloc(
        alloc_base = alloc_base,
        total_vol_ni = total_vol_ni
      ),
      stop("generate_random_allocations_by_sim() only supports random rules.")
    )
  }

  out
}

# ---- 5. One week of first-responder paging and response ------------------------------------
process_week_fr <- function(w,
                            df_sim,
                            volunteers,
                            n_cohorts,
                            radius_m,
                            p_respond,
                            k_decay,
                            dispatch_sens,
                            p_gear) {

  A <- df_sim %>% dplyr::filter(week == w)
  if (nrow(A) == 0) return(NULL)

  active_cohort <- ((w - 1) %% n_cohorts) + 1
  R <- volunteers %>% dplyr::filter(cohort == active_cohort)
  if (nrow(R) == 0) return(NULL)

  dx <- outer(A$coa_easting, R$home_x, "-")
  dy <- outer(A$coa_northing, R$home_y, "-")
  dist_m_mat <- sqrt(dx^2 + dy^2)

  within_idx <- which(dist_m_mat <= radius_m, arr.ind = TRUE)
  if (nrow(within_idx) == 0) return(NULL)

  pairs <- tibble::tibble(
    arrest_row_local = within_idx[, 1],
    responder_row_local = within_idx[, 2],
    dist_m = dist_m_mat[within_idx]
  ) %>%
    dplyr::mutate(
      dist_miles = dist_m / 1609.344,
      p_resp_dist = p_respond * exp(-k_decay * dist_miles),
      p_resp_dist = pmin(pmax(p_resp_dist, 0), 1),
      sim_row_id = A$sim_row_id[arrest_row_local],
      volunteer_id = R$volunteer_id[responder_row_local],
      week = w
    )

  # dispatch applied ONCE per arrest
  dispatch_by_event <- tibble::tibble(
    sim_row_id = sort(unique(pairs$sim_row_id)),
    dispatched = rbinom(length(unique(pairs$sim_row_id)), 1, dispatch_sens)
  )

  pairs <- pairs %>%
    dplyr::left_join(dispatch_by_event, by = "sim_row_id") %>%
    dplyr::mutate(
      got_gear = ifelse(dispatched == 1, rbinom(dplyr::n(), 1, p_gear), 0),
      responded = ifelse(got_gear == 1, rbinom(dplyr::n(), 1, p_resp_dist), 0)
    )

  pairs
}

# ---- 6. Main function: one LGD, one allocation rule ----------------------------------------
# NOTE: the per-year ICER (sim_icer) and the per-year costs below apply the full 5-year scheme cost to
# every simulated year. The reported ICERs come from make_five_year_blocks(), which counts the scheme
# cost once per 5 simulated years.
run_one_lgd_vary_qaly <- function(target_lgd,
                                  df2, zone_count, NI_shapefile, fr_alloc = NULL,
                                  fr_alloc_by_sim = NULL,
                                  zone_point_bank,
                                  life_table_yearly,
                                  weeks = 52, rota_len = 4,
                                  radius_miles = 15,
                                  p_gear = 0.8, p_respond = 0.3, dispatch_sens = 0.4,
                                  k_decay = 0.1,
                                  b0 = 1.8790657182, b1 = 0.2971864133,
                                  b2 = 0.2934664770, sigma = 0.2983923496,
                                  discount_rate = 0.03,
                                  markov_horizon = 70,
                                  target_surv5_no_mild = 0.738,
                                  hr_no_mild = 1.00,
                                  hr_moderate = 1.57,
                                  hr_severe = 2.46,
                                  u_no_mild,
                                  u_moderate,
                                  u_severe,
                                  cost_scheme_5yr,
                                  cost_hosp_no_mild,
                                  cost_hosp_moderate,
                                  cost_hosp_severe,
                                  cost_weekly_moderate,
                                  cost_weekly_severe,
                                  cost_icd_yearly,
                                  p_no_mild,
                                  p_moderate,
                                  p_severe,
                                  seed = 1,
                                  return_sim_level = FALSE,
                                  max_sims = NULL) {

  # a) Setup
  set.seed(seed)
  radius_m <- radius_miles * 1609.344

  # b) Build LGD base zone table WITHOUT attaching FR targets yet
  #    FR counts are attached inside each simulation year so that
  #    simulation-specific random allocations can be supported.
  dz_w <- dz_all_main %>%
    dplyr::filter(lgd == target_lgd) %>%
    dplyr::mutate(
      count = ifelse(is.na(count) | count < 0, 0, count)
    ) %>%
    dplyr::filter(count > 0)

  lgd_population <- sum(dz_w$count, na.rm = TRUE)
  lgd_area_km2 <- if (nrow(dz_w) > 0) {
    as.numeric(sf::st_area(sf::st_union(dz_w$geometry))) / 1e6
  } else {
    NA_real_
  }

  if (nrow(dz_w) == 0) {
    empty_out <- tibble::tibble(
      lgd_code = target_lgd,
      lgd_name = NA_character_,
      lgd_population = 0,
      lgd_area_km2 = NA_real_,
      n_arrests = 0L,
      n_vol = 0L,
      n_per_week = 0L,
      total_lives_saved = 0,
      total_qalys_gained = 0,
      total_survivor_cost = 0,
      avg_ambulance_time = NA_real_,
      avg_ambulance_plus_FR_time = NA_real_,
      mean_lives_saved_per_year = NA_real_,
      mean_qalys_gained_per_year = NA_real_,
      mean_survivor_cost_per_year = NA_real_,
      mean_scheme_cost_per_year = NA_real_,
      mean_total_cost_per_year = NA_real_,
      mean_icer = NA_real_,
      icer_from_means = NA_real_,
      mean_surv_base_year = NA_real_,
      mean_surv_FR_year = NA_real_
    )

    if (return_sim_level) {
      return(list(summary = empty_out, sim_level = tibble::tibble()))
    } else {
      return(empty_out)
    }
  }

  # c) Baseline arrests in this LGD
  df_lgd <- df2 %>%
    dplyr::filter(lgd == target_lgd)

  if (!is.null(max_sims)) {
    sims_keep <- sort(unique(df_lgd$sim))[seq_len(min(max_sims, dplyr::n_distinct(df_lgd$sim)))]
    df_lgd <- df_lgd %>%
      dplyr::filter(sim %in% sims_keep)
  }

  if (nrow(df_lgd) == 0) {
    empty_out <- tibble::tibble(
      lgd_code = target_lgd,
      lgd_name = dplyr::first(dz_w$lgd_name),
      lgd_population = lgd_population,
      lgd_area_km2 = lgd_area_km2,
      n_arrests = 0L,
      n_vol = NA_real_,
      n_per_week = NA_real_,
      total_lives_saved = 0,
      total_qalys_gained = 0,
      total_survivor_cost = 0,
      avg_ambulance_time = NA_real_,
      avg_ambulance_plus_FR_time = NA_real_,
      mean_lives_saved_per_year = NA_real_,
      mean_qalys_gained_per_year = NA_real_,
      mean_survivor_cost_per_year = NA_real_,
      mean_scheme_cost_per_year = NA_real_,
      mean_total_cost_per_year = NA_real_,
      mean_icer = NA_real_,
      icer_from_means = NA_real_,
      mean_surv_base_year = NA_real_,
      mean_surv_FR_year = NA_real_
    )

    if (return_sim_level) {
      return(list(summary = empty_out, sim_level = tibble::tibble()))
    } else {
      return(empty_out)
    }
  }

  if (!"sim" %in% names(df_lgd)) {
    stop("df2 must contain a 'sim' column.")
  }

  sim_ids <- sort(unique(df_lgd$sim))

  # d) Run one simulated year at a time
  sim_results <- lapply(seq_along(sim_ids), function(ii) {
    sim_id <- sim_ids[ii]
    set.seed(seed + ii)

    df_sim <- df_lgd %>%
      dplyr::filter(sim == sim_id) %>%
      dplyr::mutate(
        week = sample(1:weeks, size = dplyr::n(), replace = TRUE),
        sim_row_id = dplyr::row_number()
      )

    if (nrow(df_sim) == 0) {
      return(tibble::tibble())
    }

    # e) Attach simulation-specific FR allocation
    if (!is.null(fr_alloc_by_sim)) {

      fr_alloc_sim <- fr_alloc_by_sim[[as.character(sim_id)]]

      if (is.null(fr_alloc_sim)) {
        stop(paste("No fr_alloc_by_sim entry found for sim", sim_id))
      }

      fr_alloc_small_sim <- fr_alloc_sim %>%
        dplyr::ungroup() %>%
        dplyr::transmute(zone_code, fr_target)

    } else {

      if (is.null(fr_alloc)) {
        stop("Either fr_alloc or fr_alloc_by_sim must be supplied.")
      }

      fr_alloc_small_sim <- fr_alloc %>%
        dplyr::ungroup() %>%
        dplyr::transmute(zone_code, fr_target)
    }

    fr_counts_sim <- dz_w %>%
      sf::st_drop_geometry() %>%
      dplyr::select(zone_code) %>%
      dplyr::left_join(fr_alloc_small_sim, by = "zone_code") %>%
      dplyr::mutate(
        fr_target = ifelse(is.na(fr_target), 0L, fr_target)
      )

    n_vol_sim <- sum(fr_counts_sim$fr_target, na.rm = TRUE)
    n_cohorts_sim <- ifelse(n_vol_sim < rota_len, 1, rota_len)
    n_per_week_sim <- ceiling(n_vol_sim / n_cohorts_sim)

    # f) Fresh FR roster/home points for this simulation year
    if (n_vol_sim > 0) {
      vol <- fr_counts_sim %>%
        tidyr::uncount(fr_target) %>%
        dplyr::mutate(
          volunteer_id = dplyr::row_number(),
          cohort = rep(1:n_cohorts_sim, length.out = dplyr::n())
        )

      volunteers <- vol %>%
        dplyr::left_join(zone_point_bank, by = "zone_code") %>%
        dplyr::group_by(volunteer_id, cohort, zone_code) %>%
        dplyr::slice_sample(n = 1) %>%
        dplyr::ungroup() %>%
        dplyr::select(volunteer_id, cohort, zone_code, home_x, home_y)

      if (any(is.na(volunteers$home_x)) || any(is.na(volunteers$home_y))) {
        stop("Missing home coordinates after joining zone_point_bank.")
      }
    }

    # g) Weekly FR paging and response using external helper
    if (n_vol_sim == 0) {
      df_best <- df_sim %>% dplyr::mutate(t_best = T_sim)

    } else {

      pair_results <- dplyr::bind_rows(
        lapply(
          sort(unique(df_sim$week)),
          process_week_fr,
          df_sim = df_sim,
          volunteers = volunteers,
          n_cohorts = n_cohorts_sim,
          radius_m = radius_m,
          p_respond = p_respond,
          k_decay = k_decay,
          dispatch_sens = dispatch_sens,
          p_gear = p_gear
        )
      )

      if (is.null(pair_results) || nrow(pair_results) == 0) {
        df_best <- df_sim %>% dplyr::mutate(t_best = T_sim)

      } else {
        responded_long <- pair_results %>%
          dplyr::filter(responded == 1) %>%
          dplyr::left_join(
            df_sim %>% dplyr::select(sim_row_id, Urban_status),
            by = "sim_row_id"
          ) %>%
          dplyr::mutate(
            dist_for_log = pmax(dist_miles, 1e-6),
            mu_fr = b0 + b1 * log(dist_for_log) + b2 * Urban_status,
            u = runif(dplyr::n()),
            FR_time = exp(mu_fr + sigma * qlogis(u))
          )

        fr_best <- responded_long %>%
          dplyr::group_by(sim_row_id) %>%
          dplyr::summarise(fr_time_min = min(FR_time), .groups = "drop")

        df_best <- df_sim %>%
          dplyr::left_join(fr_best, by = "sim_row_id") %>%
          dplyr::mutate(
            fr_time_min = ifelse(is.na(fr_time_min), Inf, fr_time_min),
            t_best = pmin(T_sim, fr_time_min)
          )
      }
    }

    # h) Survival comparison for this simulated year
    comparison <- df_sim %>%
      dplyr::select(sim_row_id, sim, age_band, gender, T0 = T_sim) %>%
      dplyr::inner_join(
        df_best %>% dplyr::select(sim_row_id, T1 = t_best),
        by = "sim_row_id"
      ) %>%
      dplyr::mutate(U_surv = runif(dplyr::n())) %>%
      dplyr::mutate(
        IDEFIB0 = T0 + 1,
        ICPR0   = T0 + 2,
        p_base = plogis(-0.260 - 0.106 * ICPR0 - 0.139 * IDEFIB0),
        IDEFIB1 = T1 + 1,
        ICPR1   = T1 + 2,
        p_FR = plogis(-0.260 - 0.106 * ICPR1 - 0.139 * IDEFIB1),
        y_base = as.integer(U_surv < p_base),
        y_FR   = as.integer(U_surv < p_FR),
        dy = y_FR - y_base
      ) %>%
      dplyr::mutate(
        neuro_status = NA_character_,
        qaly_gain = 0,
        survivor_cost = 0
      )

    # i) Assign neurological state and run microsimulation only for incremental survivors
    idx <- which(comparison$dy == 1)

    if (length(idx) > 0) {
      comparison$neuro_status[idx] <- sample(
        c("no_mild", "moderate", "severe"),
        size = length(idx),
        replace = TRUE,
        prob = c(p_no_mild, p_moderate, p_severe)
      )

      micro_out <- t(vapply(idx, function(j) {
        simulate_markov_micro(
          age_band = comparison$age_band[j],
          gender = comparison$gender[j],
          neuro_status = comparison$neuro_status[j],
          life_table_yearly = life_table_yearly,
          discount_rate = discount_rate,
          horizon_years = markov_horizon,
          target_surv5_no_mild = target_surv5_no_mild,
          hr_no_mild = hr_no_mild,
          hr_moderate = hr_moderate,
          hr_severe = hr_severe,
          u_no_mild = u_no_mild,
          u_moderate = u_moderate,
          u_severe = u_severe,
          cost_hosp_no_mild = cost_hosp_no_mild,
          cost_hosp_moderate = cost_hosp_moderate,
          cost_hosp_severe = cost_hosp_severe,
          cost_weekly_moderate = cost_weekly_moderate,
          cost_weekly_severe = cost_weekly_severe,
          cost_icd_yearly = cost_icd_yearly
        )
      }, numeric(2)))

      comparison$qaly_gain[idx] <- micro_out[, "qaly_gain"]
      comparison$survivor_cost[idx] <- micro_out[, "survivor_cost"]
    }

    # j) Summarise this simulated year
    sim_lives_saved_year <- sum(comparison$dy, na.rm = TRUE)
    sim_qalys_year <- sum(comparison$qaly_gain, na.rm = TRUE)
    sim_survivor_cost_year <- sum(comparison$survivor_cost, na.rm = TRUE)

    # yearly mean predicted survival rates
    sim_surv_base_year <- mean(comparison$p_base, na.rm = TRUE)
    sim_surv_FR_year   <- mean(comparison$p_FR,   na.rm = TRUE)

    scheme_cost_5yr_lgd <- cost_scheme_5yr
    scheme_cost_per_year_lgd <- scheme_cost_5yr_lgd

    sim_total_cost_year <- scheme_cost_per_year_lgd + sim_survivor_cost_year
    sim_icer <- ifelse(sim_qalys_year > 0,
                       sim_total_cost_year / sim_qalys_year,
                       NA_real_)

    tibble::tibble(
      sim = sim_id,
      n_arrests = nrow(comparison),
      n_vol = n_vol_sim,
      n_per_week = n_per_week_sim,
      avg_ambulance_time = mean(comparison$T0, na.rm = TRUE),
      avg_ambulance_plus_FR_time = mean(comparison$T1, na.rm = TRUE),
      sim_surv_base_year = sim_surv_base_year,
      sim_surv_FR_year = sim_surv_FR_year,
      sim_lives_saved_year = sim_lives_saved_year,
      sim_qalys_year = sim_qalys_year,
      sim_survivor_cost_year = sim_survivor_cost_year,
      sim_scheme_cost_year = scheme_cost_per_year_lgd,
      sim_total_cost_year = sim_total_cost_year,
      sim_icer = sim_icer
    )
  })

  # k) Bind yearly results across simulations
  by_year <- dplyr::bind_rows(sim_results)
  
  q025 <- function(x) stats::quantile(x, 0.025, na.rm = TRUE, names = FALSE)
  q975 <- function(x) stats::quantile(x, 0.975, na.rm = TRUE, names = FALSE)

  # l) LGD-level summary
  summary_out <- tibble::tibble(
  lgd_code = target_lgd,
  lgd_name = dplyr::first(dz_w$lgd_name),
  lgd_population = lgd_population,
  lgd_area_km2 = lgd_area_km2,
  n_arrests = sum(by_year$n_arrests, na.rm = TRUE),
  n_vol = mean(by_year$n_vol, na.rm = TRUE),
  n_per_week = mean(by_year$n_per_week, na.rm = TRUE),

  total_lives_saved = sum(by_year$sim_lives_saved_year, na.rm = TRUE),
  total_qalys_gained = sum(by_year$sim_qalys_year, na.rm = TRUE),
  total_survivor_cost = sum(by_year$sim_survivor_cost_year, na.rm = TRUE),

  avg_ambulance_time = mean(by_year$avg_ambulance_time, na.rm = TRUE),
  avg_ambulance_plus_FR_time = mean(by_year$avg_ambulance_plus_FR_time, na.rm = TRUE),

  mean_surv_base_year = mean(by_year$sim_surv_base_year, na.rm = TRUE),
  mean_surv_base_year_lo = q025(by_year$sim_surv_base_year),
  mean_surv_base_year_hi = q975(by_year$sim_surv_base_year),

  mean_surv_FR_year = mean(by_year$sim_surv_FR_year, na.rm = TRUE),
  mean_surv_FR_year_lo = q025(by_year$sim_surv_FR_year),
  mean_surv_FR_year_hi = q975(by_year$sim_surv_FR_year),

  mean_lives_saved_per_year = mean(by_year$sim_lives_saved_year, na.rm = TRUE),
  mean_lives_saved_per_year_lo = q025(by_year$sim_lives_saved_year),
  mean_lives_saved_per_year_hi = q975(by_year$sim_lives_saved_year),

  mean_qalys_gained_per_year = mean(by_year$sim_qalys_year, na.rm = TRUE),
  mean_qalys_gained_per_year_lo = q025(by_year$sim_qalys_year),
  mean_qalys_gained_per_year_hi = q975(by_year$sim_qalys_year),

  mean_survivor_cost_per_year = mean(by_year$sim_survivor_cost_year, na.rm = TRUE),
  mean_survivor_cost_per_year_lo = q025(by_year$sim_survivor_cost_year),
  mean_survivor_cost_per_year_hi = q975(by_year$sim_survivor_cost_year),

  mean_scheme_cost_per_year = mean(by_year$sim_scheme_cost_year, na.rm = TRUE),
  mean_scheme_cost_per_year_lo = q025(by_year$sim_scheme_cost_year),
  mean_scheme_cost_per_year_hi = q975(by_year$sim_scheme_cost_year),

  mean_total_cost_per_year = mean(by_year$sim_total_cost_year, na.rm = TRUE),
  mean_total_cost_per_year_lo = q025(by_year$sim_total_cost_year),
  mean_total_cost_per_year_hi = q975(by_year$sim_total_cost_year),

  mean_icer = mean(by_year$sim_icer, na.rm = TRUE),
  mean_icer_lo = q025(by_year$sim_icer),
  mean_icer_hi = q975(by_year$sim_icer),

  icer_from_means = mean(by_year$sim_total_cost_year, na.rm = TRUE) /
    mean(by_year$sim_qalys_year, na.rm = TRUE),

  avg_ambulance_time_lo = q025(by_year$avg_ambulance_time),
  avg_ambulance_time_hi = q975(by_year$avg_ambulance_time),

  avg_ambulance_plus_FR_time_lo = q025(by_year$avg_ambulance_plus_FR_time),
  avg_ambulance_plus_FR_time_hi = q975(by_year$avg_ambulance_plus_FR_time)
)
  
  #Nice and pretty output
  summary_out <- summary_out %>%
  dplyr::mutate(
    lives_saved_display = sprintf(
      "%.2f (%.2f, %.2f)",
      mean_lives_saved_per_year,
      mean_lives_saved_per_year_lo,
      mean_lives_saved_per_year_hi
    ),
    qalys_display = sprintf(
      "%.2f (%.2f, %.2f)",
      mean_qalys_gained_per_year,
      mean_qalys_gained_per_year_lo,
      mean_qalys_gained_per_year_hi
    ),
    total_cost_display = sprintf(
      "£%s (£%s, £%s)",
      format(round(mean_total_cost_per_year, 0), big.mark = ","),
      format(round(mean_total_cost_per_year_lo, 0), big.mark = ","),
      format(round(mean_total_cost_per_year_hi, 0), big.mark = ",")
    ),
    icer_display = sprintf(
      "£%s (£%s, £%s)",
      format(round(mean_icer, 0), big.mark = ","),
      format(round(mean_icer_lo, 0), big.mark = ","),
      format(round(mean_icer_hi, 0), big.mark = ",")
    )
  )

  if (return_sim_level) {
    sim_out <- by_year %>%
      dplyr::mutate(
        lgd_code = target_lgd,
        lgd_name = dplyr::first(dz_w$lgd_name)
      )
    return(list(summary = summary_out, sim_level = sim_out))
  } else {
    return(summary_out)
  }
}

# ---- 7. Common arguments and the run_rule_lgd wrapper --------------------------------------
lgds <- sort(unique(zone_count$lgd))
all_rules <- unique(fr_alloc_all_rules$rule)

main_rules <- c(
  "lambda_across_NI",
  "lambda_within_LGD",
  "random_within_LGD"
)

common_args <- list(
  zone_count = zone_count,
  NI_shapefile = NI_shapefile,
  zone_point_bank = zone_point_bank,
  life_table_yearly = life_table_yearly,
  weeks = 52,
  rota_len = 4,
  radius_miles = 15,
  p_gear = 0.8,
  p_respond = 0.3,
  dispatch_sens = 0.4,
  k_decay = 0.1,
  b0 = 1.8790657182,
  b1 = 0.2971864133,
  b2 = 0.2934664770,
  sigma = 0.2983923496,
  discount_rate = 0.03,
  markov_horizon = markov_horizon,   # 40 years, set in script 03 (as in the dissertation)
  target_surv5_no_mild = 0.738,
  hr_no_mild = 1.00,
  hr_moderate = 1.57,
  hr_severe = 2.46,
  u_no_mild = u_no_mild,
  u_moderate = u_moderate,
  u_severe = u_severe,
  cost_scheme_5yr = cost_scheme_5yr,
  cost_hosp_no_mild = cost_hosp_no_mild,
  cost_hosp_moderate = cost_hosp_moderate,
  cost_hosp_severe = cost_hosp_severe,
  cost_weekly_moderate = cost_weekly_moderate,
  cost_weekly_severe = cost_weekly_severe,
  cost_icd_yearly = cost_icd_yearly,
  p_no_mild = p_no_mild,
  p_moderate = p_moderate,
  p_severe = p_severe
)

run_rule_lgd <- function(rule_name, target_lgd, df2_use, seed,
                         return_sim_level = FALSE,
                         max_sims = NULL) {

  sims_use <- sort(unique(df2_use$sim))
  if (!is.null(max_sims)) {
    sims_use <- sims_use[seq_len(min(max_sims, length(sims_use)))]
  }

  df2_use <- df2_use %>%
    dplyr::filter(sim %in% sims_use)

  if (rule_name %in% c("random_within_LGD", "random_across_NI")) {

    fr_alloc_by_sim <- generate_random_allocations_by_sim(
      rule_name = rule_name,
      alloc_base = alloc_base,
      sim_ids = sims_use,
      total_vol_ni = total_vol_ni,
      fr_per_lgd = 31,
      seed = seed
    )

    do.call(
      run_one_lgd_vary_qaly,
      c(
        list(
          target_lgd = target_lgd,
          df2 = df2_use,
          fr_alloc = NULL,
          fr_alloc_by_sim = fr_alloc_by_sim,
          seed = seed,
          return_sim_level = return_sim_level,
          max_sims = max_sims
        ),
        common_args
      )
    )

  } else {

    fr_alloc_rule <- fr_alloc_all_rules %>%
      dplyr::filter(rule == rule_name)

    do.call(
      run_one_lgd_vary_qaly,
      c(
        list(
          target_lgd = target_lgd,
          df2 = df2_use,
          fr_alloc = fr_alloc_rule,
          fr_alloc_by_sim = NULL,
          seed = seed,
          return_sim_level = return_sim_level,
          max_sims = max_sims
        ),
        common_args
      )
    )
  }
}
