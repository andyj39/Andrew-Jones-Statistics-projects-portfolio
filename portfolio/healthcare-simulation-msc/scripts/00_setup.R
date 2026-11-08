# 00_setup.R
#
# Packages, random seed and output folders.
#
# Needs : config.R
# Makes : loaded packages, seed

if (!exists("paths")) source("config.R")

pkgs <- c("readxl", "dplyr", "tidyr", "sf", "tibble", "ggplot2", "scales",
          "plotly", "purrr", "ggpattern", "kableExtra")
for (p in pkgs) if (!requireNamespace(p, quietly = TRUE)) install.packages(p)
invisible(lapply(pkgs, library, character.only = TRUE))

set.seed(12345)

dir.create("outputs/tables", recursive = TRUE, showWarnings = FALSE)
