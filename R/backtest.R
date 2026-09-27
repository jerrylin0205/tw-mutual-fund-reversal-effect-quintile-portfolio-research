# ------------------------------------------------------------------
# backtest.R
# Generic quintile reversal/momentum backtest on fund returns, parametrized
# by lookback/holding window length and rebalance frequency so the same
# pipeline runs the 3-month and 6-month specifications.
# ------------------------------------------------------------------

library(dplyr)
library(tidyr)
library(slider)
library(lubridate)

#' Rank funds into quintiles by trailing return and backtest a
#' Long-Q1/Short-Q5 reversal portfolio (plus the two legs on their own).
#'
#' No look-ahead: ranking at `reb_date` uses only `trail_ret`, computed
#' from returns dated on or before `reb_date` (a trailing `slide_dbl`, no
#' `.after`); the holding return uses only returns strictly after `reb_date`
#' (`date > reb_date`). So no future information leaks into fund selection,
#' and no ranking-period information leaks into the holding return.
#'
#' A rebalance date is only scored if its holding window ends on or before
#' the last date actually present in `df_long`. Without this, a holding
#' window running past the end of the data would have its unobserved
#' trailing months silently treated as 0% return by the `complete()` fill
#' below — inventing a "no news is 0% return" data point for a period that
#' simply hasn't happened yet.
#'
#' @param df_long tidy tibble(date, fund, ret) of monthly fund returns
#' @param window_months lookback/holding window length in months (e.g. 3 or 6)
#' @param rebalance_months which calendar months to rebalance on
#'   (e.g. c(3,6,9,12) for quarterly, c(6,12) for semi-annual)
#' @return tibble with one row per rebalance date: reb_date, hold_start,
#'   hold_end, q1_ret, q5_ret, ls_ret, n_q1, n_q5
run_quintile_backtest <- function(df_long, window_months, rebalance_months) {
  max_available_date <- max(df_long$date, na.rm = TRUE)

  df_lookback <- df_long %>%
    group_by(fund) %>%
    arrange(date) %>%
    mutate(
      trail_ret = slide_dbl(
        ret,
        .before = window_months - 1,
        .complete = TRUE,
        .f = ~ if (any(is.na(.x)) || length(.x) < window_months) {
          NA_real_
        } else {
          prod(1 + .x) - 1
        }
      )
    ) %>%
    ungroup() %>%
    filter(month(date) %in% rebalance_months, !is.na(trail_ret))

  df_rank <- df_lookback %>%
    group_by(date) %>%
    mutate(quintile = ntile(trail_ret, 5)) %>% # 1 = worst, 5 = best
    ungroup()

  rebalance_dates <- df_rank %>%
    distinct(date) %>%
    arrange(date) %>%
    pull(date)

  results <- lapply(rebalance_dates, function(reb_date) {
    this_rank <- df_rank %>% filter(date == reb_date)
    q1_funds <- this_rank %>% filter(quintile == 1) %>% pull(fund)
    q5_funds <- this_rank %>% filter(quintile == 5) %>% pull(fund)

    if (length(q1_funds) == 0 || length(q5_funds) == 0) return(NULL)

    hold_start <- reb_date %m+% months(1)
    hold_end <- reb_date %m+% months(window_months)
    if (hold_end > max_available_date) return(NULL) # holding window not fully observed yet

    # Built with %m+% (not seq.Date(by = "month")) so it clamps to
    # month-end consistently with hold_start/hold_end above; reb_date's
    # day-of-month varies with the trading calendar (e.g. the 28th vs the
    # 31st), and mixing the two arithmetics can misalign this list against
    # the real trading dates in df_long.
    period_months <- reb_date %m+% months(seq_len(window_months))

    holding_return <- function(funds) {
      df_long %>%
        filter(fund %in% funds, date > reb_date, date <= hold_end) %>%
        # Funds missing a month's NAV get 0% for that month rather than
        # being skipped, which would otherwise inflate the compounded
        # return (survivorship-style bias).
        complete(fund, date = period_months, fill = list(ret = 0)) %>%
        group_by(fund) %>%
        summarise(cum_ret = prod(1 + ret) - 1, .groups = "drop") %>%
        summarise(mean(cum_ret)) %>%
        pull(1)
    }

    q1_ret <- holding_return(q1_funds)
    q5_ret <- holding_return(q5_funds)
    if (is.na(q1_ret) || is.na(q5_ret)) return(NULL)

    tibble(
      reb_date = reb_date,
      hold_start = hold_start,
      hold_end = hold_end,
      q1_ret = q1_ret,
      q5_ret = q5_ret,
      ls_ret = q1_ret - q5_ret,
      n_q1 = length(q1_funds),
      n_q5 = length(q5_funds)
    )
  })

  bind_rows(results) %>% arrange(reb_date)
}

#' Attach the matching risk-free rate (compounded to the holding-period
#' length) to each backtest row, and add cumulative return columns.
#'
#' @param results output of run_quintile_backtest()
#' @param rf_monthly tibble(date, rf_annual) from load_rf_monthly()
#' @param window_months holding period length in months, must match the
#'   value used in run_quintile_backtest()
add_risk_free_and_cumulative <- function(results, rf_monthly, window_months) {
  rf_by_ym <- rf_monthly %>% mutate(ym = format(date, "%Y/%m"))

  joined <- results %>%
    mutate(ym = format(reb_date, "%Y/%m")) %>%
    arrange(reb_date) %>%
    left_join(rf_by_ym %>% select(ym, rf_annual), by = "ym")

  n_missing <- sum(is.na(joined$rf_annual))
  if (n_missing > 0) {
    # Rebalance dates past the end of the rf series (e.g. the source is a
    # few months stale) carry forward the last known rate rather than the
    # full-sample average, since money-market rates trend across cycles.
    last_known <- rf_by_ym %>% filter(!is.na(rf_annual)) %>% arrange(date) %>% tail(1)
    warning(
      n_missing, " rebalance date(s) have no matching risk-free rate ",
      "(source data ends before them); carrying forward the last known ",
      "rate from ", format(last_known$date, "%Y-%m"), " (", round(last_known$rf_annual * 100, 2), "%)."
    )
    joined$rf_annual[is.na(joined$rf_annual)] <- last_known$rf_annual
  }

  joined %>%
    mutate(
      rf_hold = (1 + rf_annual)^(window_months / 12) - 1,
      cum_q1 = cumprod(1 + q1_ret) - 1,
      cum_q5 = cumprod(1 + q5_ret) - 1,
      cum_ls = cumprod(1 + ls_ret) - 1
    ) %>%
    select(-ym)
}
