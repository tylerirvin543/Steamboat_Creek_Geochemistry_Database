# ============================================================
# lst_mineral_equilibration.R
#
# Multicomponent mineral-equilibration diagram (Reed & Spycher 1984):
# plots every candidate mineral's saturation index across the full
# real 25-300 C temperature sweep already stored in PHREEQC_Temp_Sweep
# for the six real Lower Sinter Terrace thermal samples, faceted by
# sample, with each sample's own real measured discharge temperature
# marked. Where multiple minerals' SI curves cross zero at
# approximately the same temperature, that convergence is itself
# evidence for a real, shared equilibration temperature -- a stronger
# test than reading a single mineral's zero-crossing alone (the
# quartz/chalcedony-only approach already used throughout this
# proposal).
#
# This needs zero new PHREEQC execution: PHREEQC_Temp_Sweep already has
# a full 13-step, 11-mineral sweep for all six real flowpath samples
# (confirmed directly against the database before writing this), from
# run_phreeqc_temp_sweep() (scripts/phreeqc/09_run_phreeqc.R).
#
# Adapted from the IGNIS project's own plot_mineral_equilibration()
# (C:/Projects/IGNIS/IGNIS_Geochem_Database_Directory/R/utils_plotting.R),
# restricted to the subset of minerals geothermometrically relevant
# here (the same subset already used throughout this proposal's own
# geothermometry work: Calcite, Dolomite, Quartz, Chalcedony,
# Anhydrite, Fluorite).
#
# Usage:
#   source("scripts/analysis/lst_mineral_equilibration.R")
#   build_mineral_equilibration_figure(con)
# ============================================================

library(DBI)
library(dplyr)
library(ggplot2)

source("scripts/analysis/plot_theme.R")

#' @param sample_ids Integer vector of real sample_ids with a stored
#'   PHREEQC_Temp_Sweep run (default: the six real Lower Sinter Terrace
#'   flowpath thermal samples).
build_mineral_equilibration_figure <- function(con,
    sample_ids = c(816, 815, 821, 825, 820, 822, 818),  # 818 = SBBV, added 2026-10-27 per direct request (not a thermal sample, included for downstream-flowpath context)
    minerals = c("Calcite", "Dolomite", "Quartz", "Chalcedony", "Anhydrite", "Fluorite"),
    out_png = "output/figures/manuscript/mineral_equilibration.png") {

  sweep <- dbGetQuery(con, sprintf("
    SELECT ts.sample_id, l.name AS location_name, ts.temperature_C,
           ts.parameter, ts.value, ps.temperature AS measured_temp
    FROM PHREEQC_Temp_Sweep ts
    JOIN Samples s ON ts.sample_id = s.sample_id
    JOIN Locations l ON s.location_id = l.location_id
    LEFT JOIN PHREEQC_Solutions ps ON ts.sample_id = ps.sample_id
    WHERE ts.sample_id IN (%s) AND ts.parameter LIKE 'SI_%%'
  ", paste(sample_ids, collapse = ",")))

  if (nrow(sweep) == 0) {
    message("  -> No PHREEQC_Temp_Sweep data for the requested samples. Run run_phreeqc_temp_sweep() first.")
    return(invisible(NULL))
  }

  sweep <- sweep |>
    mutate(mineral = gsub("^SI_", "", parameter)) |>
    filter(mineral %in% minerals)

  if (nrow(sweep) == 0) {
    message("  -> None of the requested minerals are present in the sweep. Skipping.")
    return(invisible(NULL))
  }

  measured <- sweep |> distinct(location_name, measured_temp) |> filter(!is.na(measured_temp))

  p <- ggplot(sweep, aes(x = temperature_C, y = value, color = mineral)) +
    annotate("rect", xmin = -Inf, xmax = Inf, ymin = -0.5, ymax = 0.5,
             fill = "#009E73", alpha = 0.10) +
    geom_hline(yintercept = 0, linewidth = 0.6, color = "grey30") +
    geom_vline(data = measured, aes(xintercept = measured_temp),
               linetype = "dashed", color = "grey20", alpha = 0.7) +
    geom_line(linewidth = 0.8, alpha = 0.9) +
    geom_point(size = 0.8, alpha = 0.5) +
    facet_wrap(~ location_name, ncol = 3, scales = "free_y") +
    scale_y_continuous(limits = c(-6, 6), oob = scales::squish) +
    scale_color_manual(values = c(
      Calcite = "#0072B2", Dolomite = "#D55E00", Quartz = "#009E73",
      Chalcedony = "#56B4E9", Anhydrite = "#E69F00", Fluorite = "#CC79A7"
    )) +
    theme_steamboat() +
    theme(legend.position = "bottom") +
    labs(
      title = "Multicomponent mineral-equilibration diagram",
    subtitle = "Saturation index vs. temperature, real PHREEQC_Temp_Sweep output for the six real thermal samples plus SBBV (downstream creek station, included for flowpath context, not itself thermal)",
      x = "Temperature (\u00B0C)",
      y = "Saturation index (SI)",
      color = "Mineral phase",
      caption = "Green band = SI within \u00B10.5 of equilibrium. Dashed vertical line = each sample's own real measured discharge temperature."
    )

  ggsave(out_png, p, width = 10, height = 7, dpi = 300)
  message("  -> Wrote ", out_png)
  invisible(p)
}
