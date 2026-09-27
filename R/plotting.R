# ------------------------------------------------------------------
# plotting.R
# ------------------------------------------------------------------

library(dplyr)
library(tidyr)
library(ggplot2)
library(scales)

#' Cumulative return chart for the Q1 / Q5 / Long-Q1-Short-Q5 legs.
#'
#' @param results output of add_risk_free_and_cumulative()
#' @param title chart title
plot_cumulative_returns <- function(results, title) {
  plot_df <- results %>%
    select(reb_date, cum_q1, cum_q5, cum_ls) %>%
    pivot_longer(cols = starts_with("cum_"), names_to = "Strategy", values_to = "cum_ret") %>%
    mutate(
      Strategy = recode(Strategy,
        cum_q1 = "Q1 (Worst)",
        cum_q5 = "Q5 (Best)",
        cum_ls = "Long Q1 Short Q5"
      )
    )

  ggplot(plot_df, aes(x = reb_date, y = cum_ret, color = Strategy)) +
    geom_line(linewidth = 1) +
    scale_y_continuous(labels = percent_format(accuracy = 1)) +
    labs(title = title, x = "Rebalancing Date", y = "Cumulative Return", color = "Strategy") +
    theme_minimal()
}
