# 02_simulate_arrests.R
#
# Imports and merges the census, lookup and AFT inputs; calculates the expected number of
# witnessed VF cardiac arrests (lambda) per Data Zone; simulates n_sim_years years of arrests
# with a Poisson process; assigns age, sex and time of day to each arrest; and simulates the
# ambulance response time of each arrest from the log-logistic accelerated failure time (AFT)
# model.
#
# Needs : config.R, the raw inputs in data/raw, data/processed/coa_nearest_ambulance.csv
# Makes : df2 (one row per simulated arrest with its ambulance time T_sim), zone_values, census_merged

if (!exists("paths")) source("config.R")
check_inputs()


# ---- 1. Import and merge the inputs --------------------------------------------------------
#Loading the data into r

#Census
census  <- read.csv(paths$census, stringsAsFactors = FALSE, fileEncoding = "UTF-8-BOM")

census <- census %>% rename(zone_code = data_zone_code)


#Old LGD 1992 lookup table

zone_to_lgd_path <- paths$lgd_lookup

zone_to_lgd <- read_excel(path = zone_to_lgd_path, sheet = 4)

zone_to_lgd <- zone_to_lgd %>%
  select(DZ2021_code, LGD1992_code, LGD1992_name) %>%
  rename(zone_code = DZ2021_code, lgd = LGD1992_code, lgd_name = LGD1992_name)

#Urban/rural classification dataset 

Urban_class <- read_excel(path = zone_to_lgd_path, sheet = 5)

Urban_class <- Urban_class %>%
  select(DZ2021_code, Urban_status) %>%
  rename(zone_code = DZ2021_code) %>%
  mutate(Urban_status = ifelse(tolower(Urban_status) == "urban", 1L, 0L))


# AFT model info (used below)

aft_model_path <- paths$aft_model

# NI shapefile (used in script 03)

NI_shapefile_path <- paths$shapefile


#Merging LGD and urban classification datasets into census data

census_merged <- census %>% 
  left_join(zone_to_lgd, by = "zone_code") %>%
  left_join(Urban_class, by = "zone_code")

# NI life tables for QALYs (used in script 03)

NI_lifetable_path <- paths$lifetable

# ---- 2. Expected arrests per year (lambda) for each Data Zone ------------------------------
#3.a - creating count * prob of arrest
census_merged <- census_merged %>% mutate(count * p)

#3.b - Grouping by zone and summing

zone_values <- census_merged %>% 
  group_by(zone_code, data_zone, lgd, lgd_name, Urban_status) %>%
  summarise(
     count = sum(count, na.rm = TRUE),
    lambda = sum(`count * p`, na.rm = TRUE),
    .groups = "drop")

# ---- 3. Simulate annual arrest counts: Poisson, n_sim_years years per Data Zone ------------
# 4.a - Example for a single data zone
lambda_example <- zone_values$lambda[1]

sim_example <- rpois(n_sim_years, lambda_example)

head(sim_example)

# 4.b - Grouping by zone and simulating

poisson_sims <- zone_values %>%
  rowwise() %>%
  mutate(n_arrests = list(rpois(n_sim_years, lambda)))

#4.c - expand into long form

poisson_sims <- poisson_sims %>%
  unnest(n_arrests) %>%
  group_by(zone_code) %>%
  mutate(sim = row_number()) %>%
  ungroup()

poisson_sims <- poisson_sims %>%
  mutate(n_arrests = as.integer(n_arrests)) #Making sure number of arrests is an integer value so below chunk works

# ---- 4. Assign age band and sex to each arrest ---------------------------------------------
# 1. Age-sex probabilities within each zone
age_sex_probs <- census_merged %>%
  transmute(zone_code, age_band, gender, prob = count * p) %>%
  group_by(zone_code) %>%
  mutate(prob = prob / sum(prob, na.rm = TRUE)) %>%
  ungroup()

# 2. Expand to one row per arrest
arrests_long <- poisson_sims %>%
  uncount(n_arrests, .id = "arrest_id") %>%
  group_by(zone_code) %>%
  mutate(zone_row = row_number()) %>%
  ungroup()



# 3. Number of arrests in each zone
zone_counts <- arrests_long %>%
  count(zone_code, name = "n")

# 4. Sample age/gender for all arrests in each zone at once
age_sex_split <- split(age_sex_probs, age_sex_probs$zone_code)

sampled_demo <- map2_dfr(
  zone_counts$zone_code,
  zone_counts$n,
  \(z, n) {
    tab <- age_sex_split[[as.character(z)]]
    draws <- sample(seq_len(nrow(tab)), size = n, replace = TRUE, prob = tab$prob)

    tibble(
      zone_code = z,
      zone_row = seq_len(n),
      age_band = tab$age_band[draws],
      gender = tab$gender[draws]
    )
  }
)

# 5. Join back to arrest rows
arrests_long <- arrests_long %>%
  left_join(sampled_demo, by = c("zone_code", "zone_row")) %>%
  select(-zone_row)

# ---- 5. Assign the time of day (hour block) of each arrest ---------------------------------
#Example:

ncounts_example <- 10

hours <- sample(0:23, size = ncounts_example, replace = TRUE)

hours


#Function that converts the sampled hour to its corresponding hour block

hour_to_block <- function(h) {
  dplyr::case_when(
    h >= 0  & h <= 7  ~ "00-07",
    h >= 8  & h <= 9  ~ "08-09",
    h >= 10 & h <= 13 ~ "10-13",
    h >= 14 & h <= 23 ~ "14-23"
  )
}

hour_to_block(hours)

#Sampling the hour non-uniformly (0-23), row-wise to our simulated data (poisson_sims) 

block_probs <- c(
  "00_07" = 101 / 602,
  "08_09" = 100 / 602,
  "10_13" = 154 / 602,
  "14_23" = 247 / 602
)

hour_poisson_sims <- arrests_long %>%
  mutate(
    hour_block = sample(
      names(block_probs),
      size = n(),
      replace = TRUE,
      prob = block_probs
    )
  )


hour_poisson_sims <- hour_poisson_sims %>% #Unnesting: for each data zone, sims where n_arrests = 0 are skipped
  unnest(hour_block)


# 2) Make sure the factor has all levels (important if some hours missing)
hour_poisson_sims$hour_block <- factor(hour_poisson_sims$hour_block, levels = c("00_07", "08_09", "10_13", "14_23"))

# 3) Create binary columns (one-hot). This returns a matrix.
X <- model.matrix(~ hour_block - 1, data = hour_poisson_sims)
# columns: hour_block00_07, hour_block08_09, hour_block10_13, hour_block14_23

# 4) Bind back into hour_poisson_sims (as plain numeric columns)
hour_poisson_sims <- cbind(hour_poisson_sims, as.data.frame(X))

# Rename columns to your preferred names
names(hour_poisson_sims)[(ncol(hour_poisson_sims)-3):ncol(hour_poisson_sims)] <- c("hb_00_07", "hb_08_09", "hb_10_13", "hb_14_23")

# ---- 6. Attach distances to the nearest ambulance stations ---------------------------------
coa_nearest_ambulance <- read.csv(paths$coa_distances, stringsAsFactors = FALSE)  # made by script 01
if (!all(c("zone_code", "ln_nearest1_miles", "ln_nearest2_miles", "near_2mi") %in% names(coa_nearest_ambulance)))
  stop("paths$coa_distances is not the table written by scripts/01_station_distances.R. ",
       "Delete it and re-run that script.", call. = FALSE)

df <- hour_poisson_sims %>%
  left_join(coa_nearest_ambulance, by = "zone_code")

# ---- 7. Ambulance response time from the AFT model (inverse-transform sampling) ------------
params <- read_excel(aft_model_path, sheet = 1) %>%
  select(-matches("^Unnamed")) %>%
  transmute(
    lgd = lgd,
    intercept = intercept,
    b_ln_d1   = `ln(min_dist+1)`,
    b_ln_d2   = `ln(2nd_closest+1)`,
    b_lt2     = logic_less_Than_2,
    b_h0007   = hour0007,
    b_h0809   = hour0809,
    b_h1013   = hour1013,
    b_h1423   = hour1423,
    sigma     = scale
  )

# Join by 2-letter code column eg. Fermanagh = PP

df2 <- df %>%
  left_join(
    params %>% mutate(lgd = paste0("95", lgd)),
    by = "lgd"
  )


stopifnot(sum(is.na(df2$intercept)) == 0)

# Compute mu 
df2 <- df2 %>%
  mutate(
    mu = intercept +
      b_ln_d1 * ln_nearest1_miles +
      b_ln_d2 * ln_nearest2_miles +
      b_lt2   * near_2mi +
      b_h0007 * hb_00_07 +
      b_h0809 * hb_08_09 +
      b_h1013 * hb_10_13 +
      b_h1423 * hb_14_23
  )

# Log-logistic survival at threshold t0 = 7 (target)
t0 <- 7
df2 <- df2 %>%
  mutate(
    z = (log(t0) - mu) / sigma,
    p_le_t0 = plogis(z),
    s_gt_t0 = plogis(-z)
    
    
  )


df2 <- df2 %>%
  mutate(
    U = runif(n()),                 # U = F
    T_sim = exp(mu + sigma * qlogis(U))
  )
