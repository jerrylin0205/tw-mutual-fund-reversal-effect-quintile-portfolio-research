# Data

Raw data is **not** included in this repository — it comes from TEJ (Taiwan
Economic Journal / 台灣經濟新報), a licensed commercial database, and its
terms of use do not permit redistribution. `data/raw/` is git-ignored; place
your own exports there before running anything in `scripts/`.

## Expected files

### `data/raw/fund_returns.xlsx`

TEJ Pro Fund DB export of monthly NAV returns for Taiwan-domiciled equity
mutual funds.

- Row 1: a title row (ignored)
- Row 2: real column headers
- Column 1: month-end date
- Remaining columns: one per fund, named `"<code> <name>"`, values as a
  percentage (e.g. `1.23` for 1.23%)

`R/data_prep.R::load_fund_returns()` drops TISA share classes and, for funds
with both an A (accumulating) and B (dividend) class, keeps only the A class.

### `data/raw/risk_free_rate.xlsx`

A raw single-series TEJ time-series export used as the risk-free rate
proxy. This project uses the **91–180 day commercial paper secondary
market rate** (TEJ series `MB04`, 台灣-貨幣市場利率-商業本票-次級市場-91-180天),
which is the standard risk-free proxy convention in Taiwan academic
asset-pricing research (analogous to the 1-month T-bill in US Fama-French
data) — a traded money-market rate, unlike a bank-posted deposit rate.

Same raw shape as `fund_returns.xlsx`: row 1 is a title/series-code string,
row 2 is the real header, then one row per month with `年月` ("YYYY/MM")
followed by the rate as a percentage (e.g. `1.87` for 1.87%) in the second
column — its label varies by series (e.g. `數值`), so `load_rf_monthly()`
reads it by position. A `.csv` export with the same 2-header-row shape is
also accepted.

If the series ends before your fund data's last rebalance date,
`add_risk_free_and_cumulative()` carries the last known rate forward for
the missing trailing months and emits a warning saying how many periods
were affected — but see the next section for a better fix than relying on
that fallback.

### `data/raw/risk_free_rate_extension.csv` (tracked in git — not TEJ data)

The TEJ `MB04` export used in this project stops at 2024/12, before the
fund data's last few rebalance dates (2025). This file fills that gap with
the **31–90 day commercial paper secondary market rate** from the [Central
Bank of Taiwan's public key-indicator statistics](https://www.cbc.gov.tw/public/data/economic/statistics/key/interest.pdf)
(retrieved 2026-09-27) — a different maturity bucket than TEJ's 91–180 day
series (the two agree to within ~0.12pp at their one overlapping month,
2024/12: 1.87% vs 1.75%, a normal term-premium gap), so it's a reasonable
but not exact stand-in for the missing months. Plain 2-column CSV, no
title row: `年月,數值`. Pass it as `load_rf_monthly(rf_source,
supplement_source = "data/raw/risk_free_rate_extension.csv")` — it only
fills months the primary source doesn't have, never overrides TEJ's own
numbers. Because this is compiled from public government statistics
rather than a TEJ export, it's the one file under `data/raw/` that's
tracked in git.

### `data/raw/tw50_index.csv`

Daily TW50 total-return index export with at least these columns:

| 日期 | 報酬指數值 |
|------|-------------|
| 2020/03/19 | ... |

Used only by `scripts/02_crash_hedge_analysis.R` for the crash-period /
beta-hedge analysis.

## Regenerating results

```r
Rscript scripts/00_install_packages.R
Rscript scripts/01_run_backtests.R
Rscript scripts/02_crash_hedge_analysis.R
```

Outputs (performance tables + charts) are written to `output/`.
