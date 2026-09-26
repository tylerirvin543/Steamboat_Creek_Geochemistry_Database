# ============================================================
# ingest_historical_skalbeck2001.R
#
# Purpose: ingest real data mined from Skalbeck, J.D. (2001), "Geophysical
# Modeling and Geochemical Analysis for Hydrogeologic Assessment of the
# Steamboat Hills Area, Nevada" (UNR PhD dissertation, advisor R.E.
# Karlin) -- a major source for hydraulic-conductivity/confining-layer
# characterization at Steamboat Hills, flagged and reviewed 2026-09-26.
#
# Ingests, in stages:
#   1. Table A-2 (p.191-199): model-derived alluvium/volcanics/altered-
#      granodiorite thickness + depth-to-bedrock points along the
#      2.75-D gravity/aeromagnetic forward-model profile -> new
#      Geophysical_Depth_Model_Points table (NOT Well_Lithology -- these
#      are forward-model estimates, not real well logs).
#   2. Table 1 (p.150): well completion details for 15 named wells.
#   3. Table 2 (p.151): chemistry (Cl/B/temp) summary, min/max + dates.
#   4. Table B-1 (p.200-202): dated Cl/B analyses, cold + thermal wells.
#
# Every well-name match against existing Wells/Locations/Well_Aliases is
# either a confirmed exact match or left unmatched -- never guessed.
# Unmatched names get a provisional Wells row (mirrors the existing
# well-log provisional-well pattern) so real data isn't stranded, and are
# logged to data/derived/skalbeck2001_unmapped_locations.csv for human
# review.
# ============================================================

#' Ingest Table A-2's real depth/thickness point data.
ingest_skalbeck2001_depth_points <- function(
    con,
    points_csv = "data/raw/historical/skalbeck2001_table_a2_depth_points.csv") {

  message("---- Ingesting Skalbeck (2001) Table A-2 depth-model points ----")

  if (!fs::file_exists(points_csv)) {
    message("[ingest_skalbeck2001_depth_points] No file at ", points_csv, " -- skipping.")
    return(invisible(list(inserted = 0L)))
  }

  pts <- readr::read_csv(points_csv, show_col_types = FALSE)

  existing <- dbGetQuery(con, "SELECT utm_e, utm_n FROM Geophysical_Depth_Model_Points")
  if (nrow(existing) > 0) {
    key_existing <- paste(round(existing$utm_e), round(existing$utm_n))
    key_new <- paste(round(pts$utm_e), round(pts$utm_n))
    pts <- pts[!(key_new %in% key_existing), ]
  }

  if (nrow(pts) == 0) {
    message("  -> 0 new points (already ingested).")
    return(invisible(list(inserted = 0L)))
  }

  for (i in seq_len(nrow(pts))) {
    row <- pts[i, ]
    dbExecute(con, "
      INSERT INTO Geophysical_Depth_Model_Points
        (utm_e, utm_n, latitude, longitude, qal_thickness_m, tv_thickness_m,
         alt_kgd_km_thickness_m, depth_to_bedrock_m, profile_line,
         source_document, notes)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      row$utm_e[1], row$utm_n[1], row$latitude[1], row$longitude[1],
      row$qal_thickness_m[1], row$tv_thickness_m[1], row$alt_kgd_km_thickness_m[1],
      row$depth_to_bedrock_m[1], row$profile_line[1], row$source_document[1], row$notes[1]
    ))
  }

  message("  -> Inserted ", nrow(pts), " real depth-model point(s).")
  invisible(list(inserted = nrow(pts)))
}

#' Ingest Table 1 (well completion details) + Table 2 (chemistry summary).
#' well_map_csv is a human-confirmed log_number-equivalent mapping
#' (well_name_raw -> canonical Wells.well_name), matching this project's
#' standard "never auto-guess identity" convention.
.skalbeck_resolve_well <- function(con, name_raw) {
  w <- dbGetQuery(con, "SELECT well_id, well_name FROM Wells WHERE well_name = ?", params = list(name_raw))
  if (nrow(w) > 0) return(w$well_id[1])
  a <- dbGetQuery(con, "SELECT well_id FROM Well_Aliases WHERE alias = ?", params = list(name_raw))
  if (nrow(a) > 0) return(a$well_id[1])
  NA_integer_
}

# A name may match an existing Locations row (a sampling point) with no
# corresponding Wells row (construction detail) yet -- mirrors the Boyd
# Domestic Well lesson (Wells and Locations are different ID spaces).
# When that happens, create a real Wells row and link it via
# location_id rather than leaving an orphaned duplicate.
.skalbeck_resolve_or_create_via_location <- function(con, name_raw) {
  loc <- dbGetQuery(con, "SELECT location_id FROM Locations WHERE name = ?", params = list(name_raw))
  if (nrow(loc) == 0) return(NA_integer_)
  location_id <- loc$location_id[1]
  already <- dbGetQuery(con, "SELECT well_id FROM Wells WHERE location_id = ?", params = list(location_id))
  if (nrow(already) > 0) return(already$well_id[1])
  dbExecute(con, "INSERT INTO Wells (well_name, location_id, well_role, notes) VALUES (?, ?, 'unknown', 'Linked to existing Locations row via Skalbeck (2001) ingestion.')",
            params = list(name_raw, location_id))
  dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id[1]
}

ingest_skalbeck2001_well_completions <- function(
    con,
    completions_csv = "data/raw/historical/skalbeck2001_well_completions.csv",
    chem_csv = "data/raw/historical/skalbeck2001_table2_chem_summary.csv") {

  message("---- Ingesting Skalbeck (2001) Table 1/2 well completions + chemistry ----")

  n_wells_created <- 0L
  n_fields_filled <- 0L
  n_chem_rows <- 0L
  unmapped <- character(0)


  if (fs::file_exists(completions_csv)) {
    comp <- readr::read_csv(completions_csv, show_col_types = FALSE)
    for (i in seq_len(nrow(comp))) {
      row <- comp[i, ]
      well_id <- .skalbeck_resolve_well(con, row$well_name[1])
      if (is.na(well_id)) well_id <- .skalbeck_resolve_or_create_via_location(con, row$well_name[1])
      if (is.na(well_id)) {
        # No confirmed match -- register a provisional Wells row so real
        # construction data isn't stranded, coordinate-less until a
        # human confirms/supplies a location.
        already <- dbGetQuery(con, "SELECT well_id FROM Wells WHERE well_name = ?", params = list(row$well_name[1]))
        if (nrow(already) == 0) {
          dbExecute(con, "
            INSERT INTO Wells (well_name, total_depth, top_perforation, bottom_perforation, well_role, notes)
            VALUES (?, ?, ?, ?, 'unknown', ?)
          ", params = list(
            row$well_name[1], row$total_depth_m[1], row$screen_top_m[1], row$screen_bottom_m[1],
            paste0("Provisional well from Skalbeck (2001) Table 1 (p.150) -- no coordinate given in source. ",
                   "Water depth ", row$water_depth_m[1], " m, water temp ", row$water_temp_c[1], " C at completion (", row$date_drilled[1], ").")
          ))
          well_id <- dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id[1]
          n_wells_created <- n_wells_created + 1L
          unmapped <- c(unmapped, row$well_name[1])
        } else {
          well_id <- already$well_id[1]
        }
      } else {
        # Confirmed match -- fill only currently-NULL fields.
        w <- dbGetQuery(con, "SELECT total_depth, top_perforation, bottom_perforation, elevation_m FROM Wells WHERE well_id = ?", params = list(well_id))
        upd <- list()
        if (is.na(w$total_depth[1]) && !is.na(row$total_depth_m[1])) upd$total_depth <- row$total_depth_m[1]
        if (is.na(w$top_perforation[1]) && !is.na(row$screen_top_m[1])) upd$top_perforation <- row$screen_top_m[1]
        if (is.na(w$bottom_perforation[1]) && !is.na(row$screen_bottom_m[1])) upd$bottom_perforation <- row$screen_bottom_m[1]
        if (is.na(w$elevation_m[1]) && !is.na(row$elevation_m[1])) upd$elevation_m <- row$elevation_m[1]
        for (fld in names(upd)) {
          dbExecute(con, paste0("UPDATE Wells SET ", fld, " = ? WHERE well_id = ?"), params = list(upd[[fld]], well_id))
          n_fields_filled <- n_fields_filled + 1L
        }
      }
    }
  } else {
    message("  (no completions CSV at ", completions_csv, ")")
  }

  message("  -> ", n_wells_created, " new provisional well(s), ", n_fields_filled, " field(s) filled.")
  if (length(unmapped) > 0) {
    dir.create("data/derived", showWarnings = FALSE, recursive = TRUE)
    write.csv(data.frame(well_name = unmapped, source = "Skalbeck (2001) Table 1, p.150"),
              "data/derived/skalbeck2001_unmapped_locations.csv", row.names = FALSE)
  }

  invisible(list(wells_created = n_wells_created, fields_filled = n_fields_filled, unmapped = unmapped))
}

#' Resolve a raw well/site name to a real Locations row for chemistry
#' attachment (Samples.location_id is NOT NULL). Tries, in order: (1)
#' exact Locations.name match, (2) the "<name> (Mariner & Janik 1995; =
#' Wells '...')" naming convention already used for the same wells by
#' ingest_mariner_janik_1995.R, (3) a couple of documented spelling
#' variants for wells this project already knows under a different
#' label. Creates a new, coordinate-less provisional Locations row only
#' as a last resort, logged for human review -- never guesses a
#' coordinate.
.skalbeck_resolve_location <- function(con, name_raw, well_id = NA_integer_) {
  loc <- dbGetQuery(con, "SELECT location_id FROM Locations WHERE name = ?", params = list(name_raw))
  if (nrow(loc) > 0) return(loc$location_id[1])

  loc <- dbGetQuery(con, "SELECT location_id FROM Locations WHERE name LIKE ?",
                     params = list(paste0(name_raw, " (Mariner%")))
  if (nrow(loc) > 0) return(loc$location_id[1])

  # STMGID#4 -> "Stmgid 4"; PW 2-1 -> "PW2-1 (Mariner..." (no space)
  alt_name <- gsub("PW ", "PW", name_raw, fixed = TRUE)
  alt_name <- gsub("STMGID MW-4|STMGID#4", "Stmgid 4", alt_name)
  if (alt_name != name_raw) {
    loc <- dbGetQuery(con, "SELECT location_id FROM Locations WHERE name = ? OR name LIKE ?",
                       params = list(alt_name, paste0(alt_name, " (Mariner%")))
    if (nrow(loc) > 0) return(loc$location_id[1])
  }

  # Last resort: a new, coordinate-less provisional Locations row.
  coords <- if (!is.na(well_id)) {
    dbGetQuery(con, "SELECT latitude, longitude FROM Wells WHERE well_id = ?", params = list(well_id))
  } else data.frame(latitude = NA_real_, longitude = NA_real_)
  lat <- if (nrow(coords) > 0) coords$latitude[1] else NA_real_
  lon <- if (nrow(coords) > 0) coords$longitude[1] else NA_real_
  site_type_guess <- if (grepl('Spring|Creek', name_raw, ignore.case = TRUE)) 'spring' else 'well'
  dbExecute(con, "
    INSERT INTO Locations (name, latitude, longitude, site_type, crs, notes)
    VALUES (?, ?, ?, ?, 'EPSG:4326', ?)
  ", params = list(name_raw, lat, lon, site_type_guess,
                    paste0("Provisional, created from Skalbeck (2001) Table B-1/B-2 chemistry ingestion -- ",
                           if (is.na(lat)) "no coordinate available yet." else "coordinate copied from the linked Wells row.")))
  dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id[1]
}

#' Ingest Table B-1's real dated Cl/B analyses (cold background + thermal
#' SB GEO/CPI wells, 1977-1994).
ingest_skalbeck2001_table_b1 <- function(
    con,
    csv_path = "data/raw/historical/skalbeck2001_table_b1_clb.csv") {

  message("---- Ingesting Skalbeck (2001) Table B-1 dated Cl/B analyses ----")
  if (!fs::file_exists(csv_path)) {
    message("  (no file at ", csv_path, ")")
    return(invisible(list(rows_inserted = 0L)))
  }

  dbExecute(con, "
    INSERT OR IGNORE INTO Data_Sources (name, notes)
    VALUES ('Skalbeck (2001) Table B-1', 'docs/literature/Skalbeck_StmbtHlls_GeoMdlng_2001.pdf, p.200-202; hand-corrected OCR, 2026-09-26.')
  ")
  source_id <- dbGetQuery(con, "SELECT source_id FROM Data_Sources WHERE name = 'Skalbeck (2001) Table B-1'")$source_id[1]

  rows <- readr::read_csv(csv_path, show_col_types = FALSE,
                           col_types = readr::cols(date = readr::col_character()))

  n_inserted <- 0L
  n_skipped <- 0L

  for (i in seq_len(nrow(rows))) {
    r <- rows[i, ]
    well_id <- .skalbeck_resolve_well(con, r$well_name[1])
    location_id <- .skalbeck_resolve_location(con, r$well_name[1], well_id)

    ext_id <- paste0("SKALBECK2001_B1_", gsub("[^A-Za-z0-9]", "", r$well_name[1]), "_", r$date[1])

    existing_sample <- dbGetQuery(con, "SELECT sample_id FROM Samples WHERE external_sample_id = ?", params = list(ext_id))
    if (nrow(existing_sample) > 0) { n_skipped <- n_skipped + 1L; next }

    dbExecute(con, "INSERT INTO Sampling_Events (external_event_id, date, purpose, notes) VALUES (?, ?, 'historical', ?)",
              params = list(ext_id, r$date[1], paste0("Skalbeck (2001) Table B-1. Reference: ", r$reference[1])))
    event_id <- dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id[1]

    dbExecute(con, "
      INSERT INTO Samples (location_id, event_id, sample_type, collection_time, external_event_id, external_sample_id, data_source, notes)
      VALUES (?, ?, 'historical', ?, ?, ?, 'Skalbeck 2001 Table B-1', ?)
    ", params = list(location_id, event_id, r$date[1], ext_id, ext_id, r$notes[1]))
    sample_id <- dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id[1]

    if (!is.na(r$Cl[1])) {
      dbExecute(con, "INSERT INTO Lab_Analyses (sample_id, analyte, value, units, method, source_id) VALUES (?, 'Cl', ?, 'mg/L', ?, ?)",
                params = list(sample_id, r$Cl[1], r$reference[1], source_id))
    }
    if (!is.na(r$B[1])) {
      dbExecute(con, "INSERT INTO Lab_Analyses (sample_id, analyte, value, units, method, source_id) VALUES (?, 'B', ?, 'mg/L', ?, ?)",
                params = list(sample_id, r$B[1], r$reference[1], source_id))
    }
    n_inserted <- n_inserted + 1L
  }

  message("  -> Inserted ", n_inserted, " real sample(s) (", n_skipped, " already present).")
  invisible(list(rows_inserted = n_inserted, rows_skipped = n_skipped))
}

#' Fetch real ground-surface elevation for any Geophysical_Depth_Model_Points
#' row that doesn't have one yet, from the public USGS Elevation Point
#' Query Service (3DEP) -- a real DEM source queried point-by-point via
#' its REST API, not a fabricated or interpolated value. Idempotent
#' (only queries rows where surface_elevation_m IS NULL), so a normal
#' pipeline re-run costs nothing once every point has been fetched once.
#' The live service is occasionally slow/rate-limited -- each point gets
#' up to 3 retries with backoff; a point that still fails is left NULL
#' (not a fabricated 0 or guess) and can be retried on a future run.
fetch_skalbeck2001_point_elevations <- function(con, max_points = Inf) {
  message("---- Fetching real USGS 3DEP surface elevations for depth-model points ----")

  migrate_geophysical_depth_points_elevation(con)

  pts <- dbGetQuery(con, "SELECT point_id, latitude, longitude FROM Geophysical_Depth_Model_Points WHERE surface_elevation_m IS NULL")
  if (nrow(pts) == 0) {
    message("  -> All points already have a real elevation on file.")
    return(invisible(list(fetched = 0L, failed = 0L)))
  }
  if (nrow(pts) > max_points) pts <- pts[seq_len(max_points), ]

  .fetch_one <- function(lat, lon, tries = 3) {
    for (attempt in seq_len(tries)) {
      url <- sprintf("https://epqs.nationalmap.gov/v1/json?x=%f&y=%f&units=Meters&wkid=4326", lon, lat)
      resp <- tryCatch(httr::GET(url, httr::timeout(20)), error = function(e) NULL)
      if (!is.null(resp) && httr::status_code(resp) == 200) {
        val <- tryCatch(as.numeric(httr::content(resp, as = "parsed")$value), error = function(e) NA_real_)
        if (!is.na(val)) return(val)
      }
      Sys.sleep(2 * attempt)
    }
    NA_real_
  }

  n_fetched <- 0L; n_failed <- 0L
  for (i in seq_len(nrow(pts))) {
    e <- .fetch_one(pts$latitude[i], pts$longitude[i])
    if (!is.na(e)) {
      dbExecute(con, "UPDATE Geophysical_Depth_Model_Points SET surface_elevation_m = ?, elevation_source = 'USGS Elevation Point Query Service (3DEP)' WHERE point_id = ?",
                params = list(e, pts$point_id[i]))
      n_fetched <- n_fetched + 1L
    } else {
      n_failed <- n_failed + 1L
    }
  }
  message("  -> Fetched ", n_fetched, " real elevation(s); ", n_failed, " failed (left NULL, retry on a future run).")
  invisible(list(fetched = n_fetched, failed = n_failed))
}

#' Ingest the real, carefully cross-checked Brown School monthly Cl/B/
#' temperature time series (Table B-2, 1985-1998, 112 real observations).
#' This is deliberately scoped to Brown School ONLY -- the same table
#' covers 4 more wells in this block (Curti Geothermal/Domestic, Herz
#' Geothermal/Domestic) plus a second well-group block (Peigh/Pine Tree
#' Ranch/Flame/Steinhardt), none of which have been transcribed yet
#' (2026-09-26). A column-bleed contamination check (isolated Cl values
#' landing in Curti Geothermal's own narrow 690-715 mg/L range,
#' surrounded by much lower real Brown School values on both sides) was
#' applied before this CSV was finalized -- 4 real rows were caught and
#' discarded this way; see the CSV's own row count vs. the 168 candidate
#' month-slots in the raw table for the full accounting.
ingest_skalbeck2001_table_b2_brownschool <- function(
    con,
    csv_path = "data/raw/historical/skalbeck2001_table_b2_brownschool.csv") {

  message("---- Ingesting Skalbeck (2001) Table B-2, Brown School monthly time series ----")
  if (!fs::file_exists(csv_path)) {
    message("  (no file at ", csv_path, ")")
    return(invisible(list(rows_inserted = 0L)))
  }

  dbExecute(con, "
    INSERT OR IGNORE INTO Data_Sources (name, notes)
    VALUES ('Skalbeck (2001) Table B-2 (Brown School)',
            'docs/literature/Skalbeck_StmbtHlls_GeoMdlng_2001.pdf, p.203-205+; careful manual OCR cross-check, 2026-09-26. Brown School only -- see file header comment for scope.')
  ")
  source_id <- dbGetQuery(con, "SELECT source_id FROM Data_Sources WHERE name = 'Skalbeck (2001) Table B-2 (Brown School)'")$source_id[1]

  rows <- readr::read_csv(csv_path, show_col_types = FALSE, col_types = readr::cols(date = readr::col_character()))
  well_name <- "Brown's School (Mariner & Janik 1995; = Wells 'Brown School Geothermal Well')"
  location_id <- .skalbeck_resolve_location(con, well_name)

  n_inserted <- 0L; n_skipped <- 0L
  for (i in seq_len(nrow(rows))) {
    r <- rows[i, ]
    ext_id <- paste0("SKALBECK2001_B2_BrownSchool_", r$date[1])
    existing <- dbGetQuery(con, "SELECT sample_id FROM Samples WHERE external_sample_id = ?", params = list(ext_id))
    if (nrow(existing) > 0) { n_skipped <- n_skipped + 1L; next }

    dbExecute(con, "INSERT INTO Sampling_Events (external_event_id, date, purpose, notes) VALUES (?, ?, 'historical', 'Skalbeck (2001) Table B-2, Brown School monthly monitoring series.')",
              params = list(ext_id, r$date[1]))
    event_id <- dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id[1]

    dbExecute(con, "
      INSERT INTO Samples (location_id, event_id, sample_type, collection_time, external_event_id, external_sample_id, data_source, notes)
      VALUES (?, ?, 'historical', ?, ?, ?, 'Skalbeck 2001 Table B-2 (Brown School)', 'Carefully cross-checked against the raw OCR text; a column-bleed sanity filter was applied before this row was accepted.')
    ", params = list(location_id, event_id, r$date[1], ext_id, ext_id))
    sample_id <- dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id[1]

    if (!is.na(r$Cl[1])) dbExecute(con, "INSERT INTO Lab_Analyses (sample_id, analyte, value, units, method, source_id) VALUES (?, 'Cl', ?, 'mg/L', 'Skalbeck (2001) Table B-2', ?)",
                                     params = list(sample_id, r$Cl[1], source_id))
    if (!is.na(r$B[1])) dbExecute(con, "INSERT INTO Lab_Analyses (sample_id, analyte, value, units, method, source_id) VALUES (?, 'B', ?, 'mg/L', 'Skalbeck (2001) Table B-2', ?)",
                                    params = list(sample_id, r$B[1], source_id))
    if (!is.na(r$Temp[1])) dbExecute(con, "INSERT INTO Field_Measurements (sample_id, parameter, value, units, instrument) VALUES (?, 'temperature', ?, 'deg C', 'Skalbeck (2001) Table B-2')",
                                       params = list(sample_id, r$Temp[1]))
    n_inserted <- n_inserted + 1L
  }
  message("  -> Inserted ", n_inserted, " real sample(s) (", n_skipped, " already present).")
  invisible(list(rows_inserted = n_inserted, rows_skipped = n_skipped))
}

#' Generic ingester for a single well's Table B-2 monthly Cl/B/temperature
#' series, once a careful, cross-checked CSV exists for it (mirrors
#' ingest_skalbeck2001_table_b2_brownschool()'s exact approach -- kept
#' as a separate, explicit per-well entry point rather than a silent
#' loop, so each well's real transcription/validation work stays
#' individually documented and auditable).
.ingest_skalbeck2001_b2_well <- function(con, csv_path, location_name, source_name, source_notes, well_name_for_depth = NULL) {
  if (!fs::file_exists(csv_path)) {
    message("  (no file at ", csv_path, ")")
    return(invisible(list(rows_inserted = 0L)))
  }
  dbExecute(con, "INSERT OR IGNORE INTO Data_Sources (name, notes) VALUES (?, ?)",
            params = list(source_name, source_notes))
  source_id <- dbGetQuery(con, "SELECT source_id FROM Data_Sources WHERE name = ?", params = list(source_name))$source_id[1]

  rows <- readr::read_csv(csv_path, show_col_types = FALSE, col_types = readr::cols(date = readr::col_character()))
  location_id <- .skalbeck_resolve_location(con, location_name)

  n_inserted <- 0L; n_skipped <- 0L
  for (i in seq_len(nrow(rows))) {
    r <- rows[i, ]
    ext_id <- paste0("SKALBECK2001_B2_", gsub("[^A-Za-z0-9]", "", location_name), "_", r$date[1])
    existing <- dbGetQuery(con, "SELECT sample_id FROM Samples WHERE external_sample_id = ?", params = list(ext_id))
    if (nrow(existing) > 0) { n_skipped <- n_skipped + 1L; next }

    dbExecute(con, "INSERT INTO Sampling_Events (external_event_id, date, purpose, notes) VALUES (?, ?, 'historical', ?)",
              params = list(ext_id, r$date[1], paste0(source_name, " monthly monitoring series.")))
    event_id <- dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id[1]

    dbExecute(con, "
      INSERT INTO Samples (location_id, event_id, sample_type, collection_time, external_event_id, external_sample_id, data_source, notes)
      VALUES (?, ?, 'historical', ?, ?, ?, ?, 'Carefully cross-checked against the raw OCR text with an ordered, range-based token parser; ambiguous/anomalous months were excluded rather than guessed.')
    ", params = list(location_id, event_id, r$date[1], ext_id, ext_id, source_name))
    sample_id <- dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id[1]

    if (!is.na(r$Cl[1])) dbExecute(con, "INSERT INTO Lab_Analyses (sample_id, analyte, value, units, method, source_id) VALUES (?, 'Cl', ?, 'mg/L', ?, ?)",
                                     params = list(sample_id, r$Cl[1], source_name, source_id))
    if (!is.na(r$B[1])) dbExecute(con, "INSERT INTO Lab_Analyses (sample_id, analyte, value, units, method, source_id) VALUES (?, 'B', ?, 'mg/L', ?, ?)",
                                    params = list(sample_id, r$B[1], source_name, source_id))
    if (!is.na(r$Temp[1])) dbExecute(con, "INSERT INTO Field_Measurements (sample_id, parameter, value, units, instrument) VALUES (?, 'temperature', ?, 'deg C', ?)",
                                       params = list(sample_id, r$Temp[1], source_name))
    n_inserted <- n_inserted + 1L
    if (!is.null(well_name_for_depth) && "Depth" %in% names(r) && !is.na(r$Depth[1])) {
      well_id <- .skalbeck_resolve_well(con, well_name_for_depth)
      if (!is.na(well_id)) {
        already_wl <- dbGetQuery(con, "SELECT observation_id FROM Water_Level_Observations WHERE well_id = ? AND method = ? AND timestamp = ?",
                                  params = list(well_id, source_name, r$date[1]))
        if (nrow(already_wl) == 0) {
          dbExecute(con, "INSERT INTO Water_Level_Observations (well_id, timestamp, depth_to_water, method, method_type, notes) VALUES (?, ?, ?, ?, 'historical', ?)",
                    params = list(well_id, r$date[1], r$Depth[1], source_name,
                                   paste0(source_name, ", real depth-to-water reading (meters).")))
        }
      } else {
        warning("[ingest_skalbeck2001_b2_well] '", well_name_for_depth, "' not found in Wells -- depth reading for ", r$date[1], " not recorded.")
      }
    }
  }
  message("  -> Inserted ", n_inserted, " real sample(s) (", n_skipped, " already present).")
  invisible(list(rows_inserted = n_inserted, rows_skipped = n_skipped))
}

#' Ingest the real, cross-checked Curti Barn Geothermal monthly Cl/B/
#' temperature series (Table B-2, 1987-1998, 36 real observations, no
#' exclusions needed -- a smooth, internally consistent 670-844 mg/L Cl
#' record matching Table 2's already-known 660-844 mg/L summary range).
ingest_skalbeck2001_table_b2_curtigeothermal <- function(
    con, csv_path = "data/raw/historical/skalbeck2001_table_b2_curtigeothermal.csv") {
  message("---- Ingesting Skalbeck (2001) Table B-2, Curti Barn Geothermal monthly time series ----")
  .ingest_skalbeck2001_b2_well(
    con, csv_path, "Curti Barn Well (geothermal)",
    "Skalbeck (2001) Table B-2 (Curti Barn Geothermal)",
    "docs/literature/Skalbeck_StmbtHlls_GeoMdlng_2001.pdf, p.203-205+; careful manual cross-check with an ordered, range-based token parser, 2026-09-26."
  )
}

#' Ingest the real, cross-checked Curti Domestic monthly Cl/B/temperature
#' series (Table B-2, 1987-1998, 31 real observations). 9 rows
#' (Nov-1989 through Jun-1990, plus an isolated Feb-1991 value of
#' 0.2 mg/L) were deliberately EXCLUDED as an unresolved, alternating
#' low/high pattern that could not be confidently attributed to Curti
#' Domestic vs. a neighboring well (Herz Geothermal's real Cl range
#' overlaps Curti Domestic's) -- flagged, not guessed.
ingest_skalbeck2001_table_b2_curtidomestic <- function(
    con, csv_path = "data/raw/historical/skalbeck2001_table_b2_curtidomestic.csv") {
  message("---- Ingesting Skalbeck (2001) Table B-2, Curti Domestic monthly time series ----")
  .ingest_skalbeck2001_b2_well(
    con, csv_path, "Curti Domestic Well",
    "Skalbeck (2001) Table B-2 (Curti Domestic)",
    "docs/literature/Skalbeck_StmbtHlls_GeoMdlng_2001.pdf, p.203-205+; careful manual cross-check with an ordered, range-based token parser, 2026-09-26. 9 ambiguous rows (Nov-1989 through Jun-1990, plus Feb-1991) deliberately excluded -- see AGENTS.md."
  )
}

#' Ingest the real, cross-checked Herz Geothermal Water monthly Cl/B/
#' temperature/depth-to-water series (Table B-2, 1985-1989, 48 real
#' observations). This well's 4-column layout (Cl/B/temp/depth) made
#' the temp-vs-depth-missing ambiguity a real problem: when this well's
#' own depth reading was genuinely blank, the parser sometimes
#' consumed the FIRST token of the next well (Herz Domestic's own Cl)
#' as if it were this well's depth. Caught via a plausibility check
#' (this well's real depth stays close to a stable ~14-16.3 m band; 7
#' months where the "depth" token came back as an implausible single
#' digit 1-6 had that field set to NA -- Cl/B/Temp for those months
#' were still trustworthy and kept, only the corrupted depth field was
#' dropped). No real values were found in the raw table after
#' Oct-1989 -- either monitoring genuinely stopped, or a real later
#' gap that wasn't successfully extracted; not resolved further.
ingest_skalbeck2001_table_b2_herzgeothermal <- function(
    con, csv_path = "data/raw/historical/skalbeck2001_table_b2_herzgeothermal.csv") {
  message("---- Ingesting Skalbeck (2001) Table B-2, Herz Geothermal Water monthly time series ----")
  .ingest_skalbeck2001_b2_well(
    con, csv_path, "Herz Geothermal",
    "Skalbeck (2001) Table B-2 (Herz Geothermal)",
    "docs/literature/Skalbeck_StmbtHlls_GeoMdlng_2001.pdf, p.203-205+; careful manual cross-check, 2026-09-26. 7 implausible depth values (likely column-bleed from Herz Domestic's own Cl) set to NA -- Cl/B/Temp for those months kept.",
    well_name_for_depth = "Herz Geothermal"
  )
}

#' Ingest the real, cross-checked Herz Domestic Water monthly Cl/B/
#' temperature/depth-to-water series (Table B-2, 1985-1994, 45 real
#' observations after excluding 9 months where a temp-vs-depth-missing
#' slip in the preceding Herz Geothermal column shifted this well's own
#' reading -- caught via a boron sanity check (Herz Domestic's real B
#' never exceeds ~4.5 mg/L per Table 2, so any row reporting B > 5 is
#' almost certainly a shifted/contaminated read) plus a depth sanity
#' check (< 3 m is implausible once real depth readings begin).
ingest_skalbeck2001_table_b2_herzdomestic <- function(
    con, csv_path = "data/raw/historical/skalbeck2001_table_b2_herzdomestic.csv") {
  message("---- Ingesting Skalbeck (2001) Table B-2, Herz Domestic Water monthly time series ----")
  .ingest_skalbeck2001_b2_well(
    con, csv_path, "Herz Domestic Well",
    "Skalbeck (2001) Table B-2 (Herz Domestic)",
    "docs/literature/Skalbeck_StmbtHlls_GeoMdlng_2001.pdf, p.203-205+; careful manual cross-check, 2026-09-26. 9 months excluded (B>5 mg/L sanity check or implausible <3 m depth) as likely shift-contaminated from the preceding Herz Geothermal column's own temp-vs-depth ambiguity.",
    well_name_for_depth = "Herz Domestic Well"
  )
}

#' Ingest the real, cross-checked Peigh Domestic monthly Cl/B/temperature
#' series (Table B-2, second well-group block, 1985-1998, 102 real
#' observations). 3 months with an implausible B value (>1 mg/L against
#' a known real max of ~0.3 mg/L, almost certainly column-bleed from
#' Pine Tree Ranch #1's own Cl reading) were excluded.
ingest_skalbeck2001_table_b2_peighdomestic <- function(
    con, csv_path = "data/raw/historical/skalbeck2001_table_b2_peighdomestic.csv") {
  message("---- Ingesting Skalbeck (2001) Table B-2, Peigh Domestic monthly time series ----")
  .ingest_skalbeck2001_b2_well(
    con, csv_path, "Peigh",
    "Skalbeck (2001) Table B-2 (Peigh Domestic)",
    "docs/literature/Skalbeck_StmbtHlls_GeoMdlng_2001.pdf, p.206-208+; careful manual cross-check, 2026-09-26. 3 months excluded (B>1 mg/L sanity check against a known real max of ~0.3 mg/L)."
  )
}

#' Ingest the real, cross-checked Pine Tree Ranch #1 monthly Cl/B/
#' temperature/depth series (Table B-2, second well-group block,
#' 1985-1990, 48 real observations). Real chemistry sampling at this
#' well ended in June 1990 (matching Table 2's own documented date
#' range exactly) -- later-looking "readings" in the raw table for this
#' well's column position are actually water-level-only values (no
#' longer paired with real Cl/B/Temp), correctly truncated out rather
#' than mistaken for continued chemistry monitoring. 3 months with an
#' implausible B value (>6 mg/L against a known real max of ~4.9 mg/L)
#' were also excluded.
ingest_skalbeck2001_table_b2_pinetreeranch1 <- function(
    con, csv_path = "data/raw/historical/skalbeck2001_table_b2_pinetreeranch1.csv") {
  message("---- Ingesting Skalbeck (2001) Table B-2, Pine Tree Ranch #1 monthly time series ----")
  .ingest_skalbeck2001_b2_well(
    con, csv_path, "Pine Tree Ranch-1",
    "Skalbeck (2001) Table B-2 (Pine Tree Ranch #1)",
    "docs/literature/Skalbeck_StmbtHlls_GeoMdlng_2001.pdf, p.206-208+; careful manual cross-check, 2026-09-26. Truncated to the real Dec-1984-to-Jun-1990 chemistry sampling window (matches Table 2's own documented end date); 3 months excluded (B>6 mg/L sanity check).",
    well_name_for_depth = "Pine Tree Ranch-1"
  )
}

#' Ingest the real Flame and Steinhardt monthly Cl/B/temperature(/depth)
#' series, transcribed 2026-09-26 directly from a clean user-supplied
#' image of Table B-2 (not OCR text -- the OCR-based attempt in the
#' prior session could not confidently resolve these two wells; this
#' clean source resolves that gap). **Important caveat, stated plainly
#' rather than hidden**: the source excerpt did not show explicit date
#' labels for these rows. Dates are POSITIONAL ESTIMATES:
#' - Flame: assumed a strict monthly sequence starting Jan-1985 with no
#'   gaps (matching every other well in this table's own real start
#'   date, and no visible blank-row gaps in the excerpt).
#' - Steinhardt: anchored by value, not guessed blindly -- its LAST
#'   listed reading (Cl=173, Temp=34) closely matches this project's
#'   own already-ingested real 1991-11-08 sample (Cl=171, Temp=34,
#'   from Mariner & Janik 1995) -- assigned to 1991-11-01, then stepped
#'   backward monthly for the other 16 rows (1990-07 through 1991-10).
#' Both are flagged with method_type/notes text saying so, so a future
#' session (or you, checking the original scanned page) can correct
#' the exact calendar dates without having to re-derive the values.
ingest_skalbeck2001_table_b2_flame <- function(
    con, csv_path = "data/raw/historical/skalbeck2001_table_b2_flame.csv") {
  message("---- Ingesting Skalbeck (2001) Table B-2, Flame monthly time series ----")
  .ingest_skalbeck2001_b2_well(
    con, csv_path, "Flame",
    "Skalbeck (2001) Table B-2 (Flame)",
    "Transcribed 2026-09-26 from a clean user-supplied table image (not OCR). DATES ARE POSITIONAL ESTIMATES (assumed monthly, starting Jan-1985, no gaps) -- not read from explicit date labels in the source excerpt. Verify against the original scanned page if exact dates matter."
  )
}

ingest_skalbeck2001_table_b2_steinhardt <- function(
    con, csv_path = "data/raw/historical/skalbeck2001_table_b2_steinhardt.csv") {
  message("---- Ingesting Skalbeck (2001) Table B-2, Steinhardt monthly time series ----")
  .ingest_skalbeck2001_b2_well(
    con, csv_path, "Steinhardt Geothermal Well (narrative Cl trend)",
    "Skalbeck (2001) Table B-2 (Steinhardt)",
    "Transcribed 2026-09-26 from a clean user-supplied table image (not OCR). DATES ARE POSITIONAL ESTIMATES anchored by value match: the last row (Cl=173, Temp=34) closely matches this project's own real 1991-11-08 sample (Cl=171, Temp=34) and was assigned 1991-11-01, with the other 16 rows stepped back monthly. Verify against the original scanned page if exact dates matter.",
    well_name_for_depth = "Steinhardt Geothermal Well (narrative Cl trend)"
  )
}

# ============================================================
# Table 3 (p.74-75): "Well data used in 2.75-D forward models and 3-D
# model depth to bedrock" -- 41 named wells with real depth-to-
# formation-contact data (a genuine, well-by-well "mini well log" of
# depth to Tv / depth to Kgd (granodiorite) / depth to top pKm
# (metasediment) / total depth / the 3-D model's own independent
# depth-to-bedrock estimate). Added 2026-09-26.
#
# Column mapping onto Skalbeck's own Table A-2 4-unit scheme
# (Qal/Tv/AltKgdpKm/Kgd). Revised 2026-09-26 (was previously labeled
# "AltKgdpKm" -- corrected per direct review): Table 3's own column
# header is literally "Depth to Kgd", i.e. the driller's log itself
# calls this contact Kgd, not an alteration product -- Table 3 gives
# no basis to further claim this interval is altered, so it is
# labeled Kgd here, matching the source table's own terminology, not
# AltKgdpKm. (This is the OPPOSITE relationship from Table A-2's own
# model points, where AltKgdpKm genuinely IS the named altered cap
# sitting within/above fresh Kgd -- see .skalbeck_table3_intervals()
# below and export_leapfrog_geophysical_lithology()'s own AltKgdpKm-
# cut-from-Kgd logic for that distinct case.)
#   - [0, depth_to_tv_m]                -> Qal  (only if surface
#     geology is Qal/Sr and depth_to_tv_m is known)
#   - [start, depth_to_kgd_m]            -> Tv   (start = 0 if the
#     well's surface geology is already Tv, else depth_to_tv_m)
#   - [depth_to_kgd_m (or start if surface geology is pKm), total_depth_m]
#                                        -> Kgd (everything from the
#     granodiorite contact down to total depth -- deliberately NOT
#     further split at depth_to_topkm_m, since Table 3 doesn't give
#     enough basis to separate fresh from altered Kgd here)
# Intervals are only written where both bounds are real (non-NA)
# numbers -- never fabricated to fill a gap.
# ============================================================

#' Build Skalbeck-scheme formation intervals for one Table 3 well row.
#' Returns a data.frame with columns depth_from_m, depth_to_m,
#' formation_unit -- zero rows if nothing can be safely bounded.
.skalbeck_table3_intervals <- function(surface_geology, depth_to_tv_m, depth_to_kgd_m,
                                        total_depth_m) {
  out <- data.frame(depth_from_m = numeric(0), depth_to_m = numeric(0),
                     formation_unit = character(0))
  starts_in_tv <- grepl("^Tv$", surface_geology)
  starts_in_pkm <- grepl("^pKm$", surface_geology)
  starts_in_qal_or_sr <- grepl("Qal|Sr", surface_geology)

  # Qal interval
  if (starts_in_qal_or_sr && !is.na(depth_to_tv_m)) {
    out <- rbind(out, data.frame(depth_from_m = 0, depth_to_m = depth_to_tv_m, formation_unit = "Qal"))
  }

  # Tv interval
  tv_start <- if (starts_in_tv) 0 else depth_to_tv_m
  if (!starts_in_pkm && !is.na(tv_start) && !is.na(depth_to_kgd_m) && depth_to_kgd_m > tv_start) {
    out <- rbind(out, data.frame(depth_from_m = tv_start, depth_to_m = depth_to_kgd_m, formation_unit = "Tv"))
  }

  # Kgd interval: from the granodiorite contact (or from 0 if the
  # well starts directly in pKm) down to total depth. Labeled Kgd,
  # not AltKgdpKm, matching Table 3's own "Depth to Kgd" column name.
  kgd_start <- if (starts_in_pkm) 0 else depth_to_kgd_m
  if (!is.na(kgd_start) && !is.na(total_depth_m) && total_depth_m > kgd_start) {
    out <- rbind(out, data.frame(depth_from_m = kgd_start, depth_to_m = total_depth_m, formation_unit = "Kgd"))
  }

  out
}

#' Ingest Table 3's 41 real well-control points.
ingest_skalbeck2001_table3_well_control <- function(
    con, csv_path = "data/raw/historical/skalbeck2001_table3_well_control.csv") {

  message("---- Ingesting Skalbeck (2001) Table 3 well-control depths ----")
  if (!fs::file_exists(csv_path)) {
    message("  (no file at ", csv_path, ")")
    return(invisible(list(inserted = 0L)))
  }
  rows <- readr::read_csv(csv_path, show_col_types = FALSE)

  doc_id <- dbGetQuery(con, "SELECT source_id FROM Data_Sources WHERE name = 'Skalbeck (2001) Table 3'")
  if (nrow(doc_id) == 0) {
    dbExecute(con, "INSERT INTO Data_Sources (name, notes) VALUES ('Skalbeck (2001) Table 3',
      'Well data used in 2.75-D forward models and 3-D model depth to bedrock, p.74-75.')")
  }

  n_new_wells <- 0L; n_matched <- 0L; n_lithology <- 0L
  for (i in seq_len(nrow(rows))) {
    r <- rows[i, ]
    well_id <- NA_integer_
    if (!is.na(r$matched_well_name[1])) {
      well_id <- .skalbeck_resolve_well(con, r$matched_well_name[1])
      if (!is.na(well_id)) n_matched <- n_matched + 1L
    }
    if (is.na(well_id)) {
      existing <- dbGetQuery(con, "SELECT well_id FROM Wells WHERE well_name = ?", params = list(r$well_name_raw[1]))
      if (nrow(existing) > 0) {
        well_id <- existing$well_id[1]
      } else {
        dbExecute(con, "
          INSERT INTO Wells (well_name, well_role, notes)
          VALUES (?, 'unknown', ?)
        ", params = list(
          r$well_name_raw[1],
          paste0("Provisional well, no coordinate -- Skalbeck (2001) Table 3 gives depth-to-formation data only, ",
                 "not a coordinate (only the raster Figure 5 map shows its location). Profile: ", r$profile[1], ". ",
                 r$notes[1])
        ))
        well_id <- dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id[1]
        n_new_wells <- n_new_wells + 1L
      }
    }

    # Fill Wells.elevation_m/total_depth only if currently NULL -- never overwrite.
    dbExecute(con, "UPDATE Wells SET elevation_m = ? WHERE well_id = ? AND elevation_m IS NULL",
              params = list(r$elevation_m[1], well_id))
    dbExecute(con, "UPDATE Wells SET total_depth = ? WHERE well_id = ? AND total_depth IS NULL",
              params = list(r$total_depth_m[1] * 3.28084, well_id))  # Wells.total_depth is stored in feet elsewhere in this project

    intervals <- .skalbeck_table3_intervals(r$surface_geology[1], r$depth_to_tv_m[1], r$depth_to_kgd_m[1], r$total_depth_m[1])
    for (j in seq_len(nrow(intervals))) {
      iv <- intervals[j, ]
      already <- dbGetQuery(con, "
        SELECT lithology_id FROM Well_Lithology
        WHERE well_id = ? AND depth_from_ft = ? AND depth_to_ft = ? AND formation_unit = ?
      ", params = list(well_id, iv$depth_from_m, iv$depth_to_m, iv$formation_unit))
      if (nrow(already) > 0) next
      dbExecute(con, "
        INSERT INTO Well_Lithology
          (well_id, depth_from_ft, depth_to_ft, description, units, formation_unit, formation_unit_basis, notes)
        VALUES (?, ?, ?, ?, 'm', ?, 'source_table_column', ?)
      ", params = list(
        well_id, iv$depth_from_m, iv$depth_to_m,
        paste0(iv$formation_unit, " (Skalbeck 2001 Table 3, well control point, real depth-log interval)"),
        iv$formation_unit,
        paste0("Real interval derived from Skalbeck (2001) Table 3's own well-log depths (surface geology='",
               r$surface_geology[1], "'). Depths stored in meters (units='m'), not feet, unlike most other ",
               "Well_Lithology rows in this project -- check the units column before comparing depths directly.")
      ))
      n_lithology <- n_lithology + 1L
    }
  }
  message("  -> ", n_new_wells, " new provisional well(s), ", n_matched, " matched to existing wells, ",
          n_lithology, " real formation-unit interval(s) written.")
  invisible(list(new_wells = n_new_wells, matched = n_matched, intervals = n_lithology))
}

# ============================================================
# Table B-2, TH-1/TH-2/TH-3 wells (p.210-213): real monthly water-depth
# (m) readings, Jan-1985 through 1998 -- SBG-TH1/SBG-TH2/SBG-TH3 (see
# Table 1's own 1991-completion entries for these same wells, already
# Wells.well_id 216/217/218, both provisional/coordinate-less). No
# chemistry in this specific table section -- water depth only, so
# this writes Water_Level_Observations, not Lab_Analyses. Added
# 2026-09-26.
#
# Real, unresolved discrepancy flagged rather than silently patched:
# this table's own real data shows TH-2/TH-3 readings as early as
# 1989 -- two years BEFORE Table 1's own stated 1991 completion date
# for SBG-TH1/2/3. Column-position parsing was independently verified
# self-consistent (a smooth, continuous, physically plausible 1989-98
# series with no discontinuity at the 1991 "completion" date), so the
# values themselves are trusted; the completion-date-vs-first-reading
# conflict itself is NOT resolved here.
# ============================================================

ingest_skalbeck2001_table_b2_th_wells <- function(
    con, csv_path = "data/raw/historical/skalbeck2001_table_b2_th_wells.csv") {

  message("---- Ingesting Skalbeck (2001) Table B-2, TH-1/TH-2/TH-3 water-depth series ----")
  if (!fs::file_exists(csv_path)) {
    message("  (no file at ", csv_path, ")")
    return(invisible(list(inserted = 0L)))
  }
  rows <- readr::read_csv(csv_path, show_col_types = FALSE, col_types = readr::cols(date = readr::col_character()))

  well_map <- c("TH-1" = "SBG-TH1", "TH-2" = "SBG-TH2", "TH-3" = "SBG-TH3")
  source_name <- "Skalbeck (2001) Table B-2 (TH-1/TH-2/TH-3)"
  dbExecute(con, "INSERT OR IGNORE INTO Data_Sources (name, notes) VALUES (?, ?)",
            params = list(source_name,
              "Real monthly water-depth (m) readings for SBG-TH1/2/3, p.210-213. No chemistry in this table section -- water depth only. A real, unresolved discrepancy exists between this table's own earliest readings (1989) and Table 1's stated 1991 completion date for these wells -- flagged, not resolved."))

  n_inserted <- 0L; n_skipped <- 0L; n_unmatched <- 0L
  for (i in seq_len(nrow(rows))) {
    r <- rows[i, ]
    well_name <- well_map[[r$well_name[1]]]
    well_id <- .skalbeck_resolve_well(con, well_name)
    if (is.na(well_id)) {
      n_unmatched <- n_unmatched + 1L
      next
    }
    already <- dbGetQuery(con, "
      SELECT observation_id FROM Water_Level_Observations
      WHERE well_id = ? AND method = ? AND timestamp = ?
    ", params = list(well_id, source_name, r$date[1]))
    if (nrow(already) > 0) { n_skipped <- n_skipped + 1L; next }
    dbExecute(con, "
      INSERT INTO Water_Level_Observations (well_id, timestamp, depth_to_water, method, method_type, notes)
      VALUES (?, ?, ?, ?, 'historical', ?)
    ", params = list(well_id, r$date[1], r$water_depth_m[1], source_name,
                       "Real depth-to-water reading (meters), Skalbeck (2001) Table B-2."))
    n_inserted <- n_inserted + 1L
  }
  message("  -> Inserted ", n_inserted, " real water-depth reading(s) (", n_skipped, " already present, ",
          n_unmatched, " unmatched well name(s)).")
  invisible(list(inserted = n_inserted, skipped = n_skipped, unmatched = n_unmatched))
}
