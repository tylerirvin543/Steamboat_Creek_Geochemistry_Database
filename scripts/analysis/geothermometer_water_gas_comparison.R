# ============================================================
# geothermometer_water_gas_comparison.R
#
# Purpose:
# Puts this project's existing water geothermometers (Na/K-Giggenbach,
# Na/K-Fournier, quartz, chalcedony -- see docs/data/geothermometer_by_site.csv,
# built in run_pipeline.R from calculate_activity_geothermometers() +
# the PHREEQC temperature-sweep zero-SI-crossing) side by side with the
# new gas geothermometer (D'Amore-Panichi, scripts/phreeqc/
# 13_gas_geothermometry.R via scripts/analysis/gas_air_correction.R) for
# the first time. The headline comparison is the one real co-located
# point (NV26-1 gas / SBF_0001 water); the broader per-sample water
# geothermometer record is shown for context.
# ============================================================

library(dplyr)
library(ggplot2)

source("scripts/analysis/plot_theme.R")
source("scripts/analysis/gas_air_correction.R")

#' Build the combined water+gas geothermometer comparison table.
#'
#' @param con DBI connection.
#' @param water_csv Path to the already-exported per-sample water
#'   geothermometer CSV (docs/data/geothermometer_by_site.csv).
get_geothermometer_water_gas_table <- function(
    con, water_csv = "docs/data/geothermometer_by_site.csv") {

  water <- if (file.exists(water_csv)) {
    readr::read_csv(water_csv, show_col_types = FALSE)
  } else {
    message("[geothermometer_comparison] ", water_csv, " not found -- re-exporting from the database is required first.")
    return(invisible(NULL))
  }

  water_long <- water |>
    tidyr::pivot_longer(
      cols = c(T_NaK_gigg_activity, T_NaK_four_activity, T_quartz_C, T_chalcedony_C),
      names_to = "method", values_to = "estimated_temp_C"
    ) |>
    mutate(method = recode(method,
      T_NaK_gigg_activity = "Water: Na/K (Giggenbach)",
      T_NaK_four_activity = "Water: Na/K (Fournier)",
      T_quartz_C = "Water: Quartz",
      T_chalcedony_C = "Water: Chalcedony"
    )) |>
    filter(!is.na(estimated_temp_C)) |>
    mutate(sample_id = as.character(sample_id)) |>
    select(sample_id, location_name, site_type, measured_temp_C = measured_temp_c, method, estimated_temp_C)

  gas <- analyze_fischer_gas_samples(con)
  if (is.null(gas)) {
    message("[geothermometer_comparison] No gas-geothermometer results -- returning water-only table.")
    return(invisible(water_long))
  }

  gas_long <- gas |>
    transmute(
      sample_id = sample_label, location_name = sample_label, site_type = "fumarole",
      measured_temp_C = field_temp_c, method = "Gas: D'Amore-Panichi",
      estimated_temp_C = dap_temperature_C
    )

  bind_rows(water_long, gas_long)
}

#' Headline table: every geothermometer method's estimate at the one
#' real co-located point (NV26-1 gas / SBF_0001 water).
build_geothermometer_fissure_point_table <- function(
    con, out_csv = "data/derived/gas_analysis/geothermometer_fissure_point_comparison.csv") {

  combined <- get_geothermometer_water_gas_table(con)
  if (is.null(combined)) return(invisible(NULL))

  fissure <- combined |>
    filter(location_name %in% c("SBF_0001", "NV26-1")) |>
    mutate(basis = ifelse(grepl("^Gas", method), "gas (NV26-1)", "water (SBF_0001)")) |>
    select(method, basis, measured_temp_C, estimated_temp_C) |>
    arrange(basis, method)

  dir.create(dirname(out_csv), showWarnings = FALSE, recursive = TRUE)
  readr::write_csv(fissure, out_csv)
  message("[geothermometer_comparison] Wrote ", out_csv)
  invisible(fissure)
}

#' Figure: measured temperature (x) vs. geothermometer-estimated
#' temperature (y), colored by method, with a 1:1 reference line -- the
#' fissure point (NV26-1/SBF_0001) is labeled directly since it is the
#' only point with both a water and a gas estimate.
build_geothermometer_water_gas_figure <- function(
    con, out_png = "output/figures/gas_analysis/geothermometer_water_gas_comparison.png") {

  combined <- get_geothermometer_water_gas_table(con)
  if (is.null(combined)) return(invisible(NULL))

  combined <- combined |>
    mutate(is_fissure = location_name %in% c("SBF_0001", "NV26-1"),
           label = ifelse(is_fissure, location_name, NA_character_))

  max_t <- max(combined$measured_temp_C, combined$estimated_temp_C, na.rm = TRUE)

  p <- ggplot(combined, aes(x = measured_temp_C, y = estimated_temp_C, color = method)) +
    geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "grey50") +
    geom_point(aes(shape = is_fissure, size = is_fissure), alpha = 0.8) +
    ggrepel::geom_text_repel(aes(label = label, color = method), size = 3, na.rm = TRUE,
                              show.legend = FALSE, max.overlaps = Inf, seed = 118,
                              force = 8, box.padding = 0.6, min.segment.length = 0) +
    scale_shape_manual(values = c(`TRUE` = 17, `FALSE` = 16), guide = "none") +
    scale_size_manual(values = c(`TRUE` = 4, `FALSE` = 2.2), guide = "none") +
    coord_equal(xlim = c(0, max_t * 1.05), ylim = c(0, max_t * 1.05)) +
    labs(x = "Measured temperature (C)", y = "Geothermometer-estimated temperature (C)",
         color = "Method",
         title = "Water and gas geothermometers vs. measured temperature",
         subtitle = "Dashed line: 1:1. Triangles: the one real co-located gas/water point (NV26-1 / SBF_0001).") +
    theme_steamboat(base_size = 11)

  dir.create(dirname(out_png), showWarnings = FALSE, recursive = TRUE)
  ggsave(out_png, p, width = 8, height = 7, dpi = 300)
  message("[geothermometer_comparison] Wrote ", out_png)
  invisible(list(data = combined, plot = p))
}