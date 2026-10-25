# ============================================================
# lst_map_and_piper_figures.R
#
# Two visualizations for the Lower Sinter Terrace forward-titration
# thread, built 2026-10-25:
#
#   1. build_lst_proximity_map_figure() -- a real lat/lon map of the
#      seven real flowpath samples (fissure, SBRR, SBW_0001, SBW_0002,
#      SBS_0001/2/3), colored/sized by each real downgradient target's
#      best-fit reaction-path RMSE -- visualizes the genuinely odd
#      finding that SBS_0001 and SBW_0001 sit only ~109 m apart (a real,
#      haversine-computed distance from their own real coordinates) yet
#      show two of the most different fit behaviors (worst fit vs.
#      largest-but-successful correction).
#   2. build_lst_piper_diagram() -- a real, publication-quality
#      trilinear Piper diagram, with geometry (grid lines, percent
#      ticks, shaded/labeled water-type diamond quadrants, plotmath
#      vertex labels) ported from the IGNIS project's own hand-built
#      utils_plotting.R (piper_coordinates()/plot_piper()), NOT ggtern:
#      confirmed by grepping the entire IGNIS codebase for "ggtern"
#      (zero hits) before writing this -- ggtern is poorly maintained
#      and frequently breaks against current ggplot2 releases, so IGNIS
#      hand-builds the geometry directly, and that richer approach is
#      ported here rather than adding ggtern as a new dependency.
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
#'
#' Reworked 2026-10-25 (same-day follow-on) to fix real layout problems
#' in the first version: the title clipped against the panel edge and
#' much of the canvas sat empty, because a true-distance coord_fixed()
#' inside a near-square save size fights the data's own real, narrow/tall
#' bounding box. Fixed by deriving both the panel's aspect ratio AND the
#' title-wrap width directly from the real geographic extent, and by
#' moving the per-point distance annotation into the caption instead of
#' an inline text box that collided with point labels.
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

  role_labels <- c(`816` = "SBF_0001\n(fissure, reference)", `819` = "SBRR\n(meteoric reference)")
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
  # latitude span ~1456 m at this latitude). A coord_fixed() true-distance
  # aspect ratio only looks right if the SAVED panel's own width:height
  # ratio matches it -- compute both from the real data, not a fixed
  # guess, and derive the title-wrap width (characters) from the real
  # panel width in inches so the title never clips again.
  lat_span_m <- diff(range(pts$latitude)) * 111320
  lon_span_m <- diff(range(pts$longitude)) * 111320 * cos(mean(pts$latitude) * pi / 180)
  fig_height <- 9
  panel_aspect <- lon_span_m / lat_span_m           # width:height of the MAP panel alone
  fig_width <- max(6, fig_height * panel_aspect * 1.9)  # *1.9 leaves room for the legend+labels beside the panel
  title_wrap_chars <- max(30, round(fig_width * 6.2))   # ~6.2 chars/inch at this title size

  p <- ggplot(pts, aes(x = longitude, y = latitude)) +
    geom_point(data = pts |> filter(role == "Reference end-member"),
               shape = 17, size = 4.5, color = "grey45") +
    geom_segment(
      data = pts |> filter(sample_id %in% c(825, 821)) |>
        summarise(x = longitude[sample_id == 825], y = latitude[sample_id == 825],
                  xend = longitude[sample_id == 821], yend = latitude[sample_id == 821]),
      aes(x = x, y = y, xend = xend, yend = yend), inherit.aes = FALSE,
      linetype = "dashed", color = "grey35", linewidth = 0.6
    ) +
    geom_point(data = pts |> filter(role == "Real downgradient target"),
               aes(size = best_fit_rmse_pct, color = best_fit_rmse_pct)) +
    ggrepel::geom_text_repel(aes(label = label), size = 3.6, max.overlaps = 30, seed = 4471,
                              box.padding = 0.9, point.padding = 0.3, force = 6,
                              min.segment.length = 0, segment.color = "grey50") +
    scale_color_viridis_c(option = "plasma", direction = -1, name = "Best-fit\nRMSE (%)") +
    scale_size_continuous(range = c(5, 11), guide = "none") +
    scale_x_continuous(expand = expansion(mult = 0.55)) +
    scale_y_continuous(expand = expansion(mult = 0.12)) +
    coord_fixed(ratio = 1 / cos(mean(pts$latitude) * pi / 180)) +
    labs(
      title = stringr::str_wrap("Close on a map, far apart chemically: the real spatial layout of the LST flowpath", width = title_wrap_chars),
      subtitle = stringr::str_wrap(paste0(
        "Grey triangles: the two reference end-members (fissure, SBRR). Circles: the five real downgradient targets, ",
        "colored and sized by their own real forward-titration best-fit RMSE (darker/larger = worse fit)."
      ), width = title_wrap_chars),
      caption = stringr::str_wrap(paste0(
        "SBS_0001 and SBW_0001 sit only ", round(d_sbs1_sbw1), " m apart (dashed line; real haversine distance from their own real ",
        "coordinates) yet show two of the most different fit behaviors on this flowpath -- SBS_0001 the worst fit of all five ",
        "targets, SBW_0001 the largest correction needed but also one of the largest improvements. A concrete, visualizable ",
        "instance of this project's own stated principle: proximity on a map does not imply shared chemistry or hydraulic ",
        "connection. Source: Locations, reaction_path_fit_comparison.csv."
      ), width = round(title_wrap_chars * 1.35)),
      x = "Longitude", y = "Latitude"
    ) +
    theme_steamboat(base_size = 12) +
    theme(
      plot.title = element_text(size = rel(1.2)),
      plot.caption = element_text(hjust = 0, size = 8.5),
      legend.position = "right"
    )

  dir.create(dirname(out_png), showWarnings = FALSE, recursive = TRUE)
  ggsave(out_png, p, width = fig_width, height = fig_height, dpi = 300)
  message("  -> Wrote ", out_png)
  invisible(p)
}

# ============================================================
# PIPER DIAGRAM (hand-rolled, geometry ported from the IGNIS project --
# NOT ggtern, see file header)
# ============================================================

#' Real meq/L-percent Piper coordinates for vectors of real major-ion
#' meq/L values, following the IGNIS project's own piper_coordinates()
#' geometry exactly: cation triangle (Mg bottom-left, Na+K bottom-right,
#' Ca top); anion triangle, offset +120 (HCO3 bottom-left, Cl
#' bottom-right, SO4 top); diamond (rotated rhombus above both,
#' combining Ca+Mg and Cl+SO4).
.piper_coordinates <- function(Ca_meq, Mg_meq, NaK_meq, Cl_meq, SO4_meq, HCO3_meq) {
  cat_sum <- Ca_meq + Mg_meq + NaK_meq
  an_sum  <- Cl_meq + SO4_meq + HCO3_meq
  Ca_pct   <- ifelse(cat_sum > 0, Ca_meq / cat_sum * 100, NA)
  Mg_pct   <- ifelse(cat_sum > 0, Mg_meq / cat_sum * 100, NA)
  NaK_pct  <- ifelse(cat_sum > 0, NaK_meq / cat_sum * 100, NA)
  Cl_pct   <- ifelse(an_sum > 0, Cl_meq / an_sum * 100, NA)
  SO4_pct  <- ifelse(an_sum > 0, SO4_meq / an_sum * 100, NA)
  HCO3_pct <- ifelse(an_sum > 0, HCO3_meq / an_sum * 100, NA)
  CaMg_pct  <- Ca_pct + Mg_pct
  ClSO4_pct <- Cl_pct + SO4_pct

  cat_x <- NaK_pct + Ca_pct / 2
  cat_y <- Ca_pct * sqrt(3) / 2
  an_x  <- Cl_pct + SO4_pct / 2 + 120
  an_y  <- SO4_pct * sqrt(3) / 2
  h <- 100 * sqrt(3) / 2
  d_x <- 110 + (CaMg_pct - ClSO4_pct) / 2
  d_y <- (CaMg_pct + ClSO4_pct) * h / 100

  tibble::tibble(cat_x, cat_y, an_x, an_y, d_x, d_y,
                 Ca_pct, Mg_pct, NaK_pct, Cl_pct, SO4_pct, HCO3_pct)
}

#' Minimal publication-quality ternary theme, ported from the IGNIS
#' project's own theme_ignis().
.theme_piper <- function(base_size = 11) {
  theme_void(base_size = base_size) %+replace%
    theme(
      plot.title = element_text(size = rel(1.2), face = "bold", hjust = 0, margin = margin(b = 4)),
      plot.subtitle = element_text(size = rel(0.9), color = "grey40", hjust = 0, margin = margin(b = 8)),
      plot.caption = element_text(size = rel(0.68), color = "grey50", hjust = 0, margin = margin(t = 8)),
      legend.position = "right",
      legend.title = element_text(size = rel(0.9), face = "bold"),
      legend.text = element_text(size = rel(0.82)),
      plot.margin = margin(10, 10, 10, 10)
    )
}

#' Figure: a real, publication-quality Piper trilinear diagram across the
#' seven real flowpath samples, built directly from PHREEQC_Solutions'
#' real mg/L chemistry (no PHREEQC modeling involved) -- a direct visual
#' check of whether SBS_0001's real sulfate-heavy, low-alkalinity
#' signature (the basis for the Anhydrite/Gypsum hypothesis tested
#' elsewhere) is visible without any modeling at all.
#'
#' Geometry (grid lines, percent-tick labels, shaded/labeled water-type
#' diamond quadrants, plotmath vertex/edge labels) ported directly from
#' the IGNIS project's own hand-built piper_coordinates()/plot_piper()
#' (C:/Projects/IGNIS/IGNIS_Geochem_Database_Directory/R/utils_plotting.R),
#' adapted here for this project's schema and a single discrete
#' color-per-sample aesthetic (IGNIS's own feature_type/prospect concept
#' does not apply to this project's seven flowpath samples).
build_lst_piper_diagram <- function(con,
    sample_ids = c(816, 819, 821, 815, 825, 820, 822),
    out_png = "output/figures/manuscript/lst_piper_diagram.png") {

  sol <- dbGetQuery(con, sprintf("SELECT * FROM PHREEQC_Solutions WHERE sample_id IN (%s)", paste(sample_ids, collapse = ",")))
  names_tbl <- dbGetQuery(con, sprintf("
    SELECT s.sample_id, l.name FROM Samples s JOIN Locations l ON s.location_id = l.location_id
    WHERE s.sample_id IN (%s)
  ", paste(sample_ids, collapse = ",")))

  # Real equivalent-weight (molar mass / valence) factors -- the same
  # real values the IGNIS project's own MEQ_FACTORS table uses.
  meq_wt <- c(Na = 22.990, K = 39.098, Ca = 20.039, Mg = 12.153,
              Cl = 35.453, SO4 = 48.030, Alkalinity = 61.017)

  val <- function(row, x) { v <- row[[x]]; if (is.null(v) || is.na(v)) 0 else as.numeric(v) }
  piper_data <- lapply(seq_len(nrow(sol)), function(i) {
    row <- as.list(sol[i, ])
    tibble::tibble(
      sample_id = row$sample_id,
      Ca_meq   = val(row, "Ca")  / meq_wt[["Ca"]],
      Mg_meq   = val(row, "Mg")  / meq_wt[["Mg"]],
      NaK_meq  = val(row, "Na")  / meq_wt[["Na"]] + val(row, "K") / meq_wt[["K"]],
      Cl_meq   = val(row, "Cl")  / meq_wt[["Cl"]],
      SO4_meq  = val(row, "SO4") / meq_wt[["SO4"]],
      HCO3_meq = val(row, "Alkalinity") / meq_wt[["Alkalinity"]]  # Alkalinity already stored as HCO3-mass-equivalent (project convention)
    )
  }) |> bind_rows() |> left_join(names_tbl, by = "sample_id")

  coords <- .piper_coordinates(piper_data$Ca_meq, piper_data$Mg_meq, piper_data$NaK_meq,
                                piper_data$Cl_meq, piper_data$SO4_meq, piper_data$HCO3_meq)
  piper_data <- bind_cols(piper_data, coords)

  h <- 100 * sqrt(3) / 2
  d_gap <- 15
  piper_data$d_y <- piper_data$d_y + d_gap

  cat_frame <- tibble::tibble(x = c(0, 50, 100, 0), y = c(0, h, 0, 0))
  an_frame  <- tibble::tibble(x = c(0, 50, 100, 0) + 120, y = c(0, h, 0, 0))
  diamond   <- tibble::tibble(x = c(110, 160, 110, 60, 110), y = c(0, h, 2 * h, h, 0) + d_gap)

  make_tri_grid <- function(ox = 0) {
    grids <- list()
    for (p in seq(20, 80, by = 20)) {
      f <- p / 100
      grids[[length(grids) + 1]] <- tibble::tibble(x = c(f * 50, 100 - f * 50) + ox, y = rep(f * h, 2))
      grids[[length(grids) + 1]] <- tibble::tibble(x = c(p / 2, p) + ox, y = c(p * sqrt(3) / 2, 0))
      grids[[length(grids) + 1]] <- tibble::tibble(x = c(50 + p / 2, p) + ox, y = c((100 - p) * sqrt(3) / 2, 0))
    }
    grids
  }
  make_diamond_grid <- function() {
    grids <- list()
    for (p in seq(20, 80, by = 20)) {
      grids[[length(grids) + 1]] <- tibble::tibble(
        x = c(110 - p / 2, 110 + (100 - p) / 2), y = c(p * h / 100, (100 + p) * h / 100) + d_gap)
      grids[[length(grids) + 1]] <- tibble::tibble(
        x = c(110 + p / 2, 60 + p / 2), y = c(p * h / 100, (p + 100) * h / 100) + d_gap)
    }
    grids
  }
  cat_grid <- make_tri_grid(0)
  an_grid  <- make_tri_grid(120)
  dia_grid <- make_diamond_grid()

  cat_btm <- tibble::tibble(x = seq(20, 80, 20), y = -5, label = as.character(seq(80, 20, -20)))
  cat_lft <- tibble::tibble(x = seq(20, 80, 20) / 2 - 5, y = seq(20, 80, 20) * sqrt(3) / 2, label = as.character(seq(20, 80, 20)))
  an_btm  <- tibble::tibble(x = seq(20, 80, 20) + 120, y = -5, label = as.character(seq(80, 20, -20)))
  an_rgt  <- tibble::tibble(x = 100 - seq(20, 80, 20) / 2 + 5 + 120, y = seq(20, 80, 20) * sqrt(3) / 2, label = as.character(seq(20, 80, 20)))

  pcts <- seq(20, 80, 20)
  rev_pcts <- rev(pcts)
  dia_br <- tibble::tibble(x = 110 + pcts / 2 + 4, y = pcts * h / 100 + d_gap, label = as.character(rev_pcts))
  dia_bl <- tibble::tibble(x = 110 - pcts / 2 - 4, y = pcts * h / 100 + d_gap, label = as.character(rev_pcts))
  dia_ur <- tibble::tibble(x = 110 + (100 - pcts) / 2 + 4, y = (100 + pcts) * h / 100 + d_gap, label = as.character(pcts))
  dia_ul <- tibble::tibble(x = 110 + (pcts - 100) / 2 - 4, y = (pcts + 100) * h / 100 + d_gap, label = as.character(pcts))

  sample_colors <- c(
    "SBF_0001" = "#D55E00", "SBW_0002" = "#E69F00", "SBRR" = "#56B4E9",
    "SBW_0001" = "#009E73", "SBS_0001" = "#CC79A7", "SBS_0002" = "#0072B2", "SBS_0003" = "#999999"
  )

  p <- ggplot() +
    coord_fixed(xlim = c(-15, 235), ylim = c(-28, 2 * h + d_gap + 18), clip = "off")

  for (g in c(cat_grid, an_grid, dia_grid)) p <- p + geom_path(data = g, aes(x, y), color = "grey88", linewidth = 0.12)

  # Shaded, labeled water-type diamond quadrants (Piper/Hem convention)
  p <- p +
    geom_polygon(data = tibble::tibble(x = c(110, 160, 110), y = c(0, h, h) + d_gap), aes(x, y), fill = "#2ca02c", alpha = 0.07) +
    geom_polygon(data = tibble::tibble(x = c(110, 160, 110), y = c(h, h, 2 * h) + d_gap), aes(x, y), fill = "#D55E00", alpha = 0.07) +
    geom_polygon(data = tibble::tibble(x = c(110, 60, 110), y = c(0, h, h) + d_gap), aes(x, y), fill = "#0072B2", alpha = 0.07) +
    geom_polygon(data = tibble::tibble(x = c(60, 110, 110), y = c(h, 2 * h, h) + d_gap), aes(x, y), fill = "#CC79A7", alpha = 0.07) +
    geom_path(data = cat_frame, aes(x, y), color = "grey25", linewidth = 0.5) +
    geom_path(data = an_frame, aes(x, y), color = "grey25", linewidth = 0.5) +
    geom_path(data = diamond, aes(x, y), color = "grey25", linewidth = 0.5) +
    geom_segment(aes(x = 60, xend = 160, y = h + d_gap, yend = h + d_gap), color = "grey50", linewidth = 0.25) +
    geom_segment(aes(x = 110, xend = 110, y = d_gap, yend = 2 * h + d_gap), color = "grey50", linewidth = 0.25)

  p <- p +
    geom_text(data = cat_btm, aes(x, y, label = label), size = 2.4, color = "grey50") +
    geom_text(data = cat_lft, aes(x, y, label = label), size = 2.4, color = "grey50", angle = 60) +
    geom_text(data = an_btm, aes(x, y, label = label), size = 2.4, color = "grey50") +
    geom_text(data = an_rgt, aes(x, y, label = label), size = 2.4, color = "grey50", angle = -60) +
    geom_text(data = dia_br, aes(x, y, label = label), size = 2.1, color = "grey40", angle = -60) +
    geom_text(data = dia_bl, aes(x, y, label = label), size = 2.1, color = "grey40", angle = 60) +
    geom_text(data = dia_ur, aes(x, y, label = label), size = 2.1, color = "grey40", angle = 60) +
    geom_text(data = dia_ul, aes(x, y, label = label), size = 2.1, color = "grey40", angle = -60)

  cy_lo <- 2 * h / 3 + d_gap
  cy_hi <- 4 * h / 3 + d_gap
  p <- p +
    annotate("text", x = 127, y = cy_lo, label = 'atop("Ca-Mg", HCO[3])', parse = TRUE, size = 3.1, color = "#2ca02c", alpha = 0.7) +
    annotate("text", x = 127, y = cy_hi, label = 'atop("Ca-Mg", SO[4]*"-Cl")', parse = TRUE, size = 3.1, color = "#D55E00", alpha = 0.7) +
    annotate("text", x = 93, y = cy_lo, label = 'atop("Na-K", HCO[3])', parse = TRUE, size = 3.1, color = "#0072B2", alpha = 0.7) +
    annotate("text", x = 93, y = cy_hi, label = 'atop("Na-K", SO[4]*"-Cl")', parse = TRUE, size = 3.1, color = "#CC79A7", alpha = 0.7) +
    annotate("text", x = -5, y = -12, label = "bold(Mg)", parse = TRUE, size = 3.8) +
    annotate("text", x = 100, y = -12, label = '"Na+K"', parse = TRUE, size = 3.8, fontface = "bold") +
    annotate("text", x = 50, y = h + 6, label = "bold(Ca)", parse = TRUE, size = 3.8) +
    annotate("text", x = 120, y = -12, label = 'bold(HCO[3])', parse = TRUE, size = 3.8) +
    annotate("text", x = 225, y = -12, label = "bold(Cl)", parse = TRUE, size = 3.8) +
    annotate("text", x = 170, y = h + 6, label = 'bold(SO[4])', parse = TRUE, size = 3.8) +
    annotate("text", x = 50, y = -23, label = "CATIONS (% meq/L)", size = 2.7, fontface = "bold", color = "grey40") +
    annotate("text", x = 170, y = -23, label = "ANIONS (% meq/L)", size = 2.7, fontface = "bold", color = "grey40") +
    annotate("text", x = 110, y = 2 * h + d_gap + 12, label = "Water Type Classification", size = 3.1, fontface = "bold", color = "grey25")

  add_pts <- function(plot, data, xc, yc, sz) {
    plot + geom_point(data = data, aes(x = .data[[xc]], y = .data[[yc]], fill = name),
                       color = "grey20", shape = 21, size = sz, alpha = 0.92, stroke = 0.45)
  }
  p <- add_pts(p, piper_data, "cat_x", "cat_y", 3.1)
  p <- add_pts(p, piper_data, "an_x", "an_y", 3.1)
  p <- add_pts(p, piper_data, "d_x", "d_y", 3.8)

  p <- p +
    scale_fill_manual(values = sample_colors, name = "Real flowpath sample") +
    guides(fill = guide_legend(override.aes = list(shape = 21, size = 4))) +
    labs(
      title = "A real Piper diagram across the Lower Sinter Terrace flowpath",
      subtitle = "Major-ion proportions (% meq/L), built directly from real PHREEQC_Solutions mg/L chemistry -- no PHREEQC modeling involved",
      caption = stringr::str_wrap(paste0(
        "If SBS_0001's real sulfate-heavy, low-alkalinity signature (the basis for the Anhydrite/Gypsum hypothesis tested in ",
        "sbs0001_sensitivity_comparison.png) is a genuine facies difference and not just a PHREEQC-modeling artifact, it should sit ",
        "visibly apart from SBS_0002/SBS_0003 on the anion triangle's SO4 corner -- checked directly in this figure, not assumed. ",
        "Geometry ported from the IGNIS project's own hand-built Piper-diagram code (not ggtern -- unmaintained, frequently broken ",
        "against current ggplot2). Source: PHREEQC_Solutions, geochem_operational.sqlite."
      ), width = 150)
    ) +
    .theme_piper(base_size = 12)

  p <- p + ggrepel::geom_text_repel(
    data = piper_data, aes(x = d_x, y = d_y, label = name), size = 3.1, max.overlaps = 20,
    segment.size = 0.2, segment.color = "grey50", show.legend = FALSE,
    min.segment.length = 0.1, box.padding = 0.4, point.padding = 0.3, force = 3, seed = 4721)

  dir.create(dirname(out_png), showWarnings = FALSE, recursive = TRUE)
  ggsave(out_png, p, width = 13, height = 8.2, dpi = 320)
  message("  -> Wrote ", out_png)
  invisible(list(plot = p, data = piper_data))
}

#' Convenience wrapper: build both figures.
build_lst_map_and_piper_figures <- function(con) {
  build_lst_proximity_map_figure(con)
  build_lst_piper_diagram(con)
  invisible(TRUE)
}
