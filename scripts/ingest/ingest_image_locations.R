# ============================================================
# ingest_image_locations.R
#
# Purpose:
# Streamline turning field photos and videos into registered Locations, using
# exiftool to pull GPS coordinates out of embedded metadata instead
# of manually reading them off a phone/camera/drone and typing coordinates
# in by hand. As of 2026-09-06 this also scans common video containers
# (mp4/mov/m4v), though many videos -- especially drone footage -- carry
# no embedded GPS at all; those are simply skipped by Step 1 rather than
# erroring, and can still get a manual coordinate in Step 2's mapping file.
#
# Workflow (two deliberately separate steps -- GPS extraction is
# automatic when a file has it, but "this filename is this named site" is a user
# judgment call that is never inferred):
#
#   1. AUTOMATIC: every photo or video dropped in data/raw/images/image_drop/
#      gets its GPS lat/lon/altitude + capture time extracted via
#      exiftool.exe and appended to Photo_Location_Candidates (raw,
#      append-only, keyed by filename -- safe to re-run any time).
#
#   2. USER-CONFIRMED: data/raw/images/image_location_map.csv (a
#      plain spreadsheet you maintain -- NOT auto-generated) maps a
#      filename to an external_station_code, site_type, and name.
#      Only rows present in this mapping ever create or touch a row
#      in `Locations`:
#        - New code -> a new Location is registered from the photo's
#          GPS coordinates.
#        - Existing code -> the Location is NOT overwritten; instead
#          the photo-derived coordinate is compared to the registered
#          one and logged to Photo_Location_QC, so a mismatch (e.g. a
#          photo actually showing a different, already-registered
#          site) is caught automatically instead of requiring a
#          manual spot-check.
#
# Folders:
#   data/raw/images/exiftool/exiftool.exe   -- the exiftool binary
#   data/raw/images/image_drop/             -- drop new photos here
#   data/raw/images/image_location_map.csv  -- filename -> site mapping
#
# image_location_map.csv columns:
#   filename, external_station_code, site_type, name, notes
# (site_type must be one of the Locations.site_type CHECK values:
#  spring, creek, well, background, fumarole, seep, steaming ground,
#  transect)
#
# Optional additional columns (see notebooks/04_photo_location_workflow.qmd):
#   observation_note          -- a qualitative field note logged to
#                                Field_Observations alongside the location
#   linked_external_sample_id -- ties that note to a specific Samples row,
#                                if the photo documents a sample collection
# ============================================================

library(DBI)
library(dplyr)
library(readr)
library(fs)

# Conservative default horizontal-uncertainty (meters) assigned to a
# photo-derived Location when the device didn't report its own
# GPSHPositioningError -- typical phone GPS is commonly cited around
# 5-15 m in open sky, worse under tree/canyon cover common at this site;
# see notebooks/04_photo_location_workflow.qmd for the full reasoning.
# This is a documented assumption, not a precision claim.
DEFAULT_PHOTO_GPS_UNCERTAINTY_M <- 15

#' Great-circle distance in meters (haversine), for comparing a
#' photo's GPS fix against an already-registered location.
haversine_m <- function(lat1, lon1, lat2, lon2) {
  r <- 6371000
  to_rad <- function(x) x * pi / 180
  dlat <- to_rad(lat2 - lat1)
  dlon <- to_rad(lon2 - lon1)
  a <- sin(dlat / 2)^2 + cos(to_rad(lat1)) * cos(to_rad(lat2)) * sin(dlon / 2)^2
  2 * r * asin(pmin(1, sqrt(a)))
}

#' Run exiftool over every photo or video in `image_dir`, returning a data
#' frame with one row per file (GPS columns are NA for non-geotagged
#' images/videos, e.g. screenshots or GPS-less drone clips (see file header).
extract_photo_gps <- function(image_dir, exiftool_path) {
  args <- c(
    "-csv", "-gpslatitude", "-gpslongitude", "-gpsaltitude",
    "-gpshpositioningerror",  # device-reported horizontal accuracy (m), when recorded
    "-datetimeoriginal", "-filename",
    "-ext", "heic", "-ext", "jpg", "-ext", "jpeg", "-ext", "png", "-ext", "tif", "-ext", "tiff", "-ext", "mp4", "-ext", "mov", "-ext", "m4v",
    "-n",  # numeric GPS output instead of "39 deg 22' 56.66\" N"
    image_dir
  )
  out <- suppressWarnings(system2(exiftool_path, args, stdout = TRUE, stderr = FALSE))
  if (length(out) == 0) return(NULL)
  read_csv(paste(out, collapse = "\n"), show_col_types = FALSE)
}

ingest_image_locations <- function(con,
                                    image_dir = "data/raw/images/image_drop",
                                    exiftool_path = "data/raw/images/exiftool/exiftool.exe",
                                    map_csv = "data/raw/images/image_location_map.csv") {

  message("---- Starting image-location (EXIF GPS) ingest ----")

  if (!file_exists(exiftool_path)) {
    message("[image locations] exiftool not found at ", exiftool_path, " — skipping.")
    return(invisible(NULL))
  }
  if (!dir_exists(image_dir) || length(dir_ls(image_dir, type = "file")) == 0) {
    message("[image locations] No photos in ", image_dir, " — skipping.")
    return(invisible(NULL))
  }

  # ------------------------------------------------------------
  # STEP 1 — AUTOMATIC: extract GPS, append new filenames only
  # ------------------------------------------------------------
  raw <- extract_photo_gps(image_dir, exiftool_path)

  if (is.null(raw) || nrow(raw) == 0) {
    message("[image locations] exiftool returned no rows — skipping.")
    return(invisible(NULL))
  }

  if (!"GPSHPositioningError" %in% names(raw)) raw$GPSHPositioningError <- NA_character_

  candidates <- raw |>
    transmute(
      filename   = FileName,
      gps_lat    = suppressWarnings(as.numeric(GPSLatitude)),
      gps_lon    = suppressWarnings(as.numeric(GPSLongitude)),
      gps_alt_m  = suppressWarnings(as.numeric(GPSAltitude)),
      gps_h_accuracy_m = suppressWarnings(as.numeric(GPSHPositioningError)),
      taken_at   = suppressWarnings(as.character(
        as.POSIXct(DateTimeOriginal, format = "%Y:%m:%d %H:%M:%S", tz = "UTC")
      )),
      source_dir = image_dir,
      ingested_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC")
    ) |>
    filter(!is.na(gps_lat), !is.na(gps_lon))

  n_no_gps <- nrow(raw) - nrow(candidates)
  if (n_no_gps > 0) {
    message("  → ", n_no_gps, " file(s) had no GPS tag — skipped from candidates.")
  }

  existing_files <- dbGetQuery(con, "SELECT filename FROM Photo_Location_Candidates")$filename
  new_candidates <- candidates |> filter(!(filename %in% existing_files))

  if (nrow(new_candidates) > 0) {
    dbAppendTable(con, "Photo_Location_Candidates", new_candidates)
    message("  → Extracted GPS for ", nrow(new_candidates), " new photo(s).")
  } else {
    message("  → No new photos since last run.")
  }

  # ------------------------------------------------------------
  # STEP 2 — HUMAN-CONFIRMED: apply filename -> site mapping
  # ------------------------------------------------------------
  if (!file_exists(map_csv)) {
    message("[image locations] No mapping file at ", map_csv,
            " yet — GPS extracted and staged in Photo_Location_Candidates, ",
            "but no Locations will be created/checked until you add one.")
    return(invisible(NULL))
  }

  map <- read_csv(map_csv, show_col_types = FALSE)
  required_map_cols <- c("filename", "external_station_code", "site_type", "name")
  missing_cols <- setdiff(required_map_cols, names(map))
  if (length(missing_cols) > 0) {
    warning("image_location_map.csv missing required column(s): ",
            paste(missing_cols, collapse = ", "), " — skipping mapping step.", call. = FALSE)
    return(invisible(NULL))
  }

  all_candidates <- dbGetQuery(con, "SELECT * FROM Photo_Location_Candidates")
  mapped <- map |> inner_join(all_candidates, by = "filename")

  if (nrow(mapped) == 0) {
    message("[image locations] Mapping file has no rows matching a known photo yet.")
    return(invisible(NULL))
  }

  existing_locations <- dbGetQuery(con, "SELECT location_id, external_station_code, latitude, longitude FROM Locations")

  new_sites <- mapped |>
    filter(!(external_station_code %in% existing_locations$external_station_code)) |>
    distinct(external_station_code, .keep_all = TRUE)

  if (nrow(new_sites) > 0) {
    bad_site_type <- new_sites |> filter(is.na(site_type) | site_type == "")
    if (nrow(bad_site_type) > 0) {
      warning("Skipping new site(s) missing a site_type in image_location_map.csv: ",
              paste(bad_site_type$external_station_code, collapse = ", "), call. = FALSE)
      new_sites <- new_sites |> filter(!is.na(site_type), site_type != "")
    }
  }

  if (nrow(new_sites) > 0) {
    to_insert <- new_sites |>
      transmute(
        external_station_code,
        name = if_else(!is.na(name) & name != "", name, external_station_code),
        latitude = gps_lat,
        longitude = gps_lon,
        elevation_m = gps_alt_m,
        crs = "EPSG:4326",
        coordinate_source = "photo_gps",
        coordinate_uncertainty_m = if_else(!is.na(gps_h_accuracy_m), gps_h_accuracy_m, DEFAULT_PHOTO_GPS_UNCERTAINTY_M),
        site_type,
        notes = if ("notes" %in% names(new_sites)) notes else NA_character_
      )
    dbAppendTable(con, "Locations", to_insert)
    message("  → Registered ", nrow(to_insert), " new Location(s) from photo GPS: ",
            paste(to_insert$external_station_code, collapse = ", "))
  }

  # Existing sites: compare, never overwrite -- log to Photo_Location_QC
  existing_matches <- mapped |>
    filter(external_station_code %in% existing_locations$external_station_code) |>
    left_join(existing_locations, by = "external_station_code")

  if (nrow(existing_matches) > 0) {
    qc_rows <- existing_matches |>
      mutate(
        distance_m = haversine_m(latitude, longitude, gps_lat, gps_lon),
        flagged_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC")
      ) |>
      transmute(
        filename, external_station_code,
        registered_lat = latitude, registered_lon = longitude,
        photo_lat = gps_lat, photo_lon = gps_lon,
        distance_m, flagged_at
      )

    already_logged <- dbGetQuery(con, "SELECT filename, external_station_code FROM Photo_Location_QC")
    qc_rows <- qc_rows |> anti_join(already_logged, by = c("filename", "external_station_code"))

    if (nrow(qc_rows) > 0) {
      dbAppendTable(con, "Photo_Location_QC", qc_rows)
      big_mismatch <- qc_rows |> filter(distance_m > 50)
      if (nrow(big_mismatch) > 0) {
        warning(
          nrow(big_mismatch), " photo(s) mapped to an existing site differ by >50 m ",
          "from that site's registered coordinates -- check Photo_Location_QC:\n  - ",
          paste(big_mismatch$filename, collapse = "\n  - "),
          call. = FALSE
        )
      }
      message("  → Logged ", nrow(qc_rows), " photo-vs-registered coordinate comparison(s) to Photo_Location_QC.")
    }
  }


  # ------------------------------------------------------------
  # STEP 3 -- OPTIONAL: qualitative field observations/sample linkage
  #
  # image_location_map.csv may optionally include `observation_note`
  # and/or `linked_external_sample_id` columns -- when a mapped row has
  # a non-blank observation_note, it becomes a Field_Observations row,
  # so "this photo shows the site" and "this is what was observed/
  # sampled there" are recorded from the same one-row CSV edit rather
  # than needing two disconnected steps. Rows without a note behave
  # exactly as before (location registration/QC only).
  # ------------------------------------------------------------
  if ("observation_note" %in% names(mapped)) {
    obs_rows <- mapped |> filter(!is.na(observation_note), observation_note != "")

    if (nrow(obs_rows) > 0) {
      current_locations <- dbGetQuery(con, "SELECT location_id, external_station_code FROM Locations")

      if ("linked_external_sample_id" %in% names(obs_rows)) {
        samples_lookup <- dbGetQuery(con, "SELECT sample_id, external_sample_id FROM Samples")
        obs_rows <- obs_rows |>
          left_join(samples_lookup, by = c("linked_external_sample_id" = "external_sample_id"))
      } else {
        obs_rows$sample_id <- NA_integer_
      }

      obs_rows <- obs_rows |>
        left_join(current_locations, by = "external_station_code") |>
        filter(!is.na(location_id))

      already_noted <- dbGetQuery(con, "SELECT source_photo_filename FROM Field_Observations WHERE source_photo_filename IS NOT NULL")
      obs_rows <- obs_rows |> filter(!(filename %in% already_noted$source_photo_filename))

      if (nrow(obs_rows) > 0) {
        to_insert_obs <- obs_rows |>
          transmute(
            location_id, sample_id,
            observed_at = taken_at,
            observer = NA_character_,
            note = observation_note,
            source_photo_filename = filename
          )
        dbAppendTable(con, "Field_Observations", to_insert_obs)
        message("  -> Logged ", nrow(to_insert_obs), " field observation(s) from photo notes.")
      }
    }
  }

  message("---- Image-location ingest complete ----")
  invisible(NULL)
}
