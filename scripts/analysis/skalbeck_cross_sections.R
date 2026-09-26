# ============================================================
# skalbeck_cross_sections.R
#
# Purpose: real geologic cross-sections ("hard lines") along
# Skalbeck (2001)'s own real 2.75-D forward-model flight lines --
# added 2026-09-26 directly in response to feedback that the IDW-
# interpolated grid surfaces (export_leapfrog_geophysical_grid_
# surfaces()) blur real, sharp geologic contacts across profile
# lines that were never meant to be smoothly interpolated between
# in the first place (the striping artifact visible in that raster
# is a symptom of exactly this).
#
# Method: each Table A-2 point is projected onto its nearest real
# flight line (from Skalbeck's own Table 1, line end-coordinates --
# data/raw/historical/skalbeck2001_table1_flightlines.csv), using
# standard point-to-segment projection. Verified directly against the
# real data before trusting this: median perpendicular distance from
# a point to its assigned line is ~0.35 m (max ~200 m for the few
# points that don't sit on a named survey line, e.g. any tie-line
# points) -- confirming Table A-2's points really do sit ON these
# lines, not just near them, so "distance along line" is a real,
# not approximated, cross-section coordinate.
# ============================================================

.project_to_line_segment <- function(px, py, x1, y1, x2, y2) {
  dx <- x2 - x1; dy <- y2 - y1
  len2 <- dx^2 + dy^2
  t <- ((px - x1) * dx + (py - y1) * dy) / len2
  t_clamped <- pmax(0, pmin(1, t))
  proj_x <- x1 + t_clamped * dx
  proj_y <- y1 + t_clamped * dy
  perp_dist <- sqrt((px - proj_x)^2 + (py - proj_y)^2)
  dist_along <- t_clamped * sqrt(len2)
  data.frame(perp_dist = perp_dist, dist_along_m = dist_along)
}

#' Assign every real Geophysical_Depth_Model_Points row to its nearest
#' real Skalbeck (2001) Table 1 flight line, with distance-along-line.
#' Points whose nearest line is still farther than `max_perp_dist_m`
#' are flagged, not force-assigned (a real, honest edge case -- e.g.
#' any point genuinely off every named line).
assign_points_to_flight_lines <- function(con, max_perp_dist_m = 300,
    lines_csv = "data/raw/historical/skalbeck2001_table1_flightlines.csv") {
  if (!file.exists(lines_csv)) lines_csv <- file.path("..", lines_csv)
  flight_lines <- readr::read_csv(lines_csv, show_col_types = FALSE)
  pts <- DBI::dbGetQuery(con, "
    SELECT point_id, utm_e, utm_n, qal_thickness_m, tv_thickness_m,
           alt_kgd_km_thickness_m, depth_to_bedrock_m
    FROM Geophysical_Depth_Model_Points WHERE utm_e IS NOT NULL
  ")
  all_proj <- do.call(rbind, lapply(seq_len(nrow(flight_lines)), function(i) {
    ln <- flight_lines[i, ]
    proj <- .project_to_line_segment(pts$utm_e, pts$utm_n, ln$nw_e, ln$nw_n, ln$se_e, ln$se_n)
    proj$line_id <- ln$line_id
    proj$point_id <- pts$point_id
    proj
  }))
  best <- do.call(rbind, lapply(split(all_proj, all_proj$point_id), function(d) d[which.min(d$perp_dist), ]))
  best$off_all_lines <- best$perp_dist > max_perp_dist_m
  merged <- merge(pts, best, by = "point_id")
  merged$base_qal <- merged$qal_thickness_m
  merged$base_tv <- merged$qal_thickness_m + merged$tv_thickness_m
  merged$base_altkgd <- merged$depth_to_bedrock_m
  merged[order(merged$line_id, merged$dist_along_m), ]
}

#' Real geologic cross-section plot for one flight line -- "hard
#' lines" (sharp, point-to-point contacts) rather than a smoothed
#' interpolation, matching how the source data was actually collected
#' (discrete profile points, not a continuous surface).
plot_skalbeck_cross_section <- function(con, line_id = NULL, min_points = 8) {
  merged <- assign_points_to_flight_lines(con)
  merged <- merged[!merged$off_all_lines & !is.na(merged$base_qal), ]
  if (is.null(line_id)) {
    counts <- table(merged$line_id)
    line_id <- names(counts)[counts >= min_points]
  }
  d <- merged[merged$line_id %in% line_id, ]
  ggplot2::ggplot(d, ggplot2::aes(x = dist_along_m / 1000)) +
    ggplot2::geom_ribbon(ggplot2::aes(ymin = 0, ymax = base_qal, fill = "Qal")) +
    ggplot2::geom_ribbon(ggplot2::aes(ymin = base_qal, ymax = base_tv, fill = "Tv")) +
    ggplot2::geom_ribbon(ggplot2::aes(ymin = base_tv, ymax = base_altkgd, fill = "AltKgdpKm")) +
    ggplot2::geom_point(ggplot2::aes(y = base_altkgd), size = 0.8, color = "black") +
    ggplot2::scale_y_reverse() +
    ggplot2::scale_fill_manual(values = c(Qal = "#e6ab02", Tv = "#7570b3", AltKgdpKm = "#1b9e77"),
                                 name = "Formation unit") +
    ggplot2::facet_wrap(~line_id, scales = "free_x", ncol = 2) +
    ggplot2::labs(x = "Distance along flight line (km), NW to SE", y = "Depth (m)",
                  title = "Real geologic cross-sections along Skalbeck (2001) flight lines",
                  subtitle = "Sharp, point-to-point contacts -- not smoothed between profile lines")
}
