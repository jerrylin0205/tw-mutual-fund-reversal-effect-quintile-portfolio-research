# ------------------------------------------------------------------
# data_prep.R
# Load and clean raw TEJ exports into tidy long-format tables:
#   - fund monthly returns (one row per fund per month)
#   - monthly risk-free rate
# ------------------------------------------------------------------

library(readxl)
library(dplyr)
library(stringr)
library(lubridate)
library(tibble)
library(tidyr)

#' Parse a TEJ "Pro Fund DB" NAV/return export into a tidy fund table.
#'
#' The raw export has two header rows (title row + real column names),
#' one date column, and one column per fund named "<code> <name>".
#' This also collapses duplicate share classes: TISA share classes are
#' dropped, and when a fund has both A (accumulating) and B (dividend)
#' classes, only the A class is kept.
#'
#' @param xlsx_path path to the TEJ export (.xlsx)
#' @param start_date optional lower bound (inclusive) on the date column,
#'   e.g. as.Date("2015-01-30"); NULL keeps the full history in the file
#' @return list(long = tibble(date, fund, ret), fund_info = tibble of
#'   code/name/share_class metadata, dropped = funds excluded as
#'   duplicate share classes)
load_fund_returns <- function(xlsx_path, start_date = NULL) {
  df_raw <- read_excel(xlsx_path, col_names = FALSE)

  new_colnames <- as.character(df_raw[2, ])
  df <- df_raw[-c(1, 2), ]
  colnames(df) <- new_colnames

  fund_info <- tibble(raw_col = colnames(df)[-1]) %>%
    mutate(
      code = str_extract(raw_col, "^\\S+"),
      name = str_trim(str_remove(raw_col, "^\\S+\\s+"))
    )

  fund_parsed <- fund_info %>%
    mutate(
      is_tisa = str_detect(name, "TISA"),
      share_class = case_when(
        str_detect(name, "B類|Bd") ~ "B",
        str_detect(name, "A類|Aa|Ad") ~ "A",
        TRUE ~ NA_character_
      ),
      base_name = name %>%
        str_replace_all("B類|Bd|A類|Aa|Ad", "") %>%
        str_squish()
    )

  fund_core <- fund_parsed %>%
    filter(!is_tisa) %>%
    mutate(is_no_class = is.na(share_class)) %>%
    group_by(base_name) %>%
    mutate(has_A = any(share_class == "A", na.rm = TRUE)) %>%
    # Keep funds with no A/B class distinction; among A/B pairs, keep
    # only the A (accumulating) class and drop the B (dividend) class,
    # since B-class NAV changes are distorted by dividend payouts.
    filter(is_no_class | !(share_class == "B" & has_A)) %>%
    ungroup()

  dropped <- fund_parsed %>%
    filter(!raw_col %in% fund_core$raw_col)

  date_col <- colnames(df)[1]
  keep_cols <- c(date_col, fund_core$raw_col)
  df_core <- df[, colnames(df) %in% keep_cols]

  df_core[[date_col]] <- as.Date(df_core[[date_col]])
  df_core[, -1] <- lapply(df_core[, -1], function(x) as.numeric(as.character(x)) / 100)

  df_long <- df_core %>%
    pivot_longer(cols = -all_of(date_col), names_to = "fund", values_to = "ret") %>%
    rename(date = all_of(date_col)) %>%
    arrange(fund, date)

  if (!is.null(start_date)) {
    df_long <- df_long %>% filter(date >= start_date)
  }

  list(long = df_long, fund_info = fund_core, dropped = dropped)
}

#' Load a monthly risk-free rate proxy from a raw TEJ time-series export
#' (e.g. the 91-180 day commercial paper secondary market rate, series
#' "MB04") into a tidy `date -> annualized rate` table.
#'
#' TEJ single-series exports share the same shape as the fund NAV export:
#' row 1 is a title/series-code string, row 2 is the real header, and the
#' data has a "YYYY/MM" column followed by the rate (percent, e.g. 1.87
#' for 1.87%) as the second column — its label varies by series (e.g.
#' "數值", "無風險利率"), so it is read by position, not by name.
#'
#' @param rf_source path to a raw .csv/.xlsx TEJ export, or an
#'   already-loaded data frame with the two header rows stripped (must
#'   have "年月" as its first column)
#' @param supplement_source optional path to a plain 2-column CSV
#'   (header "年月,數值", no title row) used to fill months not covered by
#'   `rf_source` — e.g. a public Central Bank rate spliced in for months
#'   after the TEJ export's end date. See data/README.md for the exact
#'   provenance of the supplement used in this project and why it is not
#'   a perfect match for the TEJ series.
#' @return tibble(date, rf_annual) with one row per month, rf_annual as a decimal
load_rf_monthly <- function(rf_source, supplement_source = NULL) {
  parse_rf_table <- function(rf_raw) {
    if (colnames(rf_raw)[1] != "年月") {
      stop(
        "load_rf_monthly(): expected the first column to be 年月 (\"YYYY/MM\"), got: ",
        colnames(rf_raw)[1]
      )
    }
    rate_col <- colnames(rf_raw)[2]
    rf_raw %>%
      transmute(
        年月 = trimws(.data[["年月"]]),
        rate_pct = as.numeric(.data[[rate_col]])
      ) %>%
      mutate(date = as.Date(paste0(年月, "/01"), format = "%Y/%m/%d")) %>%
      group_by(date) %>%
      summarise(rf_annual = mean(rate_pct, na.rm = TRUE) / 100, .groups = "drop")
  }

  if (is.character(rf_source)) {
    rf_raw <- if (str_detect(rf_source, "\\.xlsx?$")) {
      raw <- read_excel(rf_source, col_names = FALSE)
      colnames(raw) <- as.character(raw[2, ])
      raw[-c(1, 2), ]
    } else {
      readr::read_csv(rf_source, skip = 2, col_names = c("年月", "數值", "flag"), show_col_types = FALSE)
    }
  } else {
    rf_raw <- rf_source
  }
  primary <- parse_rf_table(rf_raw)

  if (is.null(supplement_source)) {
    return(primary)
  }

  supplement <- parse_rf_table(readr::read_csv(supplement_source, show_col_types = FALSE))
  bind_rows(primary, supplement %>% filter(!date %in% primary$date)) %>%
    arrange(date)
}

#' How many funds have a real (non-NA) return in each calendar year.
#' Context for the survivorship-bias discussion — see
#' fund_exit_diagnostic() for the more direct check.
#'
#' @param df_long tidy tibble(date, fund, ret)
#' @return tibble(year, n_funds_with_data)
fund_coverage_by_year <- function(df_long) {
  df_long %>%
    filter(!is.na(ret)) %>%
    mutate(year = year(date)) %>%
    group_by(year) %>%
    summarise(n_funds_with_data = n_distinct(fund), .groups = "drop") %>%
    arrange(year)
}

#' Per-fund first/last observed (non-NA) return date, and whether that
#' fund's return series stops well before the end of the sample.
#'
#' This is a direct, positive check on survivorship bias, not just
#' context: if `fund_returns.xlsx` only contained funds that were still
#' active as of the export date, every fund would run to the last date in
#' the file. Finding funds whose data stops years early and never resumes
#' is evidence that funds which exited the category mid-sample (most
#' plausibly via liquidation or merger) DO appear in this export with
#' their full pre-exit history intact — i.e. the query was not restricted
#' to currently-surviving funds only. It cannot rule out the narrower case
#' of a fund that both launched and fully exited before the sample's start
#' date, which is simply out of scope for a study starting at `start_date`,
#' not a survivorship bias in the usual sense.
#'
#' @param df_long tidy tibble(date, fund, ret)
#' @param min_gap_months a fund whose last observation is at least this
#'   many months before the sample's last date is flagged as an early exit
#' @return tibble(fund, first_date, last_date, n_obs, is_early_exit)
fund_exit_diagnostic <- function(df_long, min_gap_months = 12) {
  max_date <- max(df_long$date, na.rm = TRUE)
  df_long %>%
    filter(!is.na(ret)) %>%
    group_by(fund) %>%
    summarise(first_date = min(date), last_date = max(date), n_obs = n(), .groups = "drop") %>%
    mutate(is_early_exit = last_date < (max_date %m-% months(min_gap_months))) %>%
    arrange(last_date)
}
