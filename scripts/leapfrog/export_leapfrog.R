# ============================================================
# export_leapfrog.R
#
# Purpose:
# Exports this project's well data in Leapfrog's standard collar/survey/
# interval CSV format -- a NEW, SEPARATE, OPTIONAL export alongside the
# existing GeoPackage (export_geopackage.R), never a replacement for it.
# Scoped in README.md ("Planned: Leapfrog 3D geologic model export",
# 2026-09-12) and built out this session.
#
# Design:
#   - Its own output directory (output/leapfrog/), never mixed with the
#     GeoPackage output.
#   - Its own RUN_ANALYSIS$leapfrog_export flag in run_pipeline.R
#     (default FALSE, opt-in, same posture as RUN_ANALYSIS$phreeqc).
#   - Coordinate system: UTM Zone 11N (EPSG:26911), meters -- Leapfrog
#     generally expects a projected CRS for real 3D distance math, unlike
#     every other export in this project (which stays lat/lon to match
#     the GeoPackage/website). This is the one open decision from the
#     README's scoping section resolved here.
#
# Outputs (all under out_dir, default "output/leapfrog/"):
#   collar.csv            -- HoleID, X, Y, Z (UTM 11N + elevation_m),
#                             MaxDepth (total_depth, converted to meters).
#                             Only wells with lat/lon + elevation_m +
#                             total_depth ALL populated (fully collar-ready).
#   collar_incomplete.csv -- wells missing at least one of the three,
#                             for reference/future completion -- NOT
#                             silently dropped.
#   survey.csv            -- two rows per hole in collar.csv (Depth 0 and
#                             Depth=MaxDepth, Azimuth 0, Dip -90), since
#                             no deviation survey data exists anywhere in
#                             this project -- every hole is exported as a
#                             straight vertical trace. Stated explicitly
#                             here and in the README, not silently assumed.
#   completion_interval.csv -- HoleID, From, To (meters, depth-below-
#                             surface), IntervalType='completion_interval'
#                             for wells with top_perforation/
#                             bottom_perforation. Explicitly NOT a
#                             lithology table -- Well_Lithology has no
#                             usable data yet (see README) -- and labeled
#                             as such in its own IntervalType column so it
#                             can never be mistaken for real lithology
#                             downstream in Leapfrog.
#
# Depths are converted feet -> meters (this project's Wells.total_depth/
# top_perforation/bottom_perforation are stored in feet; UTM coordinates
# and elevation_m are already in meters) so every column in every output
# file is in a single, consistent unit (meters).
# ============================================================

library(DBI)
library(dplyr)
library(sf)
library(readr)
library(fs)

FT_TO_M <- 0.3048

export_leapfrog_wells <- function(con, out_dir = "output/leapfrog") {

  message("---- Exporting Leapfrog-ready well layers ----")
  dir_create(out_dir)

  wells <- dbGetQuery(con, "
    SELECT well_id, well_name, latitude, longitude, elevation_m,
           total_depth, top_perforation, bottom_perforation, well_role
    FROM Wells
  ")

  complete <- wells %>%
    filter(!is.na(latitude), !is.na(longitude), !is.na(elevation_m), !is.na(total_depth))

  incomplete <- wells %>%
    filter(is.na(latitude) | is.na(longitude) | is.na(elevation_m) | is.na(total_depth)) %>%
    mutate(
      missing_latlon = is.na(latitude) | is.na(longitude),
      missing_elevation = is.na(elevation_m),
      missing_total_depth = is.na(total_depth)
    )

  if (nrow(complete) == 0) {
    message("[leapfrog] No fully collar-ready wells found -- nothing to export.")
    return(invisible(NULL))
  }

  # ------------------------------------------------------------
  # Reproject lat/lon (EPSG:4326) -> UTM Zone 11N (EPSG:26911)
  # ------------------------------------------------------------
  pts <- st_as_sf(complete, coords = c("longitude", "latitude"), crs = 4326) %>%
    st_transform(26911)
  coords_utm <- st_coordinates(pts)
  complete$X <- coords_utm[, 1]
  complete$Y <- coords_utm[, 2]

  # ------------------------------------------------------------
  # COLLAR TABLE
  # ------------------------------------------------------------
  collar <- complete %>%
    transmute(
      HoleID = well_name,
      X = round(X, 2),
      Y = round(Y, 2),
      Z = round(elevation_m, 2),
      MaxDepth = round(total_depth * FT_TO_M, 2)
    )
  write_csv(collar, path(out_dir, "collar.csv"))

  # ------------------------------------------------------------
  # COLLAR (INCOMPLETE) -- reference only, not Leapfrog-ready
  # ------------------------------------------------------------
  if (nrow(incomplete) > 0) {
    collar_incomplete <- incomplete %>%
      transmute(
        HoleID = well_name,
        latitude, longitude, elevation_m,
        total_depth_ft = total_depth,
        missing_latlon, missing_elevation, missing_total_depth
      )
    write_csv(collar_incomplete, path(out_dir, "collar_incomplete.csv"))
  }

  # ------------------------------------------------------------
  # SURVEY TABLE -- real deviation surveys where they exist
  # (Well_Deviation_Surveys, added Session 33 after a project-wide
  # keyword search confirmed zero real directional data in any NDWR
  # driller's-report PDF; the one real exception on file, 83C-6ST1,
  # comes from Akerley et al. 2021's published drilling narrative, not
  # a well log), falling back to the assumed-vertical two-point trace
  # only for wells with no real survey rows.
  # ------------------------------------------------------------
  real_surveys <- tryCatch(
    dbGetQuery(con, "
      SELECT w.well_name AS HoleID, ds.depth_ft, ds.azimuth_deg, ds.inclination_deg,
             ds.data_quality, ds.notes
      FROM Well_Deviation_Surveys ds
      JOIN Wells w ON w.well_id = ds.well_id
    "),
    error = function(e) NULL
  )
  if (!is.null(real_surveys)) real_surveys <- real_surveys %>% filter(HoleID %in% collar$HoleID)

  wells_with_real_survey <- if (!is.null(real_surveys) && nrow(real_surveys) > 0) unique(real_surveys$HoleID) else character(0)

  survey_real <- if (length(wells_with_real_survey) > 0) {
    real_surveys %>%
      transmute(
        HoleID,
        Depth = round(depth_ft * FT_TO_M, 2),
        # Leapfrog convention: Dip = -90 (vertical) to 0 (horizontal);
        # this project's inclination_deg is degrees FROM vertical (0 =
        # vertical), so Dip = inclination_deg - 90. Left NA when the
        # source doesn't give a real station inclination (see notes).
        Azimuth = azimuth_deg,
        Dip = ifelse(is.na(inclination_deg), NA_real_, inclination_deg - 90),
        DataQuality = data_quality,
        Notes = notes
      )
  } else {
    tibble::tibble()
  }

  survey_assumed_vertical <- collar %>%
    filter(!(HoleID %in% wells_with_real_survey)) %>%
    { bind_rows(
        transmute(., HoleID, Depth = 0, Azimuth = 0, Dip = -90),
        transmute(., HoleID, Depth = MaxDepth, Azimuth = 0, Dip = -90)
      )
    } %>%
    mutate(DataQuality = "assumed_vertical", Notes = "No real deviation survey on file -- exported as a straight vertical trace.") %>%
    arrange(HoleID, Depth)

  survey <- bind_rows(survey_real, survey_assumed_vertical) %>% arrange(HoleID, Depth)
  write_csv(survey, path(out_dir, "survey.csv"))

  # ------------------------------------------------------------
  # LITHOLOGY TABLE -- real Well_Lithology rows only (well_id NOT
  # NULL, i.e. confidently matched to a named well; candidate/pending
  # rows like log 61248's, awaiting human confirmation, are correctly
  # excluded here, NOT silently included).
  # ------------------------------------------------------------
  lithology_real <- tryCatch(
    dbGetQuery(con, "
      SELECT w.well_name AS HoleID, wl.depth_from_ft, wl.depth_to_ft, wl.units AS lith_units, wl.description, wl.formation_unit, wl.formation_unit_basis, wl.notes
      FROM Well_Lithology wl
      JOIN Wells w ON w.well_id = wl.well_id
      WHERE wl.well_id IS NOT NULL
    "),
    error = function(e) NULL
  )
  if (!is.null(lithology_real) && nrow(lithology_real) > 0) {
    lithology_out <- lithology_real %>%
      filter(HoleID %in% collar$HoleID) %>%
      transmute(
        HoleID,
        # units='ft' (the project default) needs FT_TO_M; units='m' (e.g. Skalbeck Table 3's own metric well-log depths) is already correct and must NOT be double-converted -- a real bug found and fixed 2026-09-26 while testing this against real data (values were silently coming out ~3.28x too small).
        From = round(ifelse(lith_units == "m", depth_from_ft, depth_from_ft * FT_TO_M), 2),
        To = round(ifelse(lith_units == "m", depth_to_ft, depth_to_ft * FT_TO_M), 2),
        Description = description,
        FormationUnit = formation_unit,
        FormationUnitBasis = formation_unit_basis,
        IntervalType = "lithology",
        Notes = notes
      )
    if (nrow(lithology_out) > 0) write_csv(lithology_out, path(out_dir, "lithology.csv"))
  } else {
    lithology_out <- tibble::tibble()
  }

  # ------------------------------------------------------------
  # COMPLETION INTERVAL TABLE (NOT lithology -- see header comment)
  # ------------------------------------------------------------
  interval <- complete %>%
    filter(!is.na(top_perforation), !is.na(bottom_perforation)) %>%
    transmute(
      HoleID = well_name,
      From = round(top_perforation * FT_TO_M, 2),
      To = round(bottom_perforation * FT_TO_M, 2),
      IntervalType = "completion_interval",
      WellRole = well_role
    )
  if (nrow(interval) > 0) {
    write_csv(interval, path(out_dir, "completion_interval.csv"))
  }

  message("  -> collar.csv: ", nrow(collar), " wells (fully collar-ready)")
  message("  -> collar_incomplete.csv: ", nrow(incomplete), " wells (reference only)")
  if (length(wells_with_real_survey) > 0) {
    message("  -> survey.csv: ", nrow(survey), " rows -- ", length(wells_with_real_survey),
            " well(s) now have a REAL (non-vertical) deviation survey (", paste(wells_with_real_survey, collapse = ", "),
            "); the remaining ", nrow(collar) - length(wells_with_real_survey),
            " are still exported as an assumed-vertical two-point trace (no real survey on file).")
  } else {
    message("  -> survey.csv: ", nrow(survey), " rows (all vertical -- no real deviation data exists for any collar-ready well yet)")
  }
  message("  -> lithology.csv: ", nrow(lithology_out), " real interval(s) (well_id-confirmed Well_Lithology rows only -- ",
          "candidate/pending rows awaiting human identity confirmation are correctly excluded)")
  message("  -> completion_interval.csv: ", nrow(interval),
          " wells (casing/perforation interval, NOT lithology)")
  message("Leapfrog export complete: ", out_dir)

  invisible(list(
    collar_n = nrow(collar),
    incomplete_n = nrow(incomplete),
    interval_n = nrow(interval),
    lithology_n = nrow(lithology_out),
    wells_with_real_survey = wells_with_real_survey
  ))
}

#' Export Skalbeck (2001) Table A-2's real depth-model points as Leapfrog-
#' style horizon points -- one row per real UTM point per formation
#' contact (top of Qal / top of Tv / top of Alt-Kgd-Km / bedrock),
#' expressed as depth-below-ground-surface (m), NOT true elevation --
#' this project has no DEM at these points, so a real elevation value is
#' not fabricated. If/when a DEM becomes available, subtracting these
#' depths from it would give real Z values for Leapfrog import.
#' @param require_elevation If TRUE (default), a point with no real
#'   surface_elevation_m (from migrate_geophysical_depth_points_elevation()'s
#'   USGS Elevation Point Query Service lookup, run once against the
#'   real database 2026-09-26) is exported with Elevation_m = NA rather
#'   than a fabricated value -- real Z is only ever computed from a real
#'   DEM-sourced elevation, never guessed.
export_leapfrog_geophysical_horizons <- function(con, out_dir = "output/leapfrog") {
  message("---- Exporting Skalbeck (2001) depth-model points as Leapfrog horizon points ----")

  pts <- dbGetQuery(con, "
    SELECT point_id, utm_e, utm_n, latitude, longitude, surface_elevation_m, elevation_source,
           qal_thickness_m, tv_thickness_m, alt_kgd_km_thickness_m, depth_to_bedrock_m
    FROM Geophysical_Depth_Model_Points
  ")
  if (nrow(pts) == 0) {
    message("  -> No Geophysical_Depth_Model_Points rows -- nothing to export.")
    return(invisible(list(horizons_n = 0L)))
  }
  n_with_elev <- sum(!is.na(pts$surface_elevation_m))

  # Cumulative depth (top of the AltKgdpKm unit = base of Tv), needed for
  # the 4th horizon added 2026-09-26 -- previously only 3 of the 4 real
  # formation contacts in this dataset were exported.
  pts$top_altkgd_depth_m <- pts$qal_thickness_m + pts$tv_thickness_m
  horizons <- list()
  add_horizon <- function(name, depth_col) {
    d <- pts[!is.na(pts[[depth_col]]), ]
    if (nrow(d) == 0) return(NULL)
    data.frame(
      PointID = d$point_id, UTM_E = d$utm_e, UTM_N = d$utm_n,
      Latitude = d$latitude, Longitude = d$longitude,
      Horizon = name, DepthBelowSurface_m = d[[depth_col]],
      SurfaceElevation_m = d$surface_elevation_m,
      Elevation_m = ifelse(is.na(d$surface_elevation_m), NA_real_, d$surface_elevation_m - d[[depth_col]]),
      ElevationSource = d$elevation_source
    )
  }
  horizons[["qal_base"]] <- add_horizon("base_of_Qal_alluvium", "qal_thickness_m")
  horizons[["tv_base"]] <- add_horizon("base_of_Tv_volcanics", "tv_thickness_m")
  horizons[["altkgd_top"]] <- add_horizon("top_of_AltKgdpKm", "top_altkgd_depth_m")
  horizons[["depth_to_bedrock"]] <- add_horizon("depth_to_bedrock_Kgd", "depth_to_bedrock_m")
  out <- do.call(rbind, horizons[!sapply(horizons, is.null)])

  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  write_csv(out, fs::path(out_dir, "geophysical_horizons.csv"))
  message("  -> geophysical_horizons.csv: ", nrow(out), " horizon points across ",
          length(unique(out$Horizon)), " formation contact(s). ",
          n_with_elev, " of ", nrow(pts), " source points have a real USGS-3DEP surface elevation, ",
          "so Elevation_m (true Z) is now populated for those rows -- DepthBelowSurface_m/SurfaceElevation_m ",
          "are kept alongside it so the derivation stays auditable.")
  invisible(list(horizons_n = nrow(out), n_with_real_elevation = n_with_elev))
}

#' Export Skalbeck (2001) Table A-2's real depth-model points as
#' Leapfrog-style LITHOLOGY INTERVALS -- treating each UTM point as its
#' own tiny "mini well log": a stack of From/To/FormationUnit rows in
#' the exact same column shape as export_leapfrog_wells()'s real
#' lithology.csv, so a Leapfrog user (or any other consumer) sees ONE
#' consistent interval format whether the source is a real well log or
#' a Skalbeck geophysical model point. Added 2026-09-26, directly
#' answering the "map cleanly as a point source ... like mini well
#' logs" request -- deliberately NOT persisted as a new database
#' table (Geophysical_Depth_Model_Points already fully captures this
#' as cumulative thicknesses; a second, derived-at-export-time
#' representation avoids a second source of truth for the same data).
#'
#' Each point can contribute up to 4 intervals: Qal [0, qal_thickness],
#' Tv [qal_thickness, qal+tv], AltKgdpKm [qal+tv, depth_to_bedrock] --
#' only where the relevant thickness is a real, non-NA, positive
#' number. A 4th, open-ended "Kgd" interval starting at
#' depth_to_bedrock_m (no lower bound -- fresh bedrock is not resolved
#' any deeper by this model) is included with To = NA, flagged as
#' open-ended in its own Notes text, never given a fabricated lower
#' bound.
export_leapfrog_geophysical_lithology <- function(con, out_dir = "output/leapfrog") {
  message("---- Exporting Skalbeck (2001) depth-model points as Leapfrog mini-well-log lithology intervals ----")

  pts <- dbGetQuery(con, "
    SELECT point_id, qal_thickness_m, tv_thickness_m, alt_kgd_km_thickness_m, depth_to_bedrock_m
    FROM Geophysical_Depth_Model_Points
  ")
  if (nrow(pts) == 0) {
    message("  -> No Geophysical_Depth_Model_Points rows -- nothing to export.")
    return(invisible(list(intervals_n = 0L)))
  }

  out_rows <- list()
  for (i in seq_len(nrow(pts))) {
    p <- pts[i, ]
    hole_id <- paste0("A2PT_", p$point_id)
    cursor <- 0
    add_row <- function(depth_from, depth_to, unit, note) {
      out_rows[[length(out_rows) + 1]] <<- data.frame(
        HoleID = hole_id, From = depth_from, To = depth_to,
        Description = paste0(unit, " (Skalbeck 2001 Table A-2 model point, mini well log)"),
        FormationUnit = unit, FormationUnitBasis = "source_table_column",
        IntervalType = "geophysical_model_lithology", Notes = note
      )
    }
    if (!is.na(p$qal_thickness_m) && p$qal_thickness_m > 0) {
      add_row(cursor, cursor + p$qal_thickness_m, "Qal", NA_character_)
      cursor <- cursor + p$qal_thickness_m
    }
    if (!is.na(p$tv_thickness_m) && p$tv_thickness_m > 0) {
      add_row(cursor, cursor + p$tv_thickness_m, "Tv", NA_character_)
      cursor <- cursor + p$tv_thickness_m
    }
    if (!is.na(p$alt_kgd_km_thickness_m) && p$alt_kgd_km_thickness_m > 0) {
      add_row(cursor, cursor + p$alt_kgd_km_thickness_m, "AltKgdpKm", NA_character_)
      cursor <- cursor + p$alt_kgd_km_thickness_m
    }
    if (!is.na(p$depth_to_bedrock_m)) {
      add_row(p$depth_to_bedrock_m, NA_real_, "Kgd",
              "Open-ended -- fresh/final bedrock, no lower bound resolved by this model.")
    }
  }

  if (length(out_rows) == 0) {
    message("  -> No real formation-thickness data on any point -- nothing to export.")
    return(invisible(list(intervals_n = 0L)))
  }
  out <- do.call(rbind, out_rows)
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  write_csv(out, fs::path(out_dir, "geophysical_lithology_intervals.csv"))
  message("  -> geophysical_lithology_intervals.csv: ", nrow(out), " mini-well-log interval(s) across ",
          length(unique(out$HoleID)), " model point(s).")
  invisible(list(intervals_n = nrow(out), points_n = length(unique(out$HoleID))))
}

#' Interpolate Skalbeck (2001) Table A-2's real, irregularly-spaced
#' depth-model points onto a REGULAR grid, per formation contact --
#' turning the scattered point network into real, layered surfaces
#' Leapfrog (or ArcGIS) can use directly, rather than leaving every
#' consumer to interpolate the raw points themselves. Added
#' 2026-09-26, directly answering "should [Table A-2] create a grid
#' on Steamboat and have multiple layers at depth for leapfrog".
#'
#' Method: inverse-distance-weighting (`gstat::idw()`, power=2) in UTM
#' Zone 11N meters -- a real, standard geostatistical interpolator,
#' not a made-up smoothing. Deliberately NOT kriging: kriging needs a
#' real fitted variogram, which the analysis-first exploratory pass
#' in `notebooks/08_statistical_synthesis.qmd` has not yet done for
#' these specific depth surfaces (only for the all-time-pooled
#' chloride semivariogram) -- IDW is the honest, no-extra-assumptions
#' choice until that exists. `cell_size_m` defaults to 100 m, matching
#' Dhakal et al. (2025)'s own numerical-model grid resolution (see
#' README.md's "Key Literature Sources" section) so the two grids
#' are directly comparable if ever overlaid.
#'
#' Grid extent is the rectangular bounding box of the real points,
#' buffered by one cell -- corner/edge cells far from any real point
#' are a real IDW extrapolation, not a fabricated value, but should
#' be treated with more caution than cells near real control points
#' (`n_control_points` is recorded per layer for exactly this reason).
#' Three layers are output in one long CSV
#' (`geophysical_grid_surfaces.csv`): ground surface elevation is NOT
#' included (no real surface DEM grid is interpolated here, only the
#' sparse point elevations already on file) -- this file is
#' depth-below-surface layers only, matching
#' `geophysical_horizons.csv`'s own DepthBelowSurface_m convention.
export_leapfrog_geophysical_grid_surfaces <- function(con, out_dir = "output/leapfrog", cell_size_m = 100) {
  message("---- Interpolating Skalbeck (2001) Table A-2 onto a regular grid (IDW) ----")
  if (!requireNamespace("gstat", quietly = TRUE) || !requireNamespace("sp", quietly = TRUE)) {
    message("  -> gstat/sp not available -- skipping grid interpolation.")
    return(invisible(list(grid_n = 0L)))
  }

  pts <- dbGetQuery(con, "
    SELECT utm_e, utm_n, qal_thickness_m, tv_thickness_m, alt_kgd_km_thickness_m, depth_to_bedrock_m
    FROM Geophysical_Depth_Model_Points
    WHERE utm_e IS NOT NULL AND utm_n IS NOT NULL
  ")
  if (nrow(pts) < 4) {
    message("  -> Fewer than 4 real points with UTM coordinates -- nothing to interpolate.")
    return(invisible(list(grid_n = 0L)))
  }
  pts$top_altkgd_depth_m <- pts$qal_thickness_m + pts$tv_thickness_m

  bbox <- list(xmin = min(pts$utm_e) - cell_size_m, xmax = max(pts$utm_e) + cell_size_m,
               ymin = min(pts$utm_n) - cell_size_m, ymax = max(pts$utm_n) + cell_size_m)
  grid_xy <- expand.grid(
    utm_e = seq(bbox$xmin, bbox$xmax, by = cell_size_m),
    utm_n = seq(bbox$ymin, bbox$ymax, by = cell_size_m)
  )
  sp::coordinates(grid_xy) <- ~utm_e + utm_n

  interpolate_layer <- function(value_col, layer_name) {
    d <- pts[!is.na(pts[[value_col]]), c("utm_e", "utm_n", value_col)]
    if (nrow(d) < 4) return(NULL)
    names(d)[3] <- "z"
    sp::coordinates(d) <- ~utm_e + utm_n
    fit <- gstat::idw(z ~ 1, locations = d, newdata = grid_xy, idp = 2, debug.level = 0)
    out_df <- as.data.frame(sp::coordinates(fit))
    out_df$Depth_m <- fit$var1.pred
    out_df$Layer <- layer_name
    out_df$n_control_points <- nrow(d)
    out_df
  }

  layers <- list(
    interpolate_layer("qal_thickness_m", "base_of_Qal_alluvium"),
    interpolate_layer("top_altkgd_depth_m", "base_of_Tv_volcanics"),
    interpolate_layer("depth_to_bedrock_m", "top_of_fresh_Kgd")
  )
  out <- do.call(rbind, layers[!sapply(layers, is.null)])
  if (is.null(out) || nrow(out) == 0) {
    message("  -> No layer had enough real control points to interpolate.")
    return(invisible(list(grid_n = 0L)))
  }
  names(out)[1:2] <- c("UTM_E", "UTM_N")
  # Real points are never wrong by construction, but IDW can produce a
  # small negative depth right at the grid edge, just outside the real
  # point cloud -- clipped to 0, not reported as a negative depth,
  # since a below-ground formation can't start above ground surface.
  out$Depth_m <- pmax(out$Depth_m, 0)

  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  write_csv(out, fs::path(out_dir, "geophysical_grid_surfaces.csv"))
  message("  -> geophysical_grid_surfaces.csv: ", nrow(out), " grid cells across ",
          length(unique(out$Layer)), " interpolated layer(s), ", cell_size_m, " m cell size (IDW, power=2).")
  invisible(list(grid_n = nrow(out), cell_size_m = cell_size_m))
}
