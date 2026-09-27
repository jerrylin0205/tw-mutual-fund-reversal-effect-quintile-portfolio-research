# ------------------------------------------------------------------
# hedge.R
# Crash-period behaviour of the quintile portfolios, and a beta-hedge
# overlay (short TAIEX 50 futures in proportion to estimated beta).
# ------------------------------------------------------------------

library(readr)
library(dplyr)
library(lubridate)
library(tidyr)
library(slider)

#' Turn a daily TW50 total-return index export into month-end returns.
#'
#' @param csv_path path to the TW50 daily index .csv
load_tw50_monthly <- function(csv_path) {
  tw50_daily <- read_csv(csv_path, show_col_types = FALSE)

  tw50_daily %>%
    mutate(日期 = as.Date(日期, format = "%Y/%m/%d")) %>%
    arrange(日期) %>%
    mutate(year = year(日期), month = month(日期)) %>%
    group_by(year, month) %>%
    summarise(
      month_end = max(日期),
      tri_end = last(報酬指數值),
      .groups = "drop"
    ) %>%
    arrange(month_end) %>%
    mutate(mkt_ret = tri_end / lag(tri_end) - 1)
}

#' For each of the given years, find the single worst-return month and
#' work out which backtest holding period that crash month falls into.
#'
#' @param tw50_monthly output of load_tw50_monthly()
#' @param results backtest results (must have hold_start/hold_end), i.e.
#'   the output of add_risk_free_and_cumulative()
#' @param years years to scan for a crash month
find_crash_periods <- function(tw50_monthly, results, years) {
  crash_months <- tw50_monthly %>%
    filter(year %in% years) %>%
    group_by(year) %>%
    slice_min(order_by = mkt_ret, n = 1, with_ties = FALSE) %>%
    ungroup() %>%
    mutate(crash_date = month_end, crash_ret = mkt_ret)

  crash_months %>%
    rowwise() %>%
    mutate(
      reb_for_crash = results %>%
        filter(crash_date >= hold_start, crash_date <= hold_end) %>%
        slice(1) %>%
        pull(reb_date) %>%
        {if (length(.) == 0) as.Date(NA) else .}
    ) %>%
    ungroup() %>%
    left_join(results, by = c("reb_for_crash" = "reb_date"))
}

#' Estimate each leg's beta to the market over the same holding-period
#' length as the backtest, using non-overlapping compounded market
#' returns aligned to each rebalance date.
#'
#' @param results backtest results with q1_ret/q5_ret/ls_ret
#' @param tw50_monthly output of load_tw50_monthly()
#' @param window_months holding period length in months
estimate_betas <- function(results, tw50_monthly, window_months) {
  market_window <- tw50_monthly %>%
    mutate(
      ym = format(month_end, "%Y-%m"),
      mkt_window_ret = slide_dbl(
        1 + mkt_ret,
        .f = ~ prod(.x) - 1,
        .before = window_months - 1,
        .complete = TRUE
      )
    ) %>%
    filter(!is.na(mkt_window_ret)) %>%
    select(ym, mkt_window_ret)

  beta_df <- results %>%
    mutate(ym = format(reb_date, "%Y-%m")) %>%
    left_join(market_window, by = "ym") %>%
    filter(!is.na(mkt_window_ret))

  list(
    q1 = unname(coef(lm(q1_ret ~ mkt_window_ret, data = beta_df))[2]),
    q5 = unname(coef(lm(q5_ret ~ mkt_window_ret, data = beta_df))[2]),
    ls = unname(coef(lm(ls_ret ~ mkt_window_ret, data = beta_df))[2]),
    beta_df = beta_df
  )
}

#' Remove beta * market crash-month return from a holding-period return,
#' i.e. the return the portfolio would have earned if it had shorted
#' beta units of the index going into the crash.
hedge_one_beta <- function(hold_ret, crash_mkt_ret, beta) {
  (1 + hold_ret) / (1 + beta * crash_mkt_ret) - 1
}

#' Build the before/after-hedge comparison table for the crash periods.
#'
#' @param crash_analysis output of find_crash_periods()
#' @param betas output of estimate_betas()
build_hedge_comparison <- function(crash_analysis, betas) {
  crash_analysis %>%
    left_join(betas$beta_df %>% select(reb_date, mkt_window_ret), by = c("reb_for_crash" = "reb_date")) %>%
    mutate(
      q1_hedged = hedge_one_beta(q1_ret, mkt_window_ret, betas$q1),
      q5_hedged = hedge_one_beta(q5_ret, mkt_window_ret, betas$q5),
      ls_hedged = hedge_one_beta(ls_ret, mkt_window_ret, betas$ls)
    ) %>%
    select(
      crash_date, crash_ret, reb_for_crash,
      q1_ret, q1_hedged, q5_ret, q5_hedged, ls_ret, ls_hedged
    )
}
