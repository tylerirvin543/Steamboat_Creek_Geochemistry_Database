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
      SELECT w.well_name AS HoleID, wl.depth_from_ft, wl.depth_to_ft, wl.description, wl.notes
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
        From = round(depth_from_ft * FT_TO_M, 2),
        To = round(depth_to_ft * FT_TO_M, 2),
        Description = description,
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
