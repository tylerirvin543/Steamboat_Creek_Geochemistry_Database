# ============================================================
# ingest_white_geyser_features.R
#
# Purpose:
# Ingests a user-digitized GIS feature inventory covering wells,
# springs, auger holes, fissures, and sinter/steaming-ground features
# from White, Thompson & Sandberg (1964, USGS PP 458-B) and White
# (1968, USGS PP 458-C), plus a handful of Mariner & Janik (1995)
# feature locations and two Geyser Society annotations -- hand-matched
# and digitized in ArcGIS against the published plates by the user.
#
# Source: data/raw/arcgis/excel ingest/
#   White&Geyser_Society_Mariner&Janik_GIS_located_wells_springs_features.xlsx
#   (raw, one messy sheet) was cleaned into
#   data/raw/arcgis/excel ingest/white_geyser_features_clean.csv
#   (41 features; two "auger hole 4"/"auger hole 5" duplicate rows --
#   one carrying coordinates, one carrying chemistry -- merged into one
#   row each; three identically-named "sinter cone from white" rows
#   disambiguated with a #1/#2/#3 suffix, since they are three distinct
#   real features, not duplicates).
#
# Most of these features sit in the Lower Sinter Terrace (lat
# ~39.378-39.389), which is directly useful for this thesis's LST
# scope shift (2026-10-24).
#
# Three match_action values drive what happens to each row:
#   - "fill_existing": an already-registered, currently coordinate-less
#     Locations row (GS-1, Herz 1, Herz 2, Peigh, Stmgid 4, Stuart) gets
#     its lat/long filled in -- never overwrites an existing coordinate.
#   - "discrepancy_flag_only": a similarly-named existing Location
#     already HAS a real (different-source) coordinate that disagrees
#     with this sheet's point by a meaningful distance (Curti ~1.6 km,
#     Brown School ~230 m, Cox I-1 ~580 m) -- logged to
#     data/derived/white_geyser_coordinate_discrepancies.csv for human
#     review, the existing Locations row is NOT touched.
#   - "new": no existing match -- a new, real-coordinate Locations row
#     is created.
#
# Only 3 of the 41 features (GS-1, auger hole 4, auger hole 5) carry
# real numeric chemistry/temperature values (White reports Cl, pH, SC,
# bottom-hole temperature, depth, depth-to-water for these) -- those get
# real Sampling_Events/Samples/Lab_Analyses/Field_Measurements rows so
# they're queryable (e.g. via vw_major_ions) like any other sample. The
# other 38 features are geologic/structural points (fissures, sinter
# cones, auger holes with no reported chemistry, etc.) with no sample
# to attach -- their White 1964/1968-sourced description lives in
# Locations.notes only.
#
# Idempotency: matched on Locations.external_station_code (UNIQUE,
# 'WHITE1968_<slug>') for new rows; fill_existing matches update the
# fixed match_location_id row only if its latitude is currently NULL;
# Sampling_Events/Samples/Lab_Analyses/Field_Measurements follow this
# project's standard external_event_id / external_sample_id / anti_join
# idempotency pattern (see ingest_historical_sorey1992.R).
# ============================================================

library(DBI)
library(dplyr)
library(readr)
library(fs)

ingest_white_geyser_features <- function(
    con,
    csv_path = "data/raw/arcgis/excel ingest/white_geyser_features_clean.csv",
    discrepancy_csv = "data/derived/white_geyser_coordinate_discrepancies.csv") {

  message("---- Starting White/Geyser Society/Mariner & Janik GIS feature ingest ----")

  if (!file_exists(csv_path)) {
    message("[white geyser features] No file at ", csv_path, " -- skipping.")
    return(invisible(NULL))
  }

  dbExecute(con, "PRAGMA foreign_keys = ON;")

  rows <- read_csv(csv_path, show_col_types = FALSE,
                    col_types = cols(date_parsed = col_character()))

  dbExecute(con, "
    INSERT OR IGNORE INTO Data_Sources (name, notes)
    VALUES (
      'White 1964/1968 + Geyser Society + Mariner & Janik 1995 (digitized GIS features)',
      'data/raw/arcgis/excel ingest/White&Geyser_Society_Mariner&Janik_GIS_located_wells_springs_features.xlsx; user-digitized in ArcGIS against published plates, ingested 2026-10-24.'
    )
  ")
  source_id <- dbGetQuery(con,
    "SELECT source_id FROM Data_Sources WHERE name = 'White 1964/1968 + Geyser Society + Mariner & Janik 1995 (digitized GIS features)'"
  )$source_id[1]

  locations_created <- 0L
  coords_filled <- 0L
  discrepancies <- list()
  loc_id_map <- rep(NA_integer_, nrow(rows))

  for (i in seq_len(nrow(rows))) {
    r <- rows[i, ]
    note_text <- paste0(
      "White/Geyser Society/Mariner & Janik GIS feature '", r$location_name, "'.",
      if (!is.na(r$notes)) paste0(" Notes from White: ", r$notes) else "",
      if (!is.na(r$bare_lon_only) && isTRUE(r$bare_lon_only)) " [Source sheet gave only a longitude value for this row -- latitude is unavailable, feature left coordinate-less.]" else ""
    )

    if (r$match_action == "discrepancy_flag_only") {
      existing <- dbGetQuery(con,
        "SELECT location_id, name, latitude, longitude FROM Locations WHERE location_id = ?",
        params = list(r$match_location_id))
      dist_m <- NA_real_
      if (nrow(existing) > 0 && !is.na(existing$latitude[1]) && !is.na(r$latitude)) {
        dlat <- (r$latitude - existing$latitude[1]) * 111320
        dlon <- (r$longitude - existing$longitude[1]) * 111320 * cos(r$latitude * pi / 180)
        dist_m <- sqrt(dlat^2 + dlon^2)
      }
      discrepancies[[length(discrepancies) + 1]] <- data.frame(
        sheet_feature_name = r$location_name,
        existing_location_id = r$match_location_id,
        existing_location_name = r$match_location_name,
        existing_lat = if (nrow(existing) > 0) existing$latitude[1] else NA_real_,
        existing_lon = if (nrow(existing) > 0) existing$longitude[1] else NA_real_,
        sheet_lat = r$latitude,
        sheet_lon = r$longitude,
        distance_m = dist_m,
        recommendation = "Not applied -- existing Locations row left untouched. Review manually.",
        stringsAsFactors = FALSE
      )
      next
    }

    if (r$match_action == "fill_existing") {
      existing <- dbGetQuery(con,
        "SELECT location_id, latitude, notes FROM Locations WHERE location_id = ?",
        params = list(r$match_location_id))
      if (nrow(existing) == 0) {
        warning("[white geyser features] fill_existing target location_id ",
                r$match_location_id, " not found -- skipping '", r$location_name, "'.")
        next
      }
      loc_id <- existing$location_id[1]
      if (is.na(existing$latitude[1]) && !is.na(r$latitude)) {
        existing_notes <- existing$notes[1]
        new_notes <- if (is.na(existing_notes) || existing_notes == "") note_text else paste(existing_notes, note_text)
        dbExecute(con, "
          UPDATE Locations SET latitude = ?, longitude = ?,
            coordinate_source = 'white_geyser_society_gis_digitized',
            coordinate_uncertainty_m = 75,
            notes = ?
          WHERE location_id = ?",
          params = list(r$latitude, r$longitude, new_notes, loc_id))
        coords_filled <- coords_filled + 1L
      }
      loc_id_map[i] <- loc_id
      next
    }

    # match_action == "new"
    existing_new <- dbGetQuery(con,
      "SELECT location_id FROM Locations WHERE external_station_code = ?",
      params = list(r$external_station_code))
    if (nrow(existing_new) > 0) {
      loc_id_map[i] <- existing_new$location_id[1]
      next
    }
    lat <- if (isTRUE(r$bare_lon_only)) NA_real_ else r$latitude
    dbExecute(con, "
      INSERT INTO Locations
        (external_station_code, name, latitude, longitude, crs, site_type,
         coordinate_source, coordinate_uncertainty_m, notes)
      VALUES (?, ?, ?, ?, 'EPSG:4326', ?, 'white_geyser_society_gis_digitized', 75, ?)
    ", params = list(
      r$external_station_code, r$location_name, lat, r$longitude,
      r$site_type, note_text
    ))
    loc_id_map[i] <- dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id
    locations_created <- locations_created + 1L
  }
  rows$location_id <- loc_id_map

  if (length(discrepancies) > 0) {
    dir_create(path_dir(discrepancy_csv))
    write_csv(bind_rows(discrepancies), discrepancy_csv)
    message("  -> ", length(discrepancies),
            " coordinate discrepancy(ies) logged to ", discrepancy_csv, " (not applied).")
  }

  # ------------------------------------------------------------
  # Real chemistry/temperature rows (GS-1, auger hole 4, auger hole 5 only)
  # ------------------------------------------------------------
  chem_rows <- rows |> filter(!is.na(cl_ppm) | !is.na(pH) | !is.na(Sc) | !is.na(BHT_C))

  events_created <- 0L
  samples_created <- 0L
  field_meas_inserted <- 0L
  lab_rows_inserted <- 0L

  if (nrow(chem_rows) > 0) {
    for (i in seq_len(nrow(chem_rows))) {
      r <- chem_rows[i, ]
      if (is.na(r$location_id)) next

      sample_date <- if (!is.na(r$date_parsed)) r$date_parsed else "1968-01-01"
      date_precision <- if (!is.na(r$date_parsed)) r$date_precision else "unknown"

      ext_event <- paste0("WHITE1968_", r$external_station_code, "_", sample_date)
      existing_event <- dbGetQuery(con,
        "SELECT event_id FROM Sampling_Events WHERE external_event_id = ?",
        params = list(ext_event))
      if (nrow(existing_event) > 0) {
        event_id <- existing_event$event_id[1]
      } else {
        dbExecute(con, "
          INSERT INTO Sampling_Events (external_event_id, date, purpose, notes)
          VALUES (?, ?, 'historical', ?)
        ", params = list(
          ext_event, sample_date,
          paste0("date_precision='", date_precision, "' (see white_geyser_features_clean.csv)")
        ))
        event_id <- dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id
        events_created <- events_created + 1L
      }

      ext_sample <- ext_event
      existing_sample <- dbGetQuery(con,
        "SELECT sample_id FROM Samples WHERE external_sample_id = ?",
        params = list(ext_sample))
      if (nrow(existing_sample) > 0) {
        sample_id <- existing_sample$sample_id[1]
      } else {
        dbExecute(con, "
          INSERT INTO Samples
            (location_id, event_id, sample_type, collection_time,
             external_event_id, external_sample_id, data_source, notes)
          VALUES (?, ?, 'historical', ?, ?, ?, 'White 1964/1968', ?)
        ", params = list(
          r$location_id, event_id, sample_date, ext_event, ext_sample, r$notes
        ))
        sample_id <- dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id
        samples_created <- samples_created + 1L
      }

      # Field measurement: bottom-hole temperature (deg C, per the
      # source column header "BHT(C)" -- the raw xlsx header rendered
      # as "BHT(c)" with a mangled copyright-symbol artifact in place
      # of the degree sign, confirmed plausible by cross-checking GS-1's
      # 156.9 against its own notes field describing a shallower 158 F
      # (~70 C) reading higher up the same temperature-depth profile).
      if (!is.na(r$BHT_C)) {
        existing_fm <- dbGetQuery(con,
          "SELECT measurement_id FROM Field_Measurements WHERE sample_id = ? AND parameter = 'temperature' AND source_id = ?",
          params = list(sample_id, source_id))
        if (nrow(existing_fm) == 0) {
          dbExecute(con, "
            INSERT INTO Field_Measurements (sample_id, parameter, value, units, instrument, source_id)
            VALUES (?, 'temperature', ?, 'deg C', 'White 1964/1968 bottom-hole temperature', ?)
          ", params = list(sample_id, r$BHT_C, source_id))
          field_meas_inserted <- field_meas_inserted + 1L
        }
      }

      lab_vals <- list(
        Cl = r$cl_ppm,
        pH = r$pH,
        SC = r$Sc
      )
      units_for <- c(Cl = "mg/L", pH = "SU", SC = "uS/cm")
      for (analyte in names(lab_vals)) {
        val <- lab_vals[[analyte]]
        if (is.na(val)) next
        existing_la <- dbGetQuery(con,
          "SELECT analysis_id FROM Lab_Analyses WHERE sample_id = ? AND analyte = ? AND source_id = ?",
          params = list(sample_id, analyte, source_id))
        if (nrow(existing_la) > 0) next
        dbExecute(con, "
          INSERT INTO Lab_Analyses (sample_id, analyte, value, units, fraction, method, detection_limit, qualifier, source_id)
          VALUES (?, ?, ?, ?, NULL, 'White 1964/1968', NULL, NULL, ?)
        ", params = list(sample_id, analyte, val, units_for[[analyte]], source_id))
        lab_rows_inserted <- lab_rows_inserted + 1L
      }
    }
  }

  message("  -> Locations created: ", locations_created,
          " | Coordinates filled on existing Locations: ", coords_filled,
          " | Discrepancies logged (not applied): ", length(discrepancies),
          " | Sampling_Events created: ", events_created,
          " | Samples created: ", samples_created,
          " | Field_Measurements inserted: ", field_meas_inserted,
          " | Lab_Analyses rows inserted: ", lab_rows_inserted)
  message("White/Geyser Society/Mariner & Janik GIS feature ingest complete.")

  invisible(list(
    locations_created = locations_created,
    coords_filled = coords_filled,
    discrepancies = length(discrepancies),
    events_created = events_created,
    samples_created = samples_created,
    field_measurements_inserted = field_meas_inserted,
    lab_rows_inserted = lab_rows_inserted
  ))
}
