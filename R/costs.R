# ------------------------------------------------------------------
# costs.R
# Transaction-cost overlay. The backtest fully turns over each leg's
# fund basket at every rebalance (the ranking changes), so every period
# incurs a fresh round of buying into a new set of funds.
# ------------------------------------------------------------------

library(dplyr)

#' Deduct a one-way subscription cost from each leg's return at every
#' rebalance. Assumes redemption itself is free, which is standard for
#' front-load domestic equity funds held past any short-term
#' redemption-penalty window (a few weeks) — a safe assumption here since
#' the holding period is 3 or 6 months. See data/README.md / the research
#' report for the sourcing and reasoning behind the cost assumption.
#'
#' @param results output of add_risk_free_and_cumulative()
#' @param one_way_cost subscription cost as a decimal, e.g. 0.01 for 1%
#' @return results with q1_ret/q5_ret/ls_ret/cum_* replaced by net-of-cost
#'   values; the gross values are kept as q1_ret_gross/q5_ret_gross/ls_ret_gross
apply_transaction_costs <- function(results, one_way_cost) {
  results %>%
    mutate(
      q1_ret_gross = q1_ret,
      q5_ret_gross = q5_ret,
      ls_ret_gross = ls_ret,
      q1_ret = (1 + q1_ret) * (1 - one_way_cost) - 1,
      q5_ret = (1 + q5_ret) * (1 - one_way_cost) - 1,
      ls_ret = q1_ret - q5_ret,
      cum_q1 = cumprod(1 + q1_ret) - 1,
      cum_q5 = cumprod(1 + q5_ret) - 1,
      cum_ls = cumprod(1 + ls_ret) - 1
    )
}

#' Performance table across several one-way cost assumptions, for a
#' sensitivity view (0% = gross).
#'
#' @param results output of add_risk_free_and_cumulative()
#' @param window_months holding period length in months
#' @param one_way_costs vector of one-way cost assumptions to try
cost_sensitivity_table <- function(results, window_months, one_way_costs = c(0, 0.005, 0.01, 0.02)) {
  bind_rows(lapply(one_way_costs, function(c) {
    net <- if (c == 0) results else apply_transaction_costs(results, c)
    summarize_performance(net, window_months) %>%
      mutate(one_way_cost = c, .before = 1)
  }))
}
