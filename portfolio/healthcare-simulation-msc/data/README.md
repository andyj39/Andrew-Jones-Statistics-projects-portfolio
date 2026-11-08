# Data

The input files are not stored in this repository. The scripts expect these five files in `data/raw/`. The file names are set in `config.R`.

| File | What it holds | Source |
|---|---|---|
| `CENSUS_with_values.csv` | One row per Data Zone, five-year age band and sex (143,640 rows = 3,780 × 19 × 2). Columns: Data Zone code and name, the population `count`, the age band, the sex, and `p`, the yearly probability of a witnessed ventricular fibrillation arrest for that age band and sex | Counts from the [NISRA Census 2021 flexible table builder](https://build.nisra.gov.uk/) (age, sex and Data Zone). `p` is derived from Belfast WHO MONICA data for 1985 to 1987, as in Cairns et al. (2011); see section 3.4 of the dissertation |
| `2021_data_zone_to_old_lgd_and_urban_rural_classification.xlsx` | Lookup from each 2021 Data Zone to its 1992 district (the 26 "old LGDs") and to urban or rural status | NISRA, [Census 2021 output geography](https://www.nisra.gov.uk/statistics/census-2021-results/census-output-geography) lookups |
| `aft_model_info.xlsx` | Coefficients of the ambulance response time model, one row per district (first sheet) | The fitted models of Cairns et al. (2011). Not included in this repository |
| `NI_2021_lifetable.xlsx` | National life tables for Northern Ireland, 2021 to 2023 | Office for National Statistics, [National life tables: Northern Ireland](https://www.ons.gov.uk/peoplepopulationandcommunity/birthsdeathsandmarriages/lifeexpectancies/datasets/nationallifetablesnorthernirelandreferencetables) |
| `DZ2021.shp` with its `.dbf`, `.shx` and `.prj` files | Data Zone boundaries (3,780 polygons) | NISRA, [Data Zone boundaries in GIS format](https://www.nisra.gov.uk/publications/data-zone-boundaries-gis-format). Contains Ordnance Survey of Northern Ireland information licensed under the Open Government Licence v3.0 |

The discrete-event simulation (`des/ambulance_handover_des.Rmd`) needs one more file:

| File | What it holds | Source |
|---|---|---|
| `NHS_Time_of_day_ambulance_distribution.xlsx` | Sheet "Time of day distribution": A&E attendances by weekday and hour, including those arriving by ambulance. Used to shape the weekly pattern of call arrivals | NHS England, time of day ambulance attendance data, 2024/25 (references [66] and [107] in the dissertation). Save it under this name or change `nhs_file` in the script |

The code reads some workbooks by sheet number, so a re-downloaded file with a different sheet order needs `scripts/02_simulate_arrests.R` and `scripts/03_inputs_and_allocation.R` adjusting:

- lookup workbook: sheet 4 (the administrative geography lookup, with the 1992 district) and sheet 5 (urban or rural status of each Data Zone)
- `aft_model_info.xlsx`: sheet 1 (`AFT_parameters_NI_amb_model`, one row per district)
- life table: the sheet named `2021-2023`

## Made by the code

`data/processed/coa_nearest_ambulance.csv` is written by `scripts/01_station_distances.R`. It has one row per Data Zone with the distance to the nearest and second-nearest ambulance station as ln(miles + 1), and a flag for a nearest station within 2 miles. The station list is 35 Northern Ireland Ambulance Service sites (the stations plus the ambulance headquarters) taken from a Freedom of Information reply and checked against a 2025 Northern Ireland Assembly written answer (AQW 25708/22-27). The script geocodes the names with OpenStreetMap and overrides four of them (Broadway, Magherafelt, Carrick and the headquarters) with hand-checked coordinates. Distances are straight-line distances between Data Zone centroids and stations in the Irish Grid projection (EPSG:29902).
