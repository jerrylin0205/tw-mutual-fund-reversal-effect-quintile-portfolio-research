# ------------------------------------------------------------------
# 02_crash_hedge_analysis.R
#
# Checks how the quintile portfolios behaved through the market's
# worst month each year, and whether shorting TW50 futures in
# proportion to estimated beta would have improved crash-period
# returns. Uses the 6-month holding-period backtest, matching the
# original write-up.
#
# Requires scripts/01_run_backtests.R to have been run first.
#
# Run from the project root:
#   Rscript scripts/02_crash_hedge_analysis.R
# ------------------------------------------------------------------

here <- function(...) file.path(getwd(), ...)

source(here("R", "hedge.R"))

backtests <- readRDS(here("output", "backtests.rds"))
bt_6m <- backtests[["6m"]]

tw50_monthly <- load_tw50_monthly(here("data", "raw", "tw50_index.csv"))

crash_years <- c(2020, 2022, 2024, 2025)
crash_analysis <- find_crash_periods(tw50_monthly, bt_6m, crash_years)

betas <- estimate_betas(bt_6m, tw50_monthly, window_months = 6)
cat("6M beta_Q1 =", betas$q1, "\n")
cat("6M beta_Q5 =", betas$q5, "\n")
cat("6M beta_LS =", betas$ls, "\n")

compare_table <- build_hedge_comparison(crash_analysis, betas)
print(compare_table)

write.csv(
  compare_table,
  here("output", "tables", "crash_hedge_comparison.csv"),
  row.names = FALSE, fileEncoding = "UTF-8"
)
