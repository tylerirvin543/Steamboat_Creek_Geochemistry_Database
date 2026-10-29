# ============================================================
# manuscript_figures.R
#
# Purpose: generates the two figures used in the thesis-proposal
# document (manuscript/00_thesis_proposal.qmd) that don't already have
# a home in an existing script/notebook chunk:
#
#   1. discharge_through_time.png -- the 1955-2026 thermal-water
#      discharge comparison already coded inline inside
#      notebooks/07_historical_context_sorey1992.qmd's `discharge-plot`
#      chunk. Factored out here so the manuscript doesn't need to
#      render the (heavy, DB-querying) full notebook just to get one
#      figure, and so the notebook and the manuscript are guaranteed to
#      show the same numbers rather than maintaining two copies.
#   2. steamboat_timeline.png -- a new, simple horizontal timeline
#      figure spanning the 1950s USGS-era characterization through the
#      June 2025 eruption and this project's own 2026 monitoring
#      network, built from dates already documented elsewhere in this
#      project (website/timeline.Rmd, notebooks/07's discharge table,
#      docs/literature/annotated_bibliography.qmd) rather than
#      estimated fresh.
#
# Neither figure is committed as a static image -- both are produced
# on demand, consistent with this project's existing convention (see
# manuscript/04_results.qmd's own note to that effect).
#
# Usage (from the project root):
#   source("scripts/analysis/manuscript_figures.R")
#   build_manuscript_figures(con)
# ============================================================

library(DBI)
library(dplyr)
library(ggplot2)
library(ggrepel)

source("scripts/analysis/plot_theme.R")
source("scripts/analysis/chloride_mass_balance.R")

#' Reproduce notebooks/07's discharge-through-time comparison as a
#' standalone, reusable figure.
build_discharge_through_time_figure <- function(con,
    out_png = "output/figures/manuscript/discharge_through_time.png") {

  cmb <- compute_chloride_mass_balance(con)
  qtw_live <- if (is.na(cmb$mean_Q_TW_Ls)) NA_real_ else cmb$mean_Q_TW_Ls

  discharge_hist <- tibble::tribble(
    ~period, ~year_mid, ~Ls,

    "White (1968), Apr 1955 (creek inflow only)",     1955,     810 * 0.0630902,
    "White (1968), Apr 1964 (total incl. wells)",    1964,    1385 * 0.0630902,
    "Shump (1985), 1981-82 (SC-based)",              1981.5,  1300 * 0.0630902,
    "Collar (1990), Jun 1988",                       1988.5,   523 * 0.0630902,
    "Collar (1990), Mar 1989",                       1989.2,   663 * 0.0630902,
    "Collar & Huntley (1990), 1988-89 natural-only",  1988.8,  0.80 * 1120 * 0.0630902,
    "Sorey & Spielman (2008), 2007-08",              2007.5,  mean(c(730, 1214)) * 0.0630902,
    "Sorey & Spielman (2017), 2008-2016 avg",        2012,     60,
    "This project (database), 5/1/2026",             2026.33, qtw_live,
    "Irvin & Lindsey (2026 poster), post-eruption avg", 2026,  27
  ) |>
    filter(!is.na(Ls))

  p <- ggplot(discharge_hist, aes(x = year_mid, y = Ls)) +
    geom_point(aes(color = grepl("This project", period)),
               size = 3, show.legend = FALSE) +
    ggrepel::geom_text_repel(aes(label = period), size = 2.6,
                              max.overlaps = 30, seed = 4172) +
    scale_color_manual(values = c(`TRUE` = "#D55E00", `FALSE` = "black")) +
    labs(
      x = "Year", y = "Thermal-water discharge (L/s)",
      title = "Thermal-water discharge to Steamboat Creek, 1955-2026",
      subtitle = "Creek-inflow basis except where noted; no source reports a measurement uncertainty; reaches differ slightly (see text)"
    ) +
    theme_steamboat()

  dir.create(dirname(out_png), showWarnings = FALSE, recursive = TRUE)
  ggsave(out_png, p, width = 9, height = 5.5, dpi = 300)
  message("  -> Wrote ", out_png)
  invisible(p)
}

#' A professional, two-panel horizontal timeline of Steamboat Hills
#' events spanning the pre-Ormat USGS-characterization era through this
#' project's own 2026 monitoring network. Panel A gives the long
#' historical/development record (1950-2007) with the documented
#' 1987-2022 absence of natural terrace spring flow shown as a shaded
#' band (not just a dot), per Sorey and Colvard (1992) and Sorey
#' (2000). Panel B zooms into the 2022-2026 reactivation using Lindsey
#' et al. (2026)'s own stage-by-stage account (diffuse steaming in
#' 2023, a shift to discrete seeps/vents in 2024, more energetic vents
#' in early 2025) rather than a single 2022 dot. A distinct marker
#' shape/color flags the one dated, documented event that is a
#' candidate contributing factor rather than a directly observed
#' surface change: Ormat's May 30, 2025 NDEP UIC permit raising the
#' field's combined authorized injection limit from 49,500 to 55,000
#' gpm, about two weeks before the eruption -- flagged as a plausible,
#' unconfirmed hypothesis, not a demonstrated cause (see the
#' "Candidate explanations for the reactivation" discussion in the
#' surrounding text, which also covers the other candidate
#' explanations this hypothesis marker does not visually represent).
#' Dates are drawn from sources already cited elsewhere in this
#' project (Thompson & White 1964, White 1968, Sorey & Colvard 1992,
#' Sorey 2000, Klein et al. 2007, Dhakal et al. 2025, Lindsey et al.
#' 2026, the NDEP UIC Temporary Permit UNEV2007204T2025-1, this
#' project's own logger-deployment/field records) -- nothing here is
#' estimated fresh.
build_steamboat_timeline_figure <- function(
    out_png = "output/figures/manuscript/steamboat_timeline.png") {

  events_hist <- tibble::tribble(
    ~year, ~label, ~era,
    1950,  "USGS thermal-gradient/chemistry\ntest holes (GS-1 to GS-8)",        "Historical",
    1964,  "Thompson & White / White et al.:\nregional geology and structure",  "Historical",
    1968,  "White: hydrology, activity, and\nheat flow of the thermal system",  "Historical",
    1986,  "SB GEO's first power\nplants begin production",                    "Development",
    1990,  "Ormat consolidates Steamboat\nproduction under one operator",      "Development",
    1992,  "Sorey & Colvard: 1987-89 spring-flow\ndecline attributed largely to regional\ngroundwater decline, not CPI production", "Development",
    2000,  "Sorey: groundwater levels recover, but\nspring flow still has not resumed\non the main terrace", "Development",
    2007,  "Klein, Johnson & Spielman:\nmonitor-well network documented",      "Development"
  )

  # Split into a slow 2022-2024 buildup (3 events, room to breathe) and a
  # separate, much more crowded 2025-2026 eruption/aftermath panel (9
  # events packed into about 20 months) -- lumping both into one
  # 2022-2026 panel, as an earlier version of this figure did, forced
  # every label into the same narrow x-range and made the 2025 cluster
  # unreadable regardless of repel tuning. Shorter labels here too
  # (detail that doesn't fit is still in @tbl-chronology).
  events_buildup <- tibble::tribble(
    ~year, ~label, ~era,
    2022,  "Steaming ground expands; water\nreappears along natural fractures", "Reawakening",
    2023,  "Diffuse steaming measurably\nexpands across the terrace\n(Lindsey et al. 2026)", "Reawakening",
    2024,  "Shift to discrete seeps/vents;\nfirst shallow boiling observed\n(Lindsey et al. 2026)", "Reawakening"
  )

  events_eruption <- tibble::tribble(
    ~year,    ~label, ~era,
    2025.04,  "Existing vents more energetic;\ndischarge migrates along fractures", "Reawakening",
    2025.41,  "Ormat's injection limit raised\n49,500 -> 55,000 gpm (May 30)", "Hypothesis",
    2025.417, "1st eruption (June 1-2): ~100 ft\nspout, moderating by morning", "Reawakening",
    2025.43,  "2nd eruption (June 5-6): 8-12 m\nbursts; Driveway Spring 95.1C", "Reawakening",
    2025.46,  "Wellhead capped; discharge\nredistributes laterally", "Reawakening",
    2025.47,  "NBMG begins integrated\nmonitoring program", "This project",
    2025.52,  "1st calibrated thermal drone\nsurvey (July 2025)", "This project",
    2025.75,  "2nd calibrated drone survey\n(cooler than July)", "This project",
    2026,     "Lindsey et al. publish eruption\naccount; remapping continues", "This project"
  )

  era_colors <- c(
    "Historical"    = "#0072B2",
    "Development"   = "#999999",
    "Reawakening"   = "#D55E00",
    "This project"  = "#009E73",
    "Hypothesis"    = "#E69F00"
  )
  era_shapes <- c(
    "Historical"    = 16,
    "Development"   = 16,
    "Reawakening"   = 16,
    "This project"  = 16,
    "Hypothesis"    = 17
  )

  p_hist <- ggplot(events_hist, aes(x = year, y = 0)) +
    annotate("rect", xmin = 1987, xmax = 2007.9, ymin = -1.9, ymax = 1.9,
             fill = "grey50", alpha = 0.08) +
    geom_hline(yintercept = 0, color = "grey70") +
    geom_point(aes(color = era, shape = era), size = 3) +
    ggrepel::geom_text_repel(
      aes(label = paste0(year, ": ", label), color = era),
      size = 2.5, direction = "y", force = 2, box.padding = 0.4,
      segment.size = 0.3, max.overlaps = Inf, seed = 917, lineheight = 0.9,
      ylim = c(-1.9, 1.9)
    ) +
    scale_color_manual(values = era_colors, guide = "none") +
    scale_shape_manual(values = era_shapes, guide = "none") +
    scale_x_continuous(breaks = c(1950, 1964, 1968, 1986, 1990, 1992, 2000, 2007), limits = c(1947, 2012)) +
    scale_y_continuous(limits = c(-2.1, 2.1)) +
    labs(x = NULL, y = NULL, title = "A. Characterization and development, 1950-2007",
         caption = "Shaded band: natural terrace spring flow absent, 1987-2022 (Sorey & Colvard 1992; Sorey 2000).") +
    theme_steamboat(base_size = 11) +
    theme(axis.text.y = element_blank(), panel.grid.major.y = element_blank())

  p_buildup <- ggplot(events_buildup, aes(x = year, y = 0)) +
    geom_hline(yintercept = 0, color = "grey70") +
    geom_point(aes(color = era, shape = era), size = 3, show.legend = FALSE) +
    ggrepel::geom_text_repel(
      aes(label = paste0(year, ": ", label), color = era),
      size = 2.6, direction = "y", force = 1.5, box.padding = 0.6,
      segment.size = 0.3, max.overlaps = Inf, seed = 2419, lineheight = 0.95,
      ylim = c(-1.8, 1.8), show.legend = FALSE
    ) +
    scale_color_manual(values = era_colors, guide = "none") +
    scale_shape_manual(values = era_shapes, guide = "none") +
    scale_x_continuous(breaks = c(2022, 2023, 2024), limits = c(2021.5, 2024.5)) +
    scale_y_continuous(limits = c(-2, 2)) +
    labs(x = NULL, y = NULL, title = "B. Gradual buildup, 2022-2024") +
    theme_steamboat(base_size = 11) +
    theme(axis.text.y = element_blank(), panel.grid.major.y = element_blank())

  p_eruption <- ggplot(events_eruption, aes(x = year, y = 0)) +
    geom_hline(yintercept = 0, color = "grey70") +
    geom_point(aes(color = era, shape = era), size = 3) +
    ggrepel::geom_text_repel(
      aes(label = label, color = era),
      size = 2.4, direction = "y", force = 8, box.padding = 0.9,
      point.padding = 0.3, segment.size = 0.3, max.overlaps = Inf,
      seed = 83, lineheight = 0.95, ylim = c(-3.3, 3.3)
    ) +
    scale_color_manual(values = era_colors, name = "Period / status") +
    scale_shape_manual(values = era_shapes, name = "Period / status") +
    scale_x_continuous(breaks = c(2025.0, 2025.25, 2025.5, 2025.75, 2026),
                        labels = c("2025", "Apr", "Jul", "Oct", "2026"),
                        limits = c(2024.97, 2026.15)) +
    scale_y_continuous(limits = c(-3.4, 3.4)) +
    labs(x = NULL, y = NULL, title = "C. Eruption and aftermath, zoomed in (2025-2026)",
         caption = "Triangle: a candidate contributing-factor event (the injection-limit increase), not a directly observed surface change -- see text.") +
    theme_steamboat(base_size = 11) +
    theme(axis.text.y = element_blank(), panel.grid.major.y = element_blank(),
          legend.position = "bottom")

  p <- patchwork::wrap_plots(p_hist, p_buildup, p_eruption, ncol = 1, heights = c(1, 0.8, 1.7)) +
    patchwork::plot_annotation(
      title = "Steamboat Hills: from characterization to reawakening",
      theme = theme(plot.title = element_text(face = "bold", size = 13))
    )

  dir.create(dirname(out_png), showWarnings = FALSE, recursive = TRUE)
  ggsave(out_png, p, width = 11.5, height = 14, dpi = 300)
  message("  -> Wrote ", out_png)
  invisible(p)
}

#' Real Sept-Dec 2025 U230 field-parameter time series (14 sites, 6
#' injection-side ports + 8 shallow monitoring/domestic wells; see
#' AGENTS.md's Session 42 "42-row OCR batch" addendum for provenance).
#' Two panels: (1) the systematic pH gap between the injection ports and
#' the shallow well network, held across all rounds; (2) two concrete,
#' real multi-month trends (NDOT cooling, Herz Deep's rising
#' conductivity) that motivate a mixing/transport modeling discussion.
build_u230_timeseries_figure <- function(con,
    out_png = "output/figures/manuscript/u230_timeseries.png") {

  ts <- dbGetQuery(con, "
    SELECT l.name AS location, se.date, fm.parameter, fm.value
    FROM Field_Measurements fm
    JOIN Samples s ON fm.sample_id = s.sample_id
    JOIN Sampling_Events se ON s.event_id = se.event_id
    JOIN Locations l ON s.location_id = l.location_id
    WHERE s.data_source IN ('NDEP_U230_Compiled_OCR', 'NDEP_U230_Compiled')
  ")

  ts <- ts |>
    mutate(
      date_parsed = as.Date(sub(" .*$", "", date), format = "%m/%d/%Y"),
      group = ifelse(grepl("Injection", location), "Injection-side port", "Shallow monitoring/domestic well")
    ) |>
    filter(!is.na(date_parsed))

  # Panel A: pH by group, all real rounds pooled
  p_ph <- ggplot(ts |> filter(parameter == "pH"), aes(x = group, y = value, color = group)) +
    geom_jitter(width = 0.15, size = 2, alpha = 0.7, show.legend = FALSE) +
    stat_summary(fun = mean, geom = "crossbar", width = 0.4, color = "black", linewidth = 0.4) +
    scale_color_manual(values = c("Injection-side port" = "#D55E00", "Shallow monitoring/domestic well" = "#0072B2")) +
    labs(x = NULL, y = "pH", title = "A. A systematic pH gap, injection side vs. shallow network") +
    theme_steamboat(base_size = 11) +
    theme(axis.text.x = element_text(size = rel(0.8)))

  # Panel B: two concrete real trends
  highlight <- ts |>
    filter(location %in% c("NDOT", "Herz Deep"),
           parameter %in% c("temperature", "conductivity")) |>
    filter((location == "NDOT" & parameter == "temperature") |
           (location == "Herz Deep" & parameter == "conductivity")) |>
    mutate(series = paste0(location, " ", ifelse(parameter == "temperature", "temperature (C)", "specific conductance (uS/cm)")))

  p_trend <- ggplot(highlight, aes(x = date_parsed, y = value, color = series)) +
    geom_line() + geom_point(size = 2) +
    facet_wrap(~series, scales = "free_y", ncol = 1) +
    scale_color_manual(values = c(
      "NDOT temperature (C)" = "#D55E00",
      "Herz Deep specific conductance (uS/cm)" = "#0072B2"
    )) +
    labs(x = NULL, y = NULL, title = "B. Two real multi-month trends, Sept-Dec 2025") +
    theme_steamboat(base_size = 11) +
    theme(legend.position = "none")

  p <- patchwork::wrap_plots(p_ph, p_trend, ncol = 2, widths = c(1, 1.3))

  dir.create(dirname(out_png), showWarnings = FALSE, recursive = TRUE)
  ggsave(out_png, p, width = 11, height = 5, dpi = 300)
  message("  -> Wrote ", out_png)
  invisible(p)
}


#' Resize/compress the September 27, 2026 Lower Sinter Terrace field
#' photographs for embedding in the thesis proposal.
#'
#' Reads the real, full-resolution camera originals from
#' `data/raw/images/image_drop/` (gitignored raw-media home, matching
#' this project's existing photo-location pipeline convention) and
#' writes resized (1600px wide), re-compressed (quality 85) copies to
#' `output/figures/manuscript/`, at the exact filenames
#' `manuscript/00_thesis_proposal.qmd`'s `show_fig()` calls reference.
#' The originals are ~9-10 MB phone photos (5712x4284); this cuts each
#' to well under 1 MB with no visible quality loss at print size.
#' Requires the `magick` package.
prepare_field_photo_figures <- function() {
  if (!requireNamespace("magick", quietly = TRUE)) {
    stop("prepare_field_photo_figures() requires the magick package")
  }
  map <- list(
    c("IMG_5924.jpeg", "field_photo_new_hot_spring_20260927.jpg"),
    c("IMG_5932.jpeg", "field_photo_sulfur_deposit_20260927.jpg"),
    c("IMG_5916.jpeg", "field_photo_alluvium_sinter_seep_20260927.jpg"),
    c("IMG_5275.jpeg", "field_photo_seep_earlier_visit.jpg"),
    c("IMG_5305.jpeg", "field_photo_sbgg_install.jpg")
  )
  src_dir <- "data/raw/images/image_drop"
  out_dir <- "output/figures/manuscript"
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
  for (pair in map) {
    src <- file.path(src_dir, pair[1])
    dst <- file.path(out_dir, pair[2])
    if (!file.exists(src)) {
      warning("Missing source photo: ", src, " -- skipping")
      next
    }
    img <- magick::image_resize(magick::image_read(src), "1600x")
    magick::image_write(img, path = dst, format = "jpeg", quality = 85)
    message("  -> Wrote ", dst)
  }
  invisible(TRUE)
}

#' Render the three real thermal-infrared / field-sketch PDFs added
#' 2026-10-27 (data/raw/arcgis/thermal_infrared/, see that folder's own
#' README.md) to resized, embed-ready images. Each source PDF is a
#' single-page, very large (up to ~80 MB) georeferenced map -- rendered
#' via pdftools::pdf_convert() at a dpi chosen per-file for legibility
#' at manuscript figure size, not full native resolution.
prepare_thermal_imagery_figures <- function() {
  if (!requireNamespace("pdftools", quietly = TRUE)) {
    stop("prepare_thermal_imagery_figures() requires the pdftools package")
  }
  src_dir <- "data/raw/arcgis/thermal_infrared"
  out_dir <- "output/figures/manuscript"
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

  jobs <- list(
    list(src = "thermalmap_broad_july2025.pdf",
         dst = "tir_broad_thermal_map_july2025.png", dpi = 110),
    list(src = "fissure_system_zoomin_calibrated_july2025.pdf",
         dst = "tir_fissure_zoomin_calibrated_july2025.png", dpi = 130),
    list(src = "busick_property_sketch_map_20250606.pdf",
         dst = "busick_property_sketch_map_20250606.png", dpi = 160)
  )
  for (j in jobs) {
    src <- file.path(src_dir, j$src)
    dst <- file.path(out_dir, j$dst)
    if (!file.exists(src)) {
      warning("Missing source PDF: ", src, " -- skipping")
      next
    }
    pdftools::pdf_convert(src, format = "png", pages = 1, dpi = j$dpi, filenames = dst)
    message("  -> Wrote ", dst)
  }
  invisible(TRUE)
}

#' Build a single side-by-side composite image showing the same real
#' seep location at the Lower Sinter Terrace on two different visits:
#' an earlier visit (IMG_5275; this file's own EXIF has no GPS or
#' capture-date tag -- confirmed via exiftool, not assumed -- so the
#' exact date is unknown beyond "before Sept 27, 2026") and the
#' already-embedded Sept 27, 2026 visit (IMG_5916, real EXIF GPS/
#' timestamp). Built as one pre-rendered image (via `magick`), not a
#' Quarto column layout, so it renders identically across the
#' html/pdf/docx manuscript formats.
build_seep_comparison_figure <- function(
    out_png = "output/figures/manuscript/seep_same_location_through_time.jpg") {
  if (!requireNamespace("magick", quietly = TRUE)) {
    stop("build_seep_comparison_figure() requires the magick package")
  }
  img_dir <- "output/figures/manuscript"
  path_earlier <- file.path(img_dir, "field_photo_seep_earlier_visit.jpg")
  path_later   <- file.path(img_dir, "field_photo_alluvium_sinter_seep_20260927.jpg")
  if (!file.exists(path_earlier) || !file.exists(path_later)) {
    warning("Seep comparison source photo(s) missing -- run prepare_field_photo_figures() first")
    return(invisible(NULL))
  }

  img_earlier <- magick::image_read(path_earlier)
  img_later   <- magick::image_read(path_later)

  # Match heights so image_append() lines the two panels up cleanly
  target_h <- min(magick::image_info(img_earlier)$height, magick::image_info(img_later)$height)
  img_earlier <- magick::image_resize(img_earlier, paste0("x", target_h))
  img_later   <- magick::image_resize(img_later, paste0("x", target_h))

  label_earlier <- "Same seep location, earlier visit\n(date not preserved in this file)"
  label_later   <- "Same seep location, Sept 27, 2026\n(39.3829, -119.7402)"

  annotate_panel <- function(img, label) {
    w <- magick::image_info(img)$width
    magick::image_annotate(
      img, label, gravity = "southwest", location = "+15+15",
      size = max(18, round(w * 0.03)), color = "white", boxcolor = "#00000099"
    )
  }
  img_earlier <- annotate_panel(img_earlier, label_earlier)
  img_later   <- annotate_panel(img_later, label_later)

  combined <- magick::image_append(c(img_earlier, img_later))
  dir.create(dirname(out_png), showWarnings = FALSE, recursive = TRUE)
  magick::image_write(combined, path = out_png, format = "jpeg", quality = 90)
  message("  -> Wrote ", out_png)
  invisible(combined)
}

#' Air-corrected gas-ratio comparison (NV26-1/2/3 vs. Mariner & Janik
#' 1995 well 23-5) for the manuscript, reusing
#' scripts/analysis/gas_historical_comparison.R's computation so the
#' manuscript and any standalone analysis show identical numbers.
build_gas_composition_comparison_figure <- function(con,
    out_png = "output/figures/manuscript/gas_composition_comparison.png") {
  source("scripts/analysis/gas_historical_comparison.R")
  res <- build_gas_historical_comparison(con,
    out_png = "output/figures/gas_analysis/gas_ratio_historical_comparison.png")
  if (is.null(res)) return(invisible(NULL))
  dir.create(dirname(out_png), showWarnings = FALSE, recursive = TRUE)
  ggsave(out_png, res$plot, width = 9, height = 6, dpi = 300)
  message("  -> Wrote ", out_png)
  invisible(res$plot)
}

#' D'Amore-Panichi gas-geothermometer estimate (air-corrected) vs.
#' measured field temperature at each of the 3 real fissure gas points,
#' with the Mariner & Janik (1995) well-23-5 T-DP range (173-200C)
#' shown as reference -- the new fissure/fumarole points are shallow
#' vents, not deep well discharge, so agreement is not expected; this
#' figure is a comparison, not a validation.
build_gas_geothermometry_figure <- function(con,
    out_png = "output/figures/manuscript/gas_geothermometry_comparison.png") {
  source("scripts/analysis/gas_air_correction.R")
  res <- analyze_fischer_gas_samples(con,
    out_csv = "data/derived/gas_analysis/fischer_gas_air_corrected_geothermometry.csv")
  if (is.null(res)) return(invisible(NULL))

  plot_df <- res |>
    tidyr::pivot_longer(cols = c(field_temp_c, dap_temperature_C),
                         names_to = "temperature_type", values_to = "temperature_C") |>
    dplyr::mutate(temperature_type = ifelse(temperature_type == "field_temp_c",
                                             "Measured field temperature", "D'Amore-Panichi gas geothermometer"))

  p <- ggplot(plot_df, aes(x = sample_label, y = temperature_C, color = temperature_type, shape = data_quality_flag)) +
    geom_hline(yintercept = c(173, 200), linetype = "dashed", color = "grey60") +
    geom_point(size = 3.5, position = position_dodge(width = 0.3)) +
    scale_color_manual(values = c("Measured field temperature" = "#009E73",
                                   "D'Amore-Panichi gas geothermometer" = "#D55E00"),
                        name = NULL) +
    scale_shape_manual(values = c("ok" = 16, "air_contaminated_suspect" = 4), name = "Sample quality") +
    labs(x = NULL, y = "Temperature (C)",
         title = "Fissure gas geothermometry vs. measured temperature",
         subtitle = "Dashed lines: Mariner & Janik (1995) well 23-5 T-DP range (173-200C).\nNV26-2 (x symbol) is flagged air-contaminated/possible-leak.") +
    theme_steamboat(base_size = 11)

  dir.create(dirname(out_png), showWarnings = FALSE, recursive = TRUE)
  ggsave(out_png, p, width = 7.5, height = 5.5, dpi = 300)
  message("  -> Wrote ", out_png)
  invisible(p)
}


#' Gas-informed parent-fluid reconstruction: two-panel comparison of
#' (A) the real conservative-species concentrations, measured vs.
#' reconstructed parent fluid, and (B) the resulting Cl mixing
#' fractions for real LST target samples under each choice of thermal
#' end-member. Reads the CSVs written by
#' scripts/phreeqc/15_gas_informed_parent_fluid.R's
#' run_parent_fluid_analysis() -- run that first.
build_parent_fluid_comparison_figure <- function(con,
    recon_csv = "data/derived/phreeqc/parent_fluid_reconstruction.csv",
    mixing_csv = "data/derived/phreeqc/parent_fluid_mixing_comparison.csv",
    out_png = "output/figures/manuscript/parent_fluid_comparison.png") {

  if (!file.exists(recon_csv) || !file.exists(mixing_csv)) {
    message("  -> Parent-fluid CSVs not found; run run_parent_fluid_analysis(con) first. Skipping figure.")
    return(invisible(NULL))
  }

  recon <- read.csv(recon_csv, stringsAsFactors = FALSE)
  mixing <- read.csv(mixing_csv, stringsAsFactors = FALSE)

  recon_long <- recon |>
    tidyr::pivot_longer(cols = c(measured, parent), names_to = "fluid", values_to = "value") |>
    mutate(fluid = factor(fluid, levels = c("measured", "parent"),
                           labels = c("Measured (degassed) fluid", "Reconstructed parent fluid")))

  p1 <- ggplot(recon_long, aes(x = reorder(species, -value), y = value, fill = fluid)) +
    geom_col(position = position_dodge(width = 0.75), width = 0.65) +
    scale_fill_manual(values = c("Measured (degassed) fluid" = "#D55E00",
                                  "Reconstructed parent fluid" = "#0072B2"), name = NULL) +
    scale_y_log10() +
    labs(x = NULL, y = "Concentration (mg/L, log scale)",
         title = "A. Measured vs. reconstructed parent-fluid composition",
         subtitle = "Sample 816 (SBF_0001) + NV26-1 gas; parent = measured x (1 - steam-loss fraction)") +
    theme_steamboat(base_size = 10) +
    theme(axis.text.x = element_text(angle = 40, hjust = 1), legend.position = "top")

  mixing_long <- mixing |>
    tidyr::pivot_longer(cols = c(f_thermal_measured, f_thermal_parent), names_to = "endmember", values_to = "fraction") |>
    mutate(endmember = factor(endmember, levels = c("f_thermal_measured", "f_thermal_parent"),
                               labels = c("Measured fluid as end-member", "Parent fluid as end-member")))

  p2 <- ggplot(mixing_long, aes(x = location_name, y = fraction, color = endmember)) +
    geom_hline(yintercept = 1, linetype = "dashed", color = "grey60") +
    geom_point(size = 3.5, position = position_dodge(width = 0.3)) +
    scale_color_manual(values = c("Measured fluid as end-member" = "#D55E00",
                                   "Parent fluid as end-member" = "#0072B2"), name = NULL) +
    labs(x = NULL, y = "Conservative-Cl thermal mixing fraction",
         title = "B. Inferred thermal fraction, by end-member choice",
         subtitle = "Dashed line: fraction = 1 (as concentrated as the chosen thermal end-member itself)") +
    theme_steamboat(base_size = 10) +
    theme(legend.position = "top")

  p <- patchwork::wrap_plots(p1, p2, ncol = 1)
  dir.create(dirname(out_png), showWarnings = FALSE, recursive = TRUE)
  ggsave(out_png, p, width = 8, height = 9, dpi = 300)
  message("  -> Wrote ", out_png)
  invisible(p)
}
#' Conductivity time series (SBRR/SBGG, Jul-Oct 2026) with the
#' retrieval/relaunch "ambient-air-exposure" artifact annotated --
#' confirmed twice now (2026-08-22 and 2026-10-10 downloads) and
#' flagged automatically by qc_conductivity_checks.R's detector
#' (qc_flag = 'field_visit_disturbance'). Built to make this real,
#' recurring instrument-handling artifact visually obvious rather than
#' only documented in prose/QC tables.
build_conductivity_timeseries_figure <- function(con,
    out_png = "output/figures/manuscript/conductivity_timeseries.png") {

  obs <- dbGetQuery(con, "
    SELECT o.logger_id, l.logger_name, l.role, o.timestamp, o.ec_raw, o.qc_flag
    FROM Conductivity_Observations o
    JOIN Conductivity_Loggers l ON l.logger_id = o.logger_id
  ")

  if (nrow(obs) == 0) {
    message("  -> No Conductivity_Observations found; skipping figure.")
    return(invisible(NULL))
  }

  obs <- obs |>
    mutate(
      timestamp = as.POSIXct(timestamp, tz = "UTC"),
      site_label = ifelse(role == "upstream_control",
                           "SBRR (Rhodes Road, upstream control)",
                           "SBGG (Geiger Grade, downstream)"),
      flagged = !is.na(qc_flag) & qc_flag == "field_visit_disturbance"
    ) |>
    arrange(logger_id, timestamp)

  flagged_pts <- obs |> filter(flagged)

  # Retrieval/relaunch dates: where a logger was pulled and re-deployed.
  # The orange points mark only the readings the QC detector could
  # identify as a sharp drop in EC adjacent to those events. They do NOT
  # mark when the sensor actually stopped being submerged in flowing
  # water: per direct field knowledge the logger sat in open air inside
  # its housing for at least several days before each pull, and that
  # earlier interval is not separable from real stream signal in EC
  # alone (EC stays smooth at both sites through the final days; checked
  # directly), so it is not shaded here rather than guessed at.
  retrieval_dates <- obs |>
    group_by(site_label) |>
    summarise(t = max(timestamp[flagged], na.rm = TRUE), .groups = "drop") |>
    filter(is.finite(t))

  p <- ggplot(obs, aes(x = timestamp, y = ec_raw)) +
    geom_line(color = "#0072B2", linewidth = 0.3) +
    geom_vline(data = retrieval_dates, aes(xintercept = t, linetype = "Last auto-flagged retrieval reading"),
               color = "grey30", linewidth = 0.4) +
    geom_point(data = flagged_pts, aes(shape = "Auto-flagged retrieval/relaunch reading"),
               color = "#D55E00", size = 1.6) +
    scale_shape_manual(name = NULL, values = c("Auto-flagged retrieval/relaunch reading" = 16)) +
    scale_linetype_manual(name = NULL, values = c("Last auto-flagged retrieval reading" = "dashed")) +
    facet_wrap(~site_label, ncol = 1, scales = "free_y") +
    labs(
      x = NULL, y = "Raw specific conductance (uS/cm)",
      title = "Stream conductivity logger record, 2026-07-15 to 2026-10-10",
      subtitle = paste0(
        "Orange points = readings the QC detector flagged at retrieval/relaunch events only.\n",
        "They do not bound the full period each logger spent partly or fully out of flowing water."
      ),
      caption = paste0(
        "Field notes indicate each logger sat in air inside its housing for at least several days before each pull; that interval\n",
        "is not detectable in EC alone and is not shaded. Readings from the days immediately before a retrieval should be treated as\n",
        "provisional. Source: Conductivity_Observations, geochem_operational.sqlite."
      )
    ) +
    theme_steamboat(base_size = 11) +
    theme(legend.position = "bottom")

  dir.create(dirname(out_png), showWarnings = FALSE, recursive = TRUE)
  ggsave(out_png, p, width = 9, height = 7.5, dpi = 300)
  message("  -> Wrote ", out_png)
  invisible(p)
}

#' Convenience wrapper: build all manuscript/outreach figures.
build_manuscript_figures <- function(con) {
  prepare_field_photo_figures()
  prepare_thermal_imagery_figures()
  build_seep_comparison_figure()
  build_discharge_through_time_figure(con)
  build_steamboat_timeline_figure()
  build_u230_timeseries_figure(con)
  build_gas_composition_comparison_figure(con)
  build_gas_geothermometry_figure(con)
  build_parent_fluid_comparison_figure(con)
  build_conductivity_timeseries_figure(con)
  source("scripts/analysis/lst_phreeqc_illustration_figures.R")
  build_lst_phreeqc_illustration_figures(con)
  invisible(TRUE)
}
