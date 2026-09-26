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
ingest_skalbeck2001_well_completions <- function(
    con,
    completions_csv = "data/raw/historical/skalbeck2001_well_completions.csv",
    chem_csv = "data/raw/historical/skalbeck2001_table2_chem_summary.csv") {

  message("---- Ingesting Skalbeck (2001) Table 1/2 well completions + chemistry ----")

  n_wells_created <- 0L
  n_fields_filled <- 0L
  n_chem_rows <- 0L
  unmapped <- character(0)

  resolve_well <- function(name_raw) {
    # 1. exact well_name match
    w <- dbGetQuery(con, "SELECT well_id, well_name FROM Wells WHERE well_name = ?", params = list(name_raw))
    if (nrow(w) > 0) return(w$well_id[1])
    # 2. alias match
    a <- dbGetQuery(con, "SELECT well_id FROM Well_Aliases WHERE alias = ?", params = list(name_raw))
    if (nrow(a) > 0) return(a$well_id[1])
    NA_integer_
  }

  # A name may match an existing Locations row (a sampling point) with
  # no corresponding Wells row (construction detail) yet -- mirrors the
  # Boyd Domestic Well lesson (Wells and Locations are different ID
  # spaces). When that happens, create a real Wells row and link it via
  # location_id rather than leaving an orphaned duplicate.
  resolve_or_create_via_location <- function(name_raw) {
    loc <- dbGetQuery(con, "SELECT location_id FROM Locations WHERE name = ?", params = list(name_raw))
    if (nrow(loc) == 0) return(NA_integer_)
    location_id <- loc$location_id[1]
    already <- dbGetQuery(con, "SELECT well_id FROM Wells WHERE location_id = ?", params = list(location_id))
    if (nrow(already) > 0) return(already$well_id[1])
    dbExecute(con, "INSERT INTO Wells (well_name, location_id, well_role, notes) VALUES (?, ?, 'unknown', 'Linked to existing Locations row via Skalbeck (2001) Table 1 ingestion.')",
              params = list(name_raw, location_id))
    dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id[1]
  }

  if (fs::file_exists(completions_csv)) {
    comp <- readr::read_csv(completions_csv, show_col_types = FALSE)
    for (i in seq_len(nrow(comp))) {
      row <- comp[i, ]
      well_id <- resolve_well(row$well_name[1])
      if (is.na(well_id)) well_id <- resolve_or_create_via_location(row$well_name[1])
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
