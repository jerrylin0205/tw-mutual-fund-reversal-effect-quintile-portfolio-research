# Install every package this project's R/ code depends on.
# Run once: Rscript scripts/00_install_packages.R

pkgs <- c(
  "readxl", "readr", "dplyr", "stringr", "tibble", "tidyr",
  "slider", "lubridate", "ggplot2", "scales", "purrr"
)

to_install <- pkgs[!pkgs %in% rownames(installed.packages())]
if (length(to_install) > 0) {
  install.packages(to_install, repos = "https://cloud.r-project.org")
} else {
  message("All required packages are already installed.")
}
