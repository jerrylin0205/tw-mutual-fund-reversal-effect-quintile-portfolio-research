# ------------------------------------------------------------------
# performance.R
# Annualized performance stats + a significance test on the long-short
# leg (the original analysis reported returns/Sharpe only, with no
# significance test).
# ------------------------------------------------------------------

library(dplyr)

#' Annualize a series of non-overlapping period returns.
#'
#' @param ret_vec numeric vector of period returns (e.g. one per rebalance)
#' @param period_months length of each period in months
calc_perf <- function(ret_vec, period_months) {
  n_periods <- length(ret_vec)
  total_years <- n_periods * (period_months / 12)

  list(
    annual_return = prod(1 + ret_vec)^(1 / total_years) - 1,
    annual_vol = sd(ret_vec) * sqrt(12 / period_months)
  )
}

#' Build the Q1 / Q5 / Long-Q1-Short-Q5 performance table: annualized
#' return, vol, risk-free rate, excess return, Sharpe ratio, and a
#' t-test on whether the long-short leg's mean return differs from zero.
#'
#' @param results output of add_risk_free_and_cumulative()
#' @param window_months holding period length in months
summarize_performance <- function(results, window_months) {
  perf_q1 <- calc_perf(results$q1_ret, window_months)
  perf_q5 <- calc_perf(results$q5_ret, window_months)
  perf_ls <- calc_perf(results$ls_ret, window_months)

  n_periods <- length(results$rf_hold)
  total_years <- n_periods * (window_months / 12)
  ann_rf <- prod(1 + results$rf_hold)^(1 / total_years) - 1

  ls_ttest <- t.test(results$ls_ret, mu = 0)

  tibble(
    Strategy = c("Q1 (Worst)", "Q5 (Best)", "Long Q1 Short Q5"),
    Ann_Return = c(perf_q1$annual_return, perf_q5$annual_return, perf_ls$annual_return),
    Ann_Vol = c(perf_q1$annual_vol, perf_q5$annual_vol, perf_ls$annual_vol),
    Ann_Rf = ann_rf,
    Ann_Excess = c(
      perf_q1$annual_return - ann_rf,
      perf_q5$annual_return - ann_rf,
      perf_ls$annual_return - ann_rf
    ),
    Sharpe_Excess = Ann_Excess / Ann_Vol,
    LS_tstat = c(NA, NA, unname(ls_ttest$statistic)),
    LS_pvalue = c(NA, NA, ls_ttest$p.value)
  )
}
