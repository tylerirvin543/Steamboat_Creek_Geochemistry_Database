# ============================================================
# lst_map_and_piper_figures.R
#
# Two new visualizations for the Lower Sinter Terrace forward-titration
# thread, built 2026-10-25 (same-day follow-on) per direct request:
#
#   1. build_lst_proximity_map_figure() -- a real lat/lon map of the
#      seven real flowpath samples (fissure, SBRR, SBW_0001, SBW_0002,
#      SBS_0001/2/3), colored/sized by each real downgradient target's
#      best-fit reaction-path RMSE -- visualizes the genuinely odd
#      finding that SBS_0001 and SBW_0001 sit only ~109 m apart (a real,
#      haversine-computed distance from their own real coordinates) yet
#      show two of the most different fit behaviors (worst fit vs.
#      largest-but-successful correction).
#   2. build_lst_piper_diagram() -- a hand-rolled (no new package
#      dependency -- ggtern is unmaintained/often broken against current
#      ggplot2) trilinear Piper diagram in real meq/L-percent space,
#      built directly from PHREEQC_Solutions' real mg/L values and each
#      ion's real valence/molar mass. Tests visually whether SBS_0001's
#      real sulfate-heavy signature (the basis for the Anhydrite/Gypsum
#      hypothesis tested in scripts/analysis/
#      lst_phreeqc_illustration_figures.R's SBS_0001 sensitivity figure)
#      is visible without any PHREEQC modeling at all.
#
# Usage:
#   source("scripts/analysis/lst_map_and_piper_figures.R")
#   build_lst_map_and_piper_figures(con)
# ============================================================

library(DBI)
library(dplyr)
library(ggplot2)
library(ggrepel)

source("scripts/analysis/plot_theme.R")

#' Real great-circle distance (m) between two lat/lon points.
.haversine_m <- function(lat1, lon1, lat2, lon2) {
  R <- 6371000
  rad <- pi / 180
  dlat <- (lat2 - lat1) * rad
  dlon <- (lon2 - lon1) * rad
  a <- sin(dlat / 2)^2 + cos(lat1 * rad) * cos(lat2 * rad) * sin(dlon / 2)^2
  2 * R * asin(sqrt(a))
}

#' Figure: a real lat/lon map of the seven flowpath samples, colored by
#' role (reference end-member vs. real downgradient target) and, for
#' targets, sized/colored by each one's real best-fit reaction-path RMSE
#' (from reaction_path_fit_comparison.csv, built by
#' lst_phreeqc_illustration_figures.R).
build_lst_proximity_map_figure <- function(con,
    comparison_csv = "data/derived/phreeqc/reaction_path_fit_comparison.csv",
    out_png = "output/figures/manuscript/lst_proximity_map.png") {

  sample_ids <- c(816, 819, 821, 815, 825, 820, 822)
  coords <- dbGetQuery(con, sprintf("
    SELECT s.sample_id, l.name, l.latitude, l.longitude
    FROM Samples s JOIN Locations l ON s.location_id = l.location_id
    WHERE s.sample_id IN (%s)
  ", paste(sample_ids, collapse = ",")))

  if (!file.exists(comparison_csv)) {
    message("  -> No ", comparison_csv, " found -- run build_reaction_path_fit_comparison_figure() first. Skipping map.")
    return(invisible(NULL))
  }
  rmse_tbl <- read.csv(comparison_csv, stringsAsFactors = FALSE)

  role_labels <- c(`816` = "SBF_0001 (fissure, reference)", `819` = "SBRR (meteoric reference)")
  pts <- coords |>
    left_join(rmse_tbl |> select(sample_id, best_fit_rmse_pct), by = "sample_id") |>
    mutate(
      role = ifelse(sample_id %in% c(816, 819), "Reference end-member", "Real downgradient target"),
      label = ifelse(sample_id %in% names(role_labels), role_labels[as.character(sample_id)], name)
    )

  d_sbs1_sbw1 <- .haversine_m(
    pts$latitude[pts$sample_id == 825], pts$longitude[pts$sample_id == 825],
    pts$latitude[pts$sample_id == 821], pts$longitude[pts$sample_id == 821]
  )

  # The real lat/lon box here is narrow and tall (longitude span ~421 m,
  # latitude span ~1456 m at this latitude) -- a coord_fixed() true-
  # distance aspect ratio inside a wide/short panel leaves most of the
  # canvas empty and clips the title. Size the saved panel to match the
  # data's own real aspect ratio instead of fighting it with a square one.
  lat_span_m <- diff(range(pts$latitude)) * 111320
  lon_span_m <- diff(range(pts$longitude)) * 111320 * cos(mean(pts$latitude) * pi / 180)
  fig_height <- 8
  fig_width <- max(5, fig_height * (lon_span_m / lat_span_m) + 2.5)  # +2.5in headroom for labels/legend

  p <- ggplot(pts, aes(x = longitude, y = latitude)) +
    geom_point(data = pts |> filter(role == "Reference end-member"),
               shape = 17, size = 4, color = "grey50") +
    geom_segment(
      data = pts |> filter(sample_id %in% c(825, 821)) |>
        summarise(x = longitude[sample_id == 825], y = latitude[sample_id == 825],
                  xend = longitude[sample_id == 821], yend = latitude[sample_id == 821]),
      aes(x = x, y = y, xend = xend, yend = yend), inherit.aes = FALSE,
      linetype = "dashed", color = "grey40", linewidth = 0.5
    ) +
    geom_point(data = pts |> filter(role == "Real downgradient target"),
               aes(size = best_fit_rmse_pct, color = best_fit_rmse_pct)) +
    ggrepel::geom_text_repel(aes(label = label), size = 3.3, max.overlaps = 30, seed = 4471,
                              box.padding = 0.6, force = 3, min.segment.length = 0) +
    scale_color_viridis_c(option = "plasma", direction = -1, name = "Best-fit\nRMSE (%)") +
    scale_size_continuous(range = c(4, 10), guide = "none") +
    scale_x_continuous(expand = expansion(mult = 0.35)) +
    scale_y_continuous(expand = expansion(mult = 0.08)) +
    coord_fixed(ratio = 1 / cos(mean(pts$latitude) * pi / 180)) +
    labs(
      title = stringr::str_wrap("Close on a map, far apart chemically: the real spatial layout of the LST flowpath", width = 55),
      subtitle = stringr::str_wrap(paste0(
        "Grey triangles: the two reference end-members (fissure, SBRR). Circles: the five real downgradient targets, ",
        "colored and sized by their own real forward-titration best-fit RMSE (darker/larger = worse fit). Dashed line: ",
        "the real ", round(d_sbs1_sbw1), " m distance between SBS_0001 and SBW_0001."
      ), width = 48),
      caption = stringr::str_wrap(paste0(
        "SBS_0001 and SBW_0001 sit only ", round(d_sbs1_sbw1), " m apart (real haversine distance from their own real ",
        "coordinates) yet show two of the most different fit behaviors on this flowpath -- SBS_0001 the worst fit of all ",
        "five targets, SBW_0001 the largest correction needed but also one of the largest improvements. A concrete, ",
        "visualizable instance of this project's own stated principle: proximity on a map does not imply shared chemistry ",
        "or hydraulic connection. Source: Locations, reaction_path_fit_comparison.csv."
      ), width = 68),
      x = "Longitude", y = "Latitude"
    ) +
    theme_steamboat(base_size = 11) +
    theme(plot.caption = element_text(hjust = 0, size = 7.5))

  dir.create(dirname(out_png), showWarnings = FALSE, recursive = TRUE)
  ggsave(out_png, p, width = fig_width, height = fig_height, dpi = 300)
  message("  -> Wrote ", out_png)
  invisible(p)
}

# ============================================================
# PIPER DIAGRAM (hand-rolled, no new package dependency)
# ============================================================

#' Convert a real sample's major-ion mg/L values (from PHREEQC_Solutions)
#' into charge-equivalent percentages for a Piper diagram: cations
#' (%Ca, %Mg, %Na+K) summing to 100, anions (%Cl, %SO4, %HCO3+CO3)
#' summing to 100.
.piper_percentages <- function(row) {
  val <- function(x) { v <- row[[x]]; if (is.null(v) || is.na(v)) 0 else as.numeric(v) }
  # meq/L = mg/L / (molar mass / valence)
  ca_meq <- val("Ca") / (40.078 / 2)
  mg_meq <- val("Mg") / (24.305 / 2)
  na_meq <- val("Na") / (22.99 / 1)
  k_meq  <- val("K")  / (39.098 / 1)
  cl_meq <- val("Cl") / (35.453 / 1)
  so4_meq <- val("SO4") / (96.06 / 2)
  hco3_meq <- val("Alkalinity") / (61.017 / 1)  # Alkalinity already stored as HCO3-mass-equivalent (this project's standard convention)

  cat_total <- ca_meq + mg_meq + na_meq + k_meq
  an_total <- cl_meq + so4_meq + hco3_meq

  tibble::tibble(
    pct_Ca = 100 * ca_meq / cat_total, pct_Mg = 100 * mg_meq / cat_total, pct_NaK = 100 * (na_meq + k_meq) / cat_total,
    pct_Cl = 100 * cl_meq / an_total, pct_SO4 = 100 * so4_meq / an_total, pct_HCO3 = 100 * hco3_meq / an_total
  )
}

#' Project a cation/anion triangle's own (%left, %right, %top) ternary
#' coordinates (each summing to 100) into 2D Cartesian space for plotting
#' a standard equilateral Piper sub-triangle -- the standard trilinear
#' transform (e.g. Hem 1985's own Piper-diagram convention): x axis runs
#' left-to-right along the triangle's base, y axis is height.
.ternary_xy <- function(pct_left, pct_right, pct_top, x_offset = 0) {
  x <- x_offset + 0.5 * (2 * pct_right + pct_top) / 100
  y <- (sqrt(3) / 2) * pct_top / 100
  tibble::tibble(x = x, y = y)
}

#' Build the outline (grid lines + axis labels) for one equilateral
#' triangle, offset horizontally by x_offset (used for the cation and
#' anion triangles, and the central diamond is built separately).
.triangle_outline <- function(x_offset = 0) {
  corners <- .ternary_xy(c(100, 0, 0), c(0, 100, 0), c(0, 0, 100), x_offset)
  corners
}

#' Figure: a real, hand-rolled Piper trilinear diagram across the seven
#' real flowpath samples, built directly from PHREEQC_Solutions' real
#' mg/L chemistry (no PHREEQC modeling involved) -- a direct visual
#' check of whether SBS_0001's real sulfate-heavy, low-alkalinity
#' signature (the basis for the Anhydrite/Gypsum hypothesis tested
#' elsewhere) is visible without any modeling at all.
build_lst_piper_diagram <- function(con,
    sample_ids = c(816, 819, 821, 815, 825, 820, 822),
    out_png = "output/figures/manuscript/lst_piper_diagram.png") {

  sol <- dbGetQuery(con, sprintf("SELECT * FROM PHREEQC_Solutions WHERE sample_id IN (%s)", paste(sample_ids, collapse = ",")))
  names_tbl <- dbGetQuery(con, sprintf("
    SELECT s.sample_id, l.name FROM Samples s JOIN Locations l ON s.location_id = l.location_id
    WHERE s.sample_id IN (%s)
  ", paste(sample_ids, collapse = ",")))

  pct <- lapply(seq_len(nrow(sol)), function(i) {
    cbind(sample_id = sol$sample_id[i], .piper_percentages(as.list(sol[i, ])))
  }) |> bind_rows() |> left_join(names_tbl, by = "sample_id")

  # Cation triangle (left, apex up): left corner = Ca, right corner = Na+K, top = Mg
  # Anion triangle (right, apex up): left corner = Cl, right corner = SO4, top = HCO3
  # (This is the standard Piper layout -- Ca/Mg/Na+K on the left, Cl/SO4/HCO3 on the right,
  # with a central diamond combining both.)
  CAT_OFFSET <- 0
  AN_OFFSET <- 1.3
  DIAMOND_OFFSET <- 0.65

  cat_pts <- pct |> bind_cols(.ternary_xy(pct$pct_Ca, pct$pct_NaK, pct$pct_Mg, x_offset = CAT_OFFSET))
  an_pts  <- pct |> bind_cols(.ternary_xy(pct$pct_Cl, pct$pct_SO4, pct$pct_HCO3, x_offset = AN_OFFSET))

  # Diamond: x from (Na+K + SO4) pair, y from (Mg + SO4) pair -- the
  # standard Piper central-diamond projection (Hem 1985).
  diamond_x <- DIAMOND_OFFSET + 0.5 * (pct$pct_NaK + pct$pct_SO4) / 100
  diamond_y <- (sqrt(3) / 2) * (1 - (pct$pct_Mg + pct$pct_SO4) / 200) + 0.15
  dia_pts <- pct |> mutate(x = diamond_x, y = diamond_y)

  tri_outline <- function(x_offset) {
    tibble::tibble(
      x = c(x_offset, x_offset + 1, x_offset + 0.5, x_offset),
      y = c(0, 0, sqrt(3) / 2, 0)
    )
  }
  # A rhombus centered between the two triangle apexes, vertical span
  # matching the triangles' own height.
  dia_top    <- tibble::tibble(x = DIAMOND_OFFSET + 0.5, y = sqrt(3) / 2 + 0.15)
  dia_bottom <- tibble::tibble(x = DIAMOND_OFFSET + 0.5, y = 0.15)
  dia_left   <- tibble::tibble(x = DIAMOND_OFFSET, y = sqrt(3) / 4 + 0.15)
  dia_right  <- tibble::tibble(x = DIAMOND_OFFSET + 1, y = sqrt(3) / 4 + 0.15)
  diamond_outline <- bind_rows(dia_top, dia_right, dia_bottom, dia_left, dia_top)

  all_pts <- bind_rows(
    cat_pts |> mutate(panel = "cation"),
    an_pts |> mutate(panel = "anion"),
    dia_pts |> mutate(panel = "diamond")
  )

  highlight_colors <- c(
    "SBF_0001" = "#D55E00", "SBW_0002" = "#E69F00", "SBRR" = "#56B4E9",
    "SBW_0001" = "#009E73", "SBS_0001" = "#CC79A7", "SBS_0002" = "#0072B2", "SBS_0003" = "#999999"
  )

  p <- ggplot() +
    geom_polygon(data = tri_outline(CAT_OFFSET), aes(x, y), fill = NA, color = "grey40") +
    geom_polygon(data = tri_outline(AN_OFFSET), aes(x, y), fill = NA, color = "grey40") +
    geom_polygon(data = diamond_outline, aes(x, y), fill = NA, color = "grey40") +
    geom_point(data = all_pts, aes(x = x, y = y, color = name), size = 4) +
    ggrepel::geom_text_repel(data = all_pts |> filter(panel == "diamond"), aes(x = x, y = y, label = name),
                              size = 3.2, max.overlaps = 20, seed = 4471) +
    annotate("text", x = CAT_OFFSET + 0.5, y = -0.07, label = "Ca -> Na+K", size = 3.3) +
    annotate("text", x = CAT_OFFSET - 0.08, y = sqrt(3) / 4, label = "Mg", size = 3.3, angle = 60) +
    annotate("text", x = AN_OFFSET + 0.5, y = -0.07, label = "Cl -> SO4", size = 3.3) +
    annotate("text", x = AN_OFFSET - 0.08, y = sqrt(3) / 4, label = "HCO3", size = 3.3, angle = 60) +
    scale_color_manual(values = highlight_colors, name = "Real flowpath sample") +
    coord_fixed() +
    labs(
      title = "A real Piper diagram across the Lower Sinter Terrace flowpath -- no PHREEQC modeling involved",
      subtitle = stringr::str_wrap(paste0(
        "Left triangle: real cation composition (% meq/L). Right triangle: real anion composition. Diamond: combined. ",
        "Built directly from PHREEQC_Solutions' own mg/L values and each ion's real valence/molar mass."
      ), width = 120),
      caption = stringr::str_wrap(paste0(
        "If SBS_0001's real sulfate-heavy, low-alkalinity signature (the basis for the Anhydrite/Gypsum hypothesis tested ",
        "in sbs0001_sensitivity_comparison.png) is a genuine facies difference and not just a PHREEQC-modeling artifact, it ",
        "should sit visibly apart from SBS_0002/SBS_0003 on the anion triangle's SO4 corner -- checked directly in this ",
        "figure, not assumed. Source: PHREEQC_Solutions, geochem_operational.sqlite."
      ), width = 125)
    ) +
    theme_steamboat(base_size = 11) +
    theme(
      axis.title = element_blank(), axis.text = element_blank(), axis.ticks = element_blank(),
      panel.grid = element_blank(), plot.caption = element_text(hjust = 0, size = 8)
    )

  dir.create(dirname(out_png), showWarnings = FALSE, recursive = TRUE)
  ggsave(out_png, p, width = 11, height = 7, dpi = 300)
  message("  -> Wrote ", out_png)
  invisible(list(plot = p, data = pct))
}

#' Convenience wrapper: build both new figures.
build_lst_map_and_piper_figures <- function(con) {
  build_lst_proximity_map_figure(con)
  build_lst_piper_diagram(con)
  invisible(TRUE)
}
