# run_all.R: run the whole pipeline in order. All scripts share one R session (global environment).
#   Full run   : Rscript run_all.R           (slow: the 1000-year runs are the long part)
#   Quick check: N_SIM_YEARS=20 Rscript run_all.R
source("config.R")
check_inputs(include_coa = FALSE)

# Script 01 needs internet (geocoding); skip it if its output already exists
if (!file.exists(paths$coa_distances)) {
  message(">> scripts/01_station_distances.R")
  source("scripts/01_station_distances.R", print.eval = TRUE)
}

for (f in c("scripts/00_setup.R",
            "scripts/02_simulate_arrests.R",
            "scripts/03_inputs_and_allocation.R",
            "scripts/04_model_functions.R",
            "scripts/05_screening_allocation_rules.R",
            "scripts/06_cost_effectiveness.R",
            "scripts/07_maps_and_plots.R")) {
  message(">> ", f)
  source(f, print.eval = TRUE)
}
