# ------------------------------------------------------------
# 05_recommendation_report.R
#
# Purpose:
# Take the Monte Carlo sampling-frequency summary (04) and identify
# the coarsest chemistry-sampling interval that keeps error under an
# agreed threshold. The threshold is a scientific/management decision,
# not a statistical one — it is a required argument here rather than
# a hard-coded default, so a recommendation is never silently produced
# without an explicit basis.
#
# Writes:
#   data/derived/sampling_frequency/sampling_frequency_summary_<date>.csv
#   output/figures/sampling_frequency/error_vs_frequency_<date>.png
# ------------------------------------------------------------

library(ggplot2)

#' @param summary_tbl output of summarize_sampling_frequency() (04)
#' @param rmse_threshold_mgL max acceptable mean RMSE in chloride (mg/L)
#' @param flux_pct_threshold max acceptable mean |flux percent error|
recommend_sampling_frequency <- function(summary_tbl,
                                          rmse_threshold_mgL = NULL,
                                          flux_pct_threshold = NULL) {

  if (is.null(rmse_threshold_mgL) && is.null(flux_pct_threshold)) {
    stop(
      "Provide at least one of `rmse_threshold_mgL` or `flux_pct_threshold` — ",
      "there is no universally 'acceptable' error; this must be set with the PI ",
      "based on the scientific question (e.g., what Cl discharge change is ",
      "meaningful to detect)."
    )
  }

  ok <- rep(TRUE, nrow(summary_tbl))
  if (!is.null(rmse_threshold_mgL)) {
    ok <- ok & (summary_tbl$rmse_mean <= rmse_threshold_mgL)
  }
  if (!is.null(flux_pct_threshold)) {
    ok <- ok & (summary_tbl$flux_pct_error_mean <= flux_pct_threshold)
  }

  passing <- summary_tbl[ok, ]

  if (nrow(passing) == 0) {
    message("No candidate frequency meets the specified threshold(s); ",
            "even daily sampling may be insufficient given current model error.")
    return(NULL)
  }

  passing[which.max(passing$frequency_days), ]
}

#' Produce the summary CSV + plot + printed recommendation
build_recommendation_report <- function(summary_tbl,
                                         rmse_threshold_mgL = NULL,
                                         flux_pct_threshold = NULL,
                                         out_dir_data = "data/derived/sampling_frequency",
                                         out_dir_fig = "output/figures/sampling_frequency") {

  dir.create(out_dir_data, recursive = TRUE, showWarnings = FALSE)
  dir.create(out_dir_fig, recursive = TRUE, showWarnings = FALSE)
  stamp <- format(Sys.Date(), "%Y%m%d")

  write.csv(
    summary_tbl,
    file.path(out_dir_data, paste0("sampling_frequency_summary_", stamp, ".csv")),
    row.names = FALSE
  )

  p <- ggplot(summary_tbl, aes(x = frequency_days, y = rmse_mean)) +
    geom_ribbon(aes(ymin = rmse_mean - 0, ymax = rmse_p95), alpha = 0.15) +
    geom_line() +
    geom_point() +
    scale_x_continuous(breaks = summary_tbl$frequency_days) +
    labs(
      x = "Candidate chemistry-sampling interval (days)",
      y = "Chloride prediction RMSE (mg/L)\n(point = mean across MC draws, band = 95th pct)",
      title = "Chloride prediction error vs. sampling frequency"
    ) +
    theme_minimal()

  ggsave(file.path(out_dir_fig, paste0("error_vs_frequency_", stamp, ".png")),
         p, width = 7, height = 5, dpi = 150)

  recommendation <- NULL
  if (!is.null(rmse_threshold_mgL) || !is.null(flux_pct_threshold)) {
    recommendation <- recommend_sampling_frequency(summary_tbl, rmse_threshold_mgL, flux_pct_threshold)
    if (!is.null(recommendation)) {
      message(
        "Recommended coarsest sampling interval: ", recommendation$frequency_days, " days ",
        "(mean RMSE = ", round(recommendation$rmse_mean, 2), " mg/L, ",
        "mean |flux error| = ", round(recommendation$flux_pct_error_mean, 1), "%)"
      )
    }
  } else {
    message("No threshold supplied — summary and plot written, but no recommendation made. ",
            "Call recommend_sampling_frequency() directly once a threshold is agreed with the PI.")
  }

  list(summary = summary_tbl, recommendation = recommendation, plot = p)
}
