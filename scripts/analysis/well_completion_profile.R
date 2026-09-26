# ============================================================
# well_completion_profile.R
#
# plot_well_completion_profile(con, bbox = steamboat_bbox)
#
# Visualizes each well's REAL completion (screened/open-hole) interval
# -- NOT lithology/formation data, which this project does not have in
# usable form (Well_Lithology has only 5 rows, all well_id = NULL and
# tagged confidence = ocr_heuristic_unvalidated -- unreadable OCR
# garbage from the well-log pipeline, see notebooks/05 and 07). This
# is a deliberate, explicit substitution: completion interval tells you
# WHERE a well is open to the aquifer, which is a real (if partial)
# proxy for "which hydrostratigraphic zone does this well's water level
# actually represent" -- exactly the question a future potentiometric-
# surface-by-depth-zone map needs answered, even without real lithologic
# logs to name the units themselves.
#
# Design choices:
#   - `screen_top`/`screen_bot`: real top_perforation/bottom_perforation
#     when both exist; falls back to total_depth as `screen_bot` (an
#     "at least this deep, exact open interval unknown" case) when no
#     real interval is recorded -- flagged separately (`has_real_interval`),
#     never silently treated the same as a real interval.
#   - `interval_length_ft > 200` is flagged `long_open_interval` -- a well
#     open across a 200+ ft interval is more likely to be hydraulically
#     connected to (and its water level an average across) more than one
#     real hydrostratigraphic zone, making it a WEAKER single-zone
#     potentiometric-surface input than a well with a short, thin screen.
#     200 ft is a documented, adjustable threshold, not a hidden default.
#   - No true nested (multi-depth, same-location) piezometer pairs exist
#     in this database yet with BOTH a real completion interval AND a
#     current water level -- confirmed by checking directly, not assumed.
#     This means a genuine vertical head-difference (confining-layer)
#     argument cannot be made from head data alone today; this plot is a
#     completion-interval inventory to support that future work, not
#     itself a confining-layer proof.
#
# Usage:
#   source("scripts/analysis/well_completion_profile.R")
#   result <- plot_well_completion_profile(con)
#   result$plot
#   result$data
# ============================================================

library(DBI)
library(dplyr)
library(ggplot2)

STEAMBOAT_BBOX <- c(lon_min = -119.80, lon_max = -119.71, lat_min = 39.355, lat_max = 39.415)

get_well_completion_data <- function(con, bbox = STEAMBOAT_BBOX, long_interval_ft = 200) {
  wells <- dbGetQuery(con, "
    SELECT well_id, well_name, latitude, longitude, elevation_m, total_depth,
           top_perforation, bottom_perforation, well_role
    FROM Wells
    WHERE latitude IS NOT NULL
      AND (top_perforation IS NOT NULL OR total_depth IS NOT NULL)
      AND longitude >= ? AND longitude <= ? AND latitude >= ? AND latitude <= ?
  ", params = list(bbox["lon_min"], bbox["lon_max"], bbox["lat_min"], bbox["lat_max"]))

  wells <- wells |>
    dplyr::mutate(
      has_real_interval = !is.na(top_perforation) & !is.na(bottom_perforation),
      screen_top = dplyr::case_when(
        has_real_interval ~ top_perforation,
        TRUE ~ NA_real_
      ),
      screen_bot = dplyr::case_when(
        has_real_interval ~ bottom_perforation,
        !is.na(total_depth) ~ total_depth,
        TRUE ~ NA_real_
      ),
      interval_length_ft = ifelse(has_real_interval, bottom_perforation - top_perforation, NA_real_),
      long_open_interval = has_real_interval & interval_length_ft > long_interval_ft
    ) |>
    dplyr::filter(!is.na(screen_bot))

  latest_wl <- dbGetQuery(con, "
    SELECT well_id, water_level_elevation, timestamp,
           ROW_NUMBER() OVER (PARTITION BY well_id ORDER BY timestamp DESC) rn
    FROM Water_Level_Observations WHERE water_level_elevation IS NOT NULL
  ")
  latest_wl <- latest_wl[latest_wl$rn == 1, c("well_id", "water_level_elevation", "timestamp")]

  wells |> dplyr::left_join(latest_wl, by = "well_id")
}

plot_well_completion_profile <- function(con, bbox = STEAMBOAT_BBOX, long_interval_ft = 200) {
  d <- get_well_completion_data(con, bbox, long_interval_ft)

  message("[completion_profile] ", nrow(d), " wells in the Steamboat field bounding box have a depth/",
          "interval record; ", sum(d$has_real_interval), " have a REAL screened interval (the rest show",
          " only total depth, plotted as an open-ended bar); ", sum(d$long_open_interval, na.rm = TRUE),
          " have an open interval > ", long_interval_ft, " ft (flagged -- likely spans more than one",
          " real hydrostratigraphic zone); ", sum(!is.na(d$water_level_elevation)),
          " also have a water-level reading on record.")

  d$category <- dplyr::case_when(
    !d$has_real_interval ~ "Total depth only (no real screened interval)",
    d$long_open_interval ~ "Long open interval (>200 ft -- likely multi-zone)",
    TRUE ~ "Short/thin screen (single-zone proxy)"
  )

  # Main panel: only wells with a REAL screened interval -- the ones a
  # future potentiometric-surface-by-zone map could actually use.
  d_real <- d[d$has_real_interval, ] |>
    dplyr::arrange(dplyr::desc(elevation_m)) |>
    dplyr::mutate(well_name = factor(well_name, levels = unique(well_name)))

  p <- ggplot(d_real, aes(x = well_name)) +
    geom_segment(aes(y = screen_top, yend = screen_bot, xend = well_name, color = category),
                 linewidth = 3, lineend = "round") +
    geom_point(aes(y = screen_bot), data = d_real[!is.na(d_real$water_level_elevation), ],
               shape = 8, size = 2, color = "black") +
    scale_y_reverse(name = "Depth below ground surface (ft)") +
    scale_color_manual(values = c(
      "Short/thin screen (single-zone proxy)" = "#1b7837",
      "Long open interval (>200 ft -- likely multi-zone)" = "#b2182b"
    )) +
    labs(x = NULL, color = NULL,
         title = "Well completion (screened) intervals with a REAL interval on record",
         subtitle = paste0("Steamboat Hills field; ", nrow(d_real), " of ", nrow(d), " depth-having wells have a real",
                            " top/bottom perforation (the other ", nrow(d) - nrow(d_real),
                            " show only total depth -- see plot_total_depth_summary()). Star = has a water-level reading."),
         caption = "NOT lithology -- completion interval only. top_perforation/bottom_perforation, Wells table.") +
    theme_minimal() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))

  list(plot = p, data = d, data_real_interval_only = d_real)
}

#' Total-depth distribution for the wells that have ONLY a total_depth
#' (no real screened interval) -- a supplementary summary, not
#' individually labeled (too many wells, and the point here is the
#' distribution/depth range, not any one well's identity).
plot_total_depth_summary <- function(con, bbox = STEAMBOAT_BBOX, long_interval_ft = 200) {
  d <- get_well_completion_data(con, bbox, long_interval_ft)
  d_td <- d[!d$has_real_interval, ]

  p <- ggplot(d_td, aes(x = screen_bot)) +
    geom_histogram(binwidth = 200, fill = "grey50", color = "white") +
    labs(x = "Total depth (ft) -- no real screened interval on record", y = "Number of wells",
         title = "Depth distribution, wells with total depth but no known screened interval",
         subtitle = paste0(nrow(d_td), " wells, Steamboat Hills field bounding box")) +
    theme_minimal()

  list(plot = p, data = d_td)
}
