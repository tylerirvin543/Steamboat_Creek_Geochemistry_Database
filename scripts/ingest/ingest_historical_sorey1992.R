# ============================================================
# ingest_historical_sorey1992.R
#
# Purpose:
# Ingests the ~10 dated 1981-1991 major-ion chemistry analyses from
# Table 1 of Sorey, M.L. and Colvard, E.M. (1992), "Factors Affecting
# the Decline in Hot-Spring Activity in the Steamboat Springs Area of
# Critical Environmental Concern, Washoe County, Nevada" (USGS
# Administrative Report for the BLM), read directly from
# docs/literature/Sorey_StmbtSprgsHSActivity_1992.pdf. This is the
# single most detailed pre-Ormat-era chemistry dataset this project has
# direct access to, and extends this project's Cl/B/Li ratio and
# thermal-water chemistry record back to 1950 (well GS-5) / 1977
# (spring 6) for the first time.
#
# Data file: data/raw/historical/sorey1992_table1_chemistry.csv
#   (hand-transcribed, one row per sample, with a matched_well_name
#   column filled in only where an existing Wells row was confirmed --
#   never guessed. As of 2026-09-12, 83A-6, Cox 1-1, and the
#   OCR-artifact "GS-58"/"GS-59" (both really well GS-5 -- see
#   register_sorey1992_resolved_wells() below) are resolved via exact
#   NBMG Geothermal_Wells name matches
#   (data/raw/wells/sorey1992_nbmg_resolved_wells.csv). "Hot spring 6"
#   remains genuinely unresolved (its coordinate-less provisional
#   Locations row is kept, not dropped, per this project's well-log/
#   NDOM provisional-entity conventions) -- it is the
#   historically-active, currently-dormant main-terrace spring this
#   thesis's own spring-remapping fieldwork is specifically looking for.
#
# Units/analyte-code notes (see comments inline below for why):
#   - HCO3 is stored under this project's standard 'Alkalinity' code
#     (HCO3-mass-equivalent mg/L convention used project-wide since the
#     2026-09-06 NDEP alkalinity fix) with conversion_factor = 1, since
#     Sorey's Table 1 already reports true HCO3 mass (not CaCO3-basis).
#   - SiO2 is stored under a distinct 'SiO2' code (NOT this project's
#     'Si' element code used elsewhere) because Sorey's table header
#     literally says "SiO2" and this project has not independently
#     confirmed whether that is on an SiO2-mass or Si-element basis --
#     rather than silently assume equivalence with 'Si', it is kept
#     separate and flagged here and in the notebook.
#   - TWH (wellhead temperature) is a real field measurement -> stored
#     as 'temperature'. TDH (downhole temperature) and T_NaKCa
#     (Na-K-Ca cation-geothermometer estimate) are NOT measurements --
#     stored as separate, clearly-named derived-value codes
#     ('temperature_downhole', 'temperature_geothermometer_nakca') so
#     they can never be confused with a real field/lab temperature
#     reading downstream (e.g. by build_phreeqc_solutions()).
#   - B and Li are stored as reported (mg/L) without forcing a unit
#     conversion to this project's more common ug/L convention for
#     these analytes -- Lab_Analyses already tolerates mixed mg/L and
#     ug/L rows for B/Li from other sources (see AGENTS.md Session 15/16
#     notes); any downstream aggregation must already normalize by
#     `units` per row, which build_phreeqc_solutions() already does.
#
# Idempotency: matched on (external_station_code) for Locations,
# (external_sample_id) for Samples, and (sample_id, analyte, source_id)
# for Lab_Analyses -- same anti_join pattern as ingest_isotopes.R /
# ingest_lab.R. Safe to re-run.
# ============================================================

library(DBI)
library(dplyr)
library(readr)
library(fs)


# ============================================================
# register_sorey1992_resolved_wells()
#
# 2026-09-12 (session 28): several Table 1 features originally shipped
# as "unresolved" (83A-6, Cox 1-1, and the OCR-artifact "GS-58"/"GS-59",
# both of which turn out to really be well GS-5 -- see
# data/raw/wells/sorey1992_nbmg_resolved_wells.csv for the full
# reasoning) were resolved against NBMG's statewide Geothermal_Wells
# layer by exact well-name match. This registers them as real Wells
# rows (idempotent on well_name, mirrors register_well_coordinates.R's
# "only insert if missing, never overwrite" philosophy) BEFORE the main
# ingest below runs, so its Wells/Well_Aliases lookup can find them.
# ============================================================
register_sorey1992_resolved_wells <- function(
    con,
    csv_path = "data/raw/wells/sorey1992_nbmg_resolved_wells.csv") {

  if (!file_exists(csv_path)) {
    message("[sorey1992] No resolved-wells file at ", csv_path, " -- skipping well registration.")
    return(invisible(NULL))
  }

  resolved <- read_csv(csv_path, show_col_types = FALSE)
  wells_created <- 0L

  for (i in seq_len(nrow(resolved))) {
    r <- resolved[i, ]
    existing <- dbGetQuery(con, "SELECT well_id FROM Wells WHERE well_name = ?",
                            params = list(r$well_name))
    if (nrow(existing) == 0) {
      dbExecute(con, "
        INSERT INTO Wells
          (well_name, well_role, latitude, longitude,
           coordinate_source, coordinate_uncertainty_m, notes)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      ", params = list(
        r$well_name, r$well_role, r$latitude, r$longitude,
        r$coordinate_source, r$coordinate_uncertainty_m,
        paste0("APINO ", r$apino, ". ", r$notes)
      ))
      wells_created <- wells_created + 1L
    }
  }
  message("[sorey1992] Resolved wells registered: ", wells_created, " new Wells row(s).")
  invisible(list(wells_created = wells_created))
}


# ============================================================
# register_sorey1992_perforation_data()
#
# 2026-09-12 (follow-up session): Tables 6/7 (CPI/SB GEO well-completion
# information) give real casing-depth / open-hole-interval data for
# several already-resolved wells. Wells.top_perforation/bottom_perforation
# are currently NULL for every one of these wells, so this fills them --
# but ONLY when the CSV supplies a value AND the target field is
# currently NULL (per-field, never overwrites), and ONLY for wells where
# the report's own total depth doesn't substantially conflict with an
# existing Wells.total_depth (two real conflicts -- 23-5 and IW-2, both
# almost certainly explained by deepening since 1990 -- are deliberately
# NOT numerically filled; see data/raw/wells/sorey1992_perforation_data.csv
# for the reasoning). Every row's notes are appended to Wells.notes
# (idempotent: skipped if the '[Sorey1992 Table 6/7 perforation data]'
# marker is already present) regardless of whether any numeric field
# actually got filled, so the historical fact is recorded either way.
# ============================================================
register_sorey1992_perforation_data <- function(
    con,
    csv_path = "data/raw/wells/sorey1992_perforation_data.csv") {

  if (!file_exists(csv_path)) {
    message("[sorey1992] No perforation-data file at ", csv_path, " -- skipping.")
    return(invisible(NULL))
  }

  perf <- read_csv(csv_path, show_col_types = FALSE)
  fields_filled <- 0L
  notes_appended <- 0L

  for (i in seq_len(nrow(perf))) {
    r <- perf[i, ]
    well <- dbGetQuery(con, "SELECT well_id, total_depth, top_perforation, bottom_perforation, notes FROM Wells WHERE well_name = ?",
                        params = list(r$well_name))
    if (nrow(well) == 0) {
      warning("[sorey1992 perforation] well_name '", r$well_name, "' not found in Wells -- skipped.")
      next
    }
    well_id <- well$well_id[1]

    if (!is.na(r$total_depth_ft) && is.na(well$total_depth[1])) {
      dbExecute(con, "UPDATE Wells SET total_depth = ? WHERE well_id = ?", params = list(r$total_depth_ft, well_id))
      fields_filled <- fields_filled + 1L
    }
    if (!is.na(r$top_perforation_ft) && is.na(well$top_perforation[1])) {
      dbExecute(con, "UPDATE Wells SET top_perforation = ? WHERE well_id = ?", params = list(r$top_perforation_ft, well_id))
      fields_filled <- fields_filled + 1L
    }
    if (!is.na(r$bottom_perforation_ft) && is.na(well$bottom_perforation[1])) {
      dbExecute(con, "UPDATE Wells SET bottom_perforation = ? WHERE well_id = ?", params = list(r$bottom_perforation_ft, well_id))
      fields_filled <- fields_filled + 1L
    }

    existing_notes <- well$notes[1]
    marker <- "[Sorey1992 Table 6/7 perforation data]"
    already_noted <- !is.na(existing_notes) && grepl(marker, existing_notes, fixed = TRUE)
    if (!already_noted) {
      new_notes <- if (is.na(existing_notes) || existing_notes == "") r$notes else paste(existing_notes, r$notes)
      dbExecute(con, "UPDATE Wells SET notes = ? WHERE well_id = ?", params = list(new_notes, well_id))
      notes_appended <- notes_appended + 1L
    }
  }

  message("[sorey1992] Perforation data: ", fields_filled, " field(s) filled, ", notes_appended, " note(s) appended.")
  invisible(list(fields_filled = fields_filled, notes_appended = notes_appended))
}

ingest_historical_sorey1992 <- function(
    con,
    csv_path = "data/raw/historical/sorey1992_table1_chemistry.csv") {

  message("---- Starting Sorey & Colvard (1992) Table 1 chemistry ingest ----")

  if (!file_exists(csv_path)) {
    message("[sorey1992] No file at ", csv_path, " -- skipping.")
    return(invisible(NULL))
  }

  dbExecute(con, "PRAGMA foreign_keys = ON;")

  # ------------------------------------------------------------
  # DATA SOURCE
  # ------------------------------------------------------------
  dbExecute(con, "
    INSERT OR IGNORE INTO Data_Sources (name, notes)
    VALUES (
      'Sorey & Colvard 1992 (USGS Admin Report)',
      'Table 1 chemistry, docs/literature/Sorey_StmbtSprgsHSActivity_1992.pdf; hand-transcribed 2026-09-12.'
    )
  ")
  source_id <- dbGetQuery(con,
    "SELECT source_id FROM Data_Sources WHERE name = 'Sorey & Colvard 1992 (USGS Admin Report)'"
  )$source_id[1]

  # col_types forces sample_date to stay a plain character string --
  # readr::read_csv() otherwise auto-parses an ISO-looking date column
  # into a real Date object, which RSQLite/DBI then silently stores as
  # a numeric day-since-epoch value rather than the intended
  # "YYYY-MM-DD" text -- exactly the same class of bug already flagged
  # project-wide for Sampling_Events.date (see AGENTS.md); caught here
  # by testing against a scratch DB copy before this was ever applied
  # for real.
  rows <- read_csv(csv_path, show_col_types = FALSE,
                    col_types = cols(sample_date = col_character()))

  # ------------------------------------------------------------
  # RESOLVE / CREATE LOCATIONS
  # ------------------------------------------------------------
  locations_created <- 0L
  loc_id_map <- integer(0)

  # Looks up a matched_well_name (or its Well_Aliases entry) and
  # returns its lat/lon if resolved, else NA/NA -- shared by both the
  # new-Locations-row path and the coordinate-backfill path below.
  .lookup_well_coords <- function(matched_well_name) {
    if (is.na(matched_well_name) || matched_well_name == "") {
      return(list(lat = NA_real_, lon = NA_real_))
    }
    well_match <- dbGetQuery(con,
      "SELECT well_id, latitude, longitude FROM Wells WHERE well_name = ?
       UNION
       SELECT w.well_id, w.latitude, w.longitude FROM Well_Aliases a
       JOIN Wells w ON w.well_id = a.well_id WHERE a.alias = ?",
      params = list(matched_well_name, matched_well_name))
    if (nrow(well_match) > 0 && !is.na(well_match$latitude[1])) {
      list(lat = well_match$latitude[1], lon = well_match$longitude[1])
    } else {
      list(lat = NA_real_, lon = NA_real_)
    }
  }

  coords_backfilled <- 0L

  for (i in seq_len(nrow(rows))) {
    r <- rows[i, ]
    existing_loc <- dbGetQuery(con,
      "SELECT location_id, latitude FROM Locations WHERE external_station_code = ?",
      params = list(r$external_location_code))

    if (nrow(existing_loc) > 0) {
      loc_id <- existing_loc$location_id[1]
      # 2026-09-12 (session 28): backfill-only-if-NULL coordinate fix,
      # mirroring register_well_coordinates.R's "never overwrite, only
      # fill a currently-NULL field" idiom -- lets a Locations row
      # created back when a feature (83A-6, Cox 1-1, GS-5/"GS-58"/"GS-59")
      # was still unresolved pick up a real coordinate on a later re-run
      # once data/raw/historical/sorey1992_table1_chemistry.csv and
      # data/raw/wells/sorey1992_nbmg_resolved_wells.csv are updated,
      # without ever clobbering a coordinate a human already confirmed.
      if (is.na(existing_loc$latitude[1])) {
        coords <- .lookup_well_coords(r$matched_well_name)
        if (!is.na(coords$lat)) {
          dbExecute(con, "
            UPDATE Locations SET latitude = ?, longitude = ?, name = ?, site_type = ?,
              coordinate_source = 'copied_from_wells_table',
              notes = notes || ' Identity/coordinate corrected 2026-09-12 once ' || ? || ' was resolved (was previously an OCR-artifact or unresolved name).'
            WHERE location_id = ?",
            params = list(coords$lat, coords$lon, r$location_name,
                          if (r$location_type %in% c("spring", "seep")) r$location_type else "well",
                          r$matched_well_name, loc_id))
          coords_backfilled <- coords_backfilled + 1L
        }
      }
    } else {
      coords <- .lookup_well_coords(r$matched_well_name)
      lat <- coords$lat
      lon <- coords$lon
      coord_source <- if (!is.na(lat)) "copied_from_wells_table" else NA_character_
      site_type <- if (r$location_type %in% c("spring", "seep")) r$location_type else "well"
      dbExecute(con, "
        INSERT INTO Locations
          (external_station_code, name, latitude, longitude, crs, site_type,
           coordinate_source, notes)
        VALUES (?, ?, ?, ?, 'EPSG:4326', ?, ?, ?)
      ", params = list(
        r$external_location_code, r$location_name, lat, lon, site_type,
        coord_source,
        paste0("Sorey & Colvard (1992) Table 1 feature '", r$feature,
               "'. ", r$notes)
      ))
      loc_id <- dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id
      locations_created <- locations_created + 1L
    }
    loc_id_map[i] <- loc_id
  }
  rows$location_id <- loc_id_map

  # ------------------------------------------------------------
  # SAMPLING EVENTS + SAMPLES
  # ------------------------------------------------------------
  events_created <- 0L
  samples_created <- 0L
  sample_id_map <- integer(nrow(rows))

  for (i in seq_len(nrow(rows))) {
    r <- rows[i, ]
    ext_event <- paste0("SOREY1992_", r$external_location_code, "_", r$sample_date)

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
        ext_event, r$sample_date,
        paste0("date_precision='", r$date_precision,
               "' (see data/raw/historical/sorey1992_table1_chemistry.csv)")
      ))
      event_id <- dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id
      events_created <- events_created + 1L
    }

    ext_sample <- paste0("SOREY1992_", r$external_location_code, "_", r$sample_date)
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
        VALUES (?, ?, 'historical', ?, ?, ?, 'Sorey & Colvard 1992', ?)
      ", params = list(
        r$location_id, event_id, r$sample_date, ext_event, ext_sample,
        r$notes
      ))
      sample_id <- dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id
      samples_created <- samples_created + 1L
    }
    sample_id_map[i] <- sample_id
  }
  rows$sample_id <- sample_id_map

  # ------------------------------------------------------------
  # LAB ANALYSES (long format)
  # ------------------------------------------------------------
  analyte_cols <- c(
    TWH_C   = "temperature",
    TDH_C   = "temperature_downhole",
    T_NaKCa_C = "temperature_geothermometer_nakca",
    pH      = "pH",
    SiO2    = "SiO2",
    Na      = "Na",
    K       = "K",
    Ca      = "Ca",
    Mg      = "Mg",
    Li      = "Li",
    HCO3    = "Alkalinity",
    CO3     = "CO3",
    Cl      = "Cl",
    B       = "B",
    F       = "F",
    SO4     = "SO4"
  )
  units_for <- c(
    temperature = "deg C", temperature_downhole = "deg C",
    temperature_geothermometer_nakca = "deg C", pH = "SU",
    SiO2 = "mg/L", Na = "mg/L", K = "mg/L", Ca = "mg/L", Mg = "mg/L",
    Li = "mg/L", Alkalinity = "mg/L", CO3 = "mg/L", Cl = "mg/L",
    B = "mg/L", F = "mg/L", SO4 = "mg/L"
  )

  long_rows <- list()
  for (raw_col in names(analyte_cols)) {
    analyte <- analyte_cols[[raw_col]]
    vals <- rows[[raw_col]]
    keep <- !is.na(vals)
    if (!any(keep)) next
    long_rows[[analyte]] <- data.frame(
      sample_id = rows$sample_id[keep],
      analyte = analyte,
      value = as.numeric(vals[keep]),
      units = units_for[[analyte]],
      fraction = NA_character_,
      method = "Sorey & Colvard (1992) Table 1",
      detection_limit = NA_real_,
      qualifier = NA_character_,
      source_id = source_id,
      stringsAsFactors = FALSE
    )
  }
  lab_new <- bind_rows(long_rows)

  existing_lab <- dbGetQuery(con,
    "SELECT sample_id, analyte, source_id FROM Lab_Analyses")

  lab_new <- lab_new %>%
    anti_join(existing_lab, by = c("sample_id", "analyte", "source_id"))

  if (nrow(lab_new) > 0) {
    dbAppendTable(con, "Lab_Analyses", lab_new)
  }

  message("  -> Locations created: ", locations_created,
          " | Coordinates backfilled: ", coords_backfilled,
          " | Sampling_Events created: ", events_created,
          " | Samples created: ", samples_created,
          " | Lab_Analyses rows inserted: ", nrow(lab_new))
  message("Sorey & Colvard (1992) chemistry ingest complete.")

  invisible(list(
    locations_created = locations_created,
    coords_backfilled = coords_backfilled,
    events_created = events_created,
    samples_created = samples_created,
    lab_rows_inserted = nrow(lab_new)
  ))
}
