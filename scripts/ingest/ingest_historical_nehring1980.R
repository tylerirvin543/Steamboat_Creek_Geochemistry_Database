# ============================================================
# ingest_historical_nehring1980.R
#
# Purpose: ingest Nehring, N.L. (1980), "Geochemistry of Steamboat
# Springs, Nevada" (USGS Open-File Report 80-887) -- Table 7 (p.22),
# real well data (depth, temperature, enthalpy, chloride) reproduced
# from White (1968a). Added 2026-09-26 (real text layer, extracted
# directly via pdftotext, not OCR -- the source has a genuine text
# layer despite being an older USGS open-file report).
#
# A one-time historical snapshot per well (not a time series): each
# well gets exactly one real Sampling_Event/Sample, dated to the
# report's own 1980 publication year (the report gives no more
# precise sample date than that -- stated explicitly, not guessed).
# Only GS-5 matches an existing Wells row; the other 15 names (GS-1
# through GS-4, GS-8, and several genuinely new 1960s-era wells --
# Mt Rose 1, Herz 1/2, E Reno, W Reno, Senges, Rodeo, SB-4, No. 32,
# SSW) register as coordinate-less provisional Wells rows, mirroring
# the established well-log/Skalbeck-Table-3 pattern. "Herz 1"/"Herz 2"
# are explicitly NOT the same as this project's already-known "Herz
# Domestic Well"/"Herz Geothermal" (those are later Ormat-era wells);
# kept as distinct provisional entries, never merged.
# ============================================================

.nehring_resolve_or_create_well <- function(con, well_name, notes) {
  w <- dbGetQuery(con, "SELECT well_id FROM Wells WHERE well_name = ?", params = list(well_name))
  if (nrow(w) > 0) return(w$well_id[1])
  a <- dbGetQuery(con, "SELECT well_id FROM Well_Aliases WHERE alias = ?", params = list(well_name))
  if (nrow(a) > 0) return(a$well_id[1])
  dbExecute(con, "INSERT INTO Wells (well_name, well_role, notes) VALUES (?, 'unknown', ?)",
            params = list(well_name, notes))
  dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id[1]
}

ingest_nehring1980_table7 <- function(
    con, csv_path = "data/raw/historical/nehring1980_table7_well_data.csv") {

  message("---- Ingesting Nehring (1980) Table 7 well data (from White 1968a) ----")
  if (!fs::file_exists(csv_path)) {
    message("  (no file at ", csv_path, ")")
    return(invisible(list(inserted = 0L)))
  }
  rows <- readr::read_csv(csv_path, show_col_types = FALSE)

  source_name <- "Nehring (1980) Table 7"
  dbExecute(con, "INSERT OR IGNORE INTO Data_Sources (name, notes) VALUES (?, ?)",
            params = list(source_name,
              "Well data from White (1968a), reproduced in Nehring (1980) USGS Open-File Report 80-887, Table 7, p.22. One-time 1980-dated snapshot per well, not a time series."))
  source_id <- dbGetQuery(con, "SELECT source_id FROM Data_Sources WHERE name = ?", params = list(source_name))$source_id[1]

  n_new_wells <- 0L; n_inserted <- 0L; n_skipped <- 0L
  for (i in seq_len(nrow(rows))) {
    r <- rows[i, ]
    well_id_before <- dbGetQuery(con, "SELECT well_id FROM Wells WHERE well_name = ?", params = list(r$well_name[1]))
    well_id <- .nehring_resolve_or_create_well(con, r$well_name[1], r$notes[1])
    if (nrow(well_id_before) == 0) n_new_wells <- n_new_wells + 1L

    # Fill Wells.total_depth (feet) only if currently NULL.
    dbExecute(con, "UPDATE Wells SET total_depth = ? WHERE well_id = ? AND total_depth IS NULL",
              params = list(r$depth_ft[1], well_id))

    ext_id <- paste0("NEHRING1980_T7_", gsub("[^A-Za-z0-9]", "", r$well_name[1]))
    existing <- dbGetQuery(con, "SELECT sample_id FROM Samples WHERE external_sample_id = ?", params = list(ext_id))
    if (nrow(existing) > 0) { n_skipped <- n_skipped + 1L; next }

    # Attach the sample to the well's own Locations row if one exists
    # (e.g. GS-5), else fall back to a bare, coordinate-less Locations
    # row for the well name (never fabricates a coordinate).
    loc <- dbGetQuery(con, "SELECT location_id FROM Locations WHERE name = ?", params = list(r$well_name[1]))
    if (nrow(loc) == 0) {
      wloc <- dbGetQuery(con, "SELECT location_id FROM Wells WHERE well_id = ?", params = list(well_id))
      if (nrow(wloc) > 0 && !is.na(wloc$location_id[1])) {
        location_id <- wloc$location_id[1]
      } else {
        dbExecute(con, "INSERT INTO Locations (name, site_type, crs, notes) VALUES (?, 'well', 'EPSG:4326', ?)",
                  params = list(r$well_name[1], "Provisional, no coordinate -- Nehring (1980) Table 7 / White (1968a) gives no location for this well."))
        location_id <- dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id[1]
        dbExecute(con, "UPDATE Wells SET location_id = ? WHERE well_id = ? AND location_id IS NULL", params = list(location_id, well_id))
      }
    } else {
      location_id <- loc$location_id[1]
    }

    dbExecute(con, "INSERT INTO Sampling_Events (external_event_id, date, purpose, notes) VALUES (?, '1980-01-01', 'historical', ?)",
              params = list(ext_id, "Nehring (1980) Table 7 / White (1968a) well data -- no more precise date given in the source."))
    event_id <- dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id[1]

    dbExecute(con, "
      INSERT INTO Samples (location_id, event_id, sample_type, collection_time, external_event_id, external_sample_id, data_source, notes)
      VALUES (?, ?, 'historical', '1980-01-01', ?, ?, ?, ?)
    ", params = list(location_id, event_id, ext_id, ext_id, source_name, r$notes[1]))
    sample_id <- dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id[1]

    cl_val <- if (!is.na(r$cl_corrected_steam_loss[1])) r$cl_corrected_steam_loss[1] else
              if (!is.na(r$cl_erupted[1])) r$cl_erupted[1] else r$cl_nonerupted[1]
    cl_basis <- if (!is.na(r$cl_corrected_steam_loss[1])) "corrected_for_steam_loss" else
                if (!is.na(r$cl_erupted[1])) "erupted" else "non_erupted"
    if (!is.na(cl_val)) {
      dbExecute(con, "INSERT INTO Lab_Analyses (sample_id, analyte, value, units, method, source_id) VALUES (?, 'Cl', ?, 'mg/L', ?, ?)",
                params = list(sample_id, cl_val, paste0(source_name, " (", cl_basis, ")"), source_id))
    }
    if (!is.na(r$temp_c[1])) {
      dbExecute(con, "INSERT INTO Field_Measurements (sample_id, parameter, value, units, instrument) VALUES (?, 'temperature', ?, 'deg C', ?)",
                params = list(sample_id, r$temp_c[1], source_name))
    }
    if (!is.na(r$enthalpy_jg[1])) {
      dbExecute(con, "INSERT INTO Field_Measurements (sample_id, parameter, value, units, instrument) VALUES (?, 'enthalpy', ?, 'J/g', ?)",
                params = list(sample_id, r$enthalpy_jg[1], source_name))
    }
    n_inserted <- n_inserted + 1L
  }
  message("  -> ", n_new_wells, " new provisional well(s), ", n_inserted, " real sample(s) inserted (",
          n_skipped, " already present).")
  invisible(list(new_wells = n_new_wells, inserted = n_inserted, skipped = n_skipped))
}
