## scripts/analysis/injection_pressure_plot.R
##
## Builds a current-vs-newly-authorized pressure/rate figure and a
## tidy summary CSV from Injection_Operating_History, for the
## injection-pressure/eruption-timing question flagged in
## AGENTS.md ("Session 43"). As more NDEP permits are transcribed into
## Injection_Operating_History, this will show successive document
## dates side by side rather than just one permit's before/after.

suppressPackageStartupMessages({
  library(DBI)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
})

build_injection_pressure_plot <- function(con,
                                           out_dir = "output/figures/injection_operations",
                                           derived_dir = "data/derived/injection_operations") {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(derived_dir, recursive = TRUE, showWarnings = FALSE)

  hist <- DBI::dbGetQuery(con, "SELECT * FROM Injection_Operating_History")
  if (nrow(hist) == 0) {
    message("[INJECTION PRESSURE PLOT] No Injection_Operating_History rows yet -- skipping.")
    return(invisible(NULL))
  }

  # Wide summary: one row per well/document, pressure metrics as columns.
  pressure_wide <- hist %>%
    dplyr::filter(parameter == "pressure_psig", well_name != "TOTAL") %>%
    dplyr::select(well_name, metric_type, value, status, document_date, document_name) %>%
    tidyr::pivot_wider(names_from = metric_type, values_from = value)

  readr::write_csv(pressure_wide, file.path(derived_dir, "injection_pressure_summary.csv"))

  rate_wide <- hist %>%
    dplyr::filter(parameter == "rate_gpm") %>%
    dplyr::select(well_name, metric_type, value, value_min, value_max, status, document_date, document_name) %>%
    tidyr::pivot_wider(names_from = metric_type, values_from = value)

  readr::write_csv(rate_wide, file.path(derived_dir, "injection_rate_summary.csv"))

  # Current vs. historic peak vs. new-authorized pressure, per well,
  # for the most recent document on file.
  plot_df <- hist %>%
    dplyr::filter(
      parameter == "pressure_psig",
      well_name != "TOTAL",
      metric_type %in% c("historic_peak", "current", "new_authorized")
    ) %>%
    dplyr::filter(document_date == max(document_date)) %>%
    dplyr::mutate(
      metric_type = factor(metric_type,
                            levels = c("historic_peak", "current", "new_authorized"),
                            labels = c("Historic peak", "Current", "Newly authorized"))
    )

  # Flag any well whose current pressure already exceeds its own newly
  # authorized limit, so it's documented explicitly rather than left
  # only implicit in relative bar lengths.
  exceed_df <- hist %>%
    dplyr::filter(parameter == "pressure_psig", status == "exceeds_new_authorized_limit",
                  document_date == max(document_date))
  exceed_wells <- unique(exceed_df$well_name)
  exceed_note <- if (length(exceed_wells) > 0) {
    paste0(" FLAGGED: ", paste(exceed_wells, collapse = ", "),
           " current pressure already exceeds its own newly-authorized limit.")
  } else {
    ""
  }

  p <- ggplot(plot_df, aes(x = value, y = well_name, fill = metric_type)) +
    geom_col(position = position_dodge(width = 0.75), width = 0.7, na.rm = TRUE) +
    labs(
      title = "Injection wellhead pressure: historic peak vs. current vs. newly authorized",
      subtitle = paste0("NDEP UIC Temporary Permit ", plot_df$permit_number[1],
                         " (issued ", plot_df$document_date[1], ")"),
      x = "Wellhead pressure (psig)", y = NULL, fill = NULL,
      caption = paste(strwrap(paste0(
        "Source: NDEP UIC Temporary Permit UNEV2007204T2025-1, Table B. ",
        "Wells shown idle/production-only have no bars.", exceed_note
      ), width = 100), collapse = "\n")
    ) +
    theme_minimal() +
    theme(plot.caption = ggplot2::element_text(hjust = 0))

  ggsave(file.path(out_dir, "injection_pressure_by_well.png"), p, width = 10, height = 6.5, dpi = 150)

  message("[INJECTION PRESSURE PLOT] Wrote summary CSVs to ", derived_dir,
          " and figure to ", out_dir)
  invisible(list(pressure_wide = pressure_wide, rate_wide = rate_wide, plot = p))
}
