# ------------------------------------------------------------------
# 01_run_backtests.R
#
# Runs the quintile reversal backtest for both holding periods used in
# the write-up (quarterly rebalance / 3-month window, and semi-annual
# rebalance / 6-month window), and writes performance tables + charts
# to output/.
#
# Expected inputs (see data/README.md for exact format):
#   data/raw/fund_returns.xlsx             TEJ Pro Fund DB monthly NAV export
#   data/raw/risk_free_rate.xlsx           TEJ commercial paper rate export
#   data/raw/risk_free_rate_extension.csv  public CBC rate, fills months
#                                           after the TEJ export ends (optional)
#
# Run from the project root:
#   Rscript scripts/01_run_backtests.R
# ------------------------------------------------------------------

here <- function(...) file.path(getwd(), ...)

source(here("R", "data_prep.R"))
source(here("R", "backtest.R"))
source(here("R", "performance.R"))
source(here("R", "plotting.R"))
source(here("R", "costs.R"))

fund_xlsx <- here("data", "raw", "fund_returns.xlsx")
rf_xlsx <- here("data", "raw", "risk_free_rate.xlsx")
rf_extension_csv <- here("data", "raw", "risk_free_rate_extension.csv")
sample_start <- as.Date("2015-01-30")

# One-way subscription cost applied at every rebalance (both legs fully
# turn over each period). See data/README.md for how this was sourced;
# cost_sensitivity_table() below also reports 0%/0.5%/2% for comparison.
one_way_cost <- 0.01

fund_data <- load_fund_returns(fund_xlsx, start_date = sample_start)
rf_monthly <- load_rf_monthly(rf_xlsx, supplement_source = rf_extension_csv)

write.csv(
  fund_coverage_by_year(fund_data$long),
  here("output", "tables", "fund_coverage_by_year.csv"),
  row.names = FALSE, fileEncoding = "UTF-8"
)

exit_diag <- fund_exit_diagnostic(fund_data$long)
write.csv(
  exit_diag,
  here("output", "tables", "fund_exit_diagnostic.csv"),
  row.names = FALSE, fileEncoding = "UTF-8"
)
cat(
  sum(exit_diag$is_early_exit), "of", nrow(exit_diag),
  "funds have their return series stop 12+ months before the sample end",
  "(see output/tables/fund_exit_diagnostic.csv and docs/research_report.md 二.4)\n"
)

specs <- list(
  list(label = "3m", window_months = 3, rebalance_months = c(3, 6, 9, 12)),
  list(label = "6m", window_months = 6, rebalance_months = c(6, 12))
)

backtests <- list()

for (spec in specs) {
  bt <- run_quintile_backtest(fund_data$long, spec$window_months, spec$rebalance_months)
  bt <- add_risk_free_and_cumulative(bt, rf_monthly, spec$window_months)
  backtests[[spec$label]] <- bt

  perf_table <- summarize_performance(bt, spec$window_months)
  print(perf_table)
  write.csv(
    perf_table,
    here("output", "tables", paste0("perf_table_", spec$label, ".csv")),
    row.names = FALSE, fileEncoding = "UTF-8"
  )

  bt_net <- apply_transaction_costs(bt, one_way_cost)
  perf_table_net <- summarize_performance(bt_net, spec$window_months)
  print(perf_table_net)
  write.csv(
    perf_table_net,
    here("output", "tables", paste0("perf_table_", spec$label, "_net.csv")),
    row.names = FALSE, fileEncoding = "UTF-8"
  )

  write.csv(
    cost_sensitivity_table(bt, spec$window_months),
    here("output", "tables", paste0("cost_sensitivity_", spec$label, ".csv")),
    row.names = FALSE, fileEncoding = "UTF-8"
  )

  p <- plot_cumulative_returns(
    bt,
    title = paste0("Cumulative Return of ", spec$label, " Holding-Period Strategies (Gross)")
  )
  ggplot2::ggsave(
    here("output", "figures", paste0("cum_return_", spec$label, ".png")),
    p, width = 10, height = 6, dpi = 150
  )

  p_net <- plot_cumulative_returns(
    bt_net,
    title = paste0("Cumulative Return of ", spec$label, " Holding-Period Strategies (Net of ", one_way_cost * 100, "% Cost)")
  )
  ggplot2::ggsave(
    here("output", "figures", paste0("cum_return_", spec$label, "_net.png")),
    p_net, width = 10, height = 6, dpi = 150
  )
}

# Saved for scripts/02_crash_hedge_analysis.R
saveRDS(backtests, here("output", "backtests.rds"))
