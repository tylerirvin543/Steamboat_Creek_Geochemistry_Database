## scripts/analysis/injection_pressure_plot.R
##
## Builds ONE combined current-vs-newly-authorized pressure/rate figure
## (two stacked panels, pressure then rate, same well order) and a tidy
## summary CSV from Injection_Operating_History, for the
## injection-pressure/eruption-timing question flagged in
## AGENTS.md ("Session 43"). Previously two separate figures
## (injection_pressure_by_well.png, injection_rate_by_well.png); merged
## into one PNG on 2026-10-27 per direct request ("only have one graph
## about the Ormat pressure increase for injection wells"). As more
## NDEP permits are transcribed into Injection_Operating_History, this
## will show successive document dates side by side rather than just
## one permit's before/after.
suppressPackageStartupMessages({
  library(DBI)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(patchwork)
})
#' Build the single combined injection pressure + rate figure, and
#' write the two tidy summary CSVs (pressure, rate) that back it.
#'
#' @return Invisibly, a list with `pressure_wide`, `rate_wide`, and
#'   `plot` (the combined patchwork object).
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
  pressure_plot_df <- hist %>%
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
  well_order <- pressure_plot_df %>%
    dplyr::filter(metric_type == "Newly authorized") %>%
    dplyr::arrange(value) %>%
    dplyr::pull(well_name)
  if (length(well_order) > 0) {
    pressure_plot_df$well_name <- factor(pressure_plot_df$well_name, levels = well_order)
  }
  p_pressure <- ggplot(pressure_plot_df, aes(x = value, y = well_name, fill = metric_type)) +
    geom_col(position = position_dodge(width = 0.75), width = 0.7, na.rm = TRUE) +
    labs(
      title = "A. Wellhead pressure: historic peak vs. current vs. newly authorized",
      x = "Wellhead pressure (psig)", y = NULL, fill = NULL
    ) +
    theme_minimal()
  # Companion panel: current production flow vs. maximum flow at the
  # allowable pressure, per injection well, same permit document and
  # same well order as the pressure panel above (for direct, row-by-row
  # comparison). Shows how much headroom each well has between what it
  # currently injects (flow_full_production) and what the pressure
  # limit alone would physically allow (max_flow_at_allowable_pressure)
  # -- a well already close to that ceiling has less real headroom than
  # the newly authorized pressure increase alone would suggest.
  rate_plot_df <- hist %>%
    dplyr::filter(parameter == "rate_gpm", well_name != "TOTAL",
                  metric_type %in% c("flow_full_production", "max_flow_at_allowable_pressure")) %>%
    dplyr::filter(document_date == max(document_date)) %>%
    dplyr::mutate(
      metric_type = factor(metric_type,
        levels = c("flow_full_production", "max_flow_at_allowable_pressure"),
        labels = c("Current (full production)", "Max at allowable pressure")),
      well_name = if (length(well_order) > 0) factor(well_name, levels = well_order) else well_name
    ) %>%
    dplyr::filter(!is.na(well_name))
  p_rate <- ggplot(rate_plot_df, aes(x = value, y = well_name, fill = metric_type)) +
    geom_col(position = position_dodge(width = 0.75), width = 0.7, na.rm = TRUE) +
    labs(
      title = "B. Injection rate: current (full production) vs. the pressure-limited maximum",
      x = "Injection rate (gpm)", y = NULL, fill = NULL
    ) +
    theme_minimal()
  p <- patchwork::wrap_plots(p_pressure, p_rate, ncol = 1) +
    patchwork::plot_annotation(
      title = "Injection wellhead pressure and rate, per well",
      subtitle = paste0("NDEP UIC Temporary Permit ", pressure_plot_df$permit_number[1],
                         " (issued ", pressure_plot_df$document_date[1], "), Tables B and C"),
      caption = paste(strwrap(paste0(
        "Wells shown idle/production-only have no bars in one or both panels. ",
        "A well whose current rate (panel B) already sits close to its own pressure-limited maximum has little real ",
        "headroom left, regardless of the newly authorized field-wide total (panel A).", exceed_note
      ), width = 130), collapse = "\n"),
      theme = theme(plot.caption = ggplot2::element_text(hjust = 0))
    )
  ggsave(file.path(out_dir, "injection_pressure_and_rate.png"), p, width = 10, height = 11, dpi = 150)
  message("[INJECTION PRESSURE PLOT] Wrote summary CSVs to ", derived_dir,
          " and combined figure to ", out_dir)
  invisible(list(pressure_wide = pressure_wide, rate_wide = rate_wide, plot = p))
}
