# config.R: file locations and run settings. Edit paths here and nowhere else.
# Run everything from the project root (the folder that contains this file).

paths <- list(
  census        = "data/raw/CENSUS_with_values.csv",
  lgd_lookup    = "data/raw/2021_data_zone_to_old_lgd_and_urban_rural_classification.xlsx",
  aft_model     = "data/raw/aft_model_info.xlsx",
  lifetable     = "data/raw/NI_2021_lifetable.xlsx",
  shapefile     = "data/raw/DZ2021.shp",             # needs the .dbf, .shx and .prj files next to it
  coa_distances = "data/processed/coa_nearest_ambulance.csv"   # made by scripts/01_station_distances.R
)

# Number of simulated years per data zone. The dissertation results use 1000.
# For a quick test use N_SIM_YEARS=20 Rscript run_all.R
n_sim_years <- as.integer(Sys.getenv("N_SIM_YEARS", "1000"))

check_inputs <- function(include_coa = TRUE) {
  need <- unlist(paths)
  if (!include_coa) need <- need[names(need) != "coa_distances"]
  missing <- need[!file.exists(need)]
  if (length(missing) > 0) {
    stop("Missing input file(s):\n  ", paste(missing, collapse = "\n  "),
         "\nSee data/README.md for where each file comes from.", call. = FALSE)
  }
  invisible(TRUE)
}
