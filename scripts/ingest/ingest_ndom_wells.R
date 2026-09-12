# ============================================================
# ingest_ndom_wells.R
#
# Purpose:
# Ingest NDOM (Nevada Division of Minerals) permitted-well data for
# Ormat's Steamboat wells (data/raw/ndom/Ormat Steamboat Wells.xlsx,
# supplied by Keith Hayes/NDOM 2026-09) -- the official state permit
# record: Permit #, API #, BLM Lease Number, Well Type, Status,
# Spud/Completion dates, Total Depth, UTM coordinates, Elevation.
#
# What this does, per row:
#   1. Convert UTM Easting/Northing (assumed NAD83 UTM Zone 11N /
#      EPSG:26911, matching the convention already used elsewhere in
#      this project, e.g. the well-log OCR parser's
#      .extract_utm_latlon()) to lat/lon (EPSG:4326). Spot-checked
#      against 9 already-coordinated wells before writing this script:
#      most agree within ~15-50 m of the existing NBMG/ArcGIS-sourced
#      coordinate, consistent with this CRS assumption being correct.
#      A few rows (e.g. the bare "1"/"3" TG holes, "11-12-TG") have no
#      UTM coordinate in the source file at all -- left NULL rather
#      than erroring.
#   2. Stage the full raw row (every source column, untouched) into
#      NDOM_Well_Records (see database/schema/09_ndom_wells_schema.R),
#      idempotent on Permit.
#   3. Resolve the row's well name to an existing Wells row:
#        a. exact Wells.well_name match, OR
#        b. one of 7 confirmed spelling-variant matches (hardcoded
#           below, each independently checked against project notes
#           documenting the same variants from other sources), OR
#        c. an existing Well_Aliases match, OR
#        d. none of the above -> register as a new, provisional Wells
#           row (this is the common case: ~24 of 49 NDOM wells have no
#           prior record in this database at all).
#   4. Fill Wells fields ONLY WHEN CURRENTLY NULL (never overwrite):
#      well_role (mapped from Well Type), latitude/longitude/
#      elevation_m/coordinate_source/coordinate_uncertainty_m,
#      total_depth, and the new identifier columns (ndom_permit,
#      api_number, blm_lease_number, well_status, spud_date,
#      completion_date, field_name, land_type).
#   5. If a well ALREADY has a coordinate that disagrees with NDOM's by
#      more than 100 m, do NOT touch it -- log the discrepancy to
#      data/derived/ndom_coordinate_discrepancies.csv for manual
#      review instead (per this project's standing no-silent-overwrite
#      convention for coordinates).
#
# Two names are deliberately NOT treated as spelling variants of an
# existing well, per explicit review:
#   - "14-33" (NDOM permit 0708) vs. existing "14A-33" (permit 0669):
#     two distinct real NDOM permits: registered as its own new well,
#     with a note flagging the naming similarity for manual review.
#   - "1" / "3" (both Well Type = TG, thermal-gradient monitoring
#     holes, permits 0273/0275): renamed to "TG-1"/"TG-3" before any
#     matching, since a literal well_name of "1" or "3" is too generic
#     to be usable/safe going forward.
#
# Idempotent: re-running skips permits already in NDOM_Well_Records
# and re-applies the same never-overwrite Wells-fill logic (a no-op
# once fields are filled).
# ============================================================

library(DBI)
library(dplyr)
library(readxl)
library(sf)

#' Haversine great-circle distance in meters.
.haversine_m <- function(lat1, lon1, lat2, lon2) {
  r <- 6371000
  to_rad <- pi / 180
  dlat <- (lat2 - lat1) * to_rad
  dlon <- (lon2 - lon1) * to_rad
  a <- sin(dlat / 2)^2 + cos(lat1 * to_rad) * cos(lat2 * to_rad) * sin(dlon / 2)^2
  2 * r * asin(pmin(1, sqrt(a)))
}

ingest_ndom_wells <- function(
    con,
    xlsx_path = "data/raw/ndom/Ormat Steamboat Wells.xlsx",
    discrepancy_csv = "data/derived/ndom_coordinate_discrepancies.csv",
    coordinate_conflict_threshold_m = 100) {

  message("---- Ingesting NDOM well-permit data ----")

  if (!file.exists(xlsx_path)) {
    message("[ingest_ndom_wells] No file at ", xlsx_path, " -- nothing to ingest.")
    return(invisible(NULL))
  }

  raw <- read_excel(xlsx_path, sheet = 1) %>%
    rename(
      permit = Permit, well_name_raw = Well, api = API,
      blm_lease_number = `BLM Lease Number`, well_type = `Well Type`,
      status = Status, field = Field, county = County, operator = Operator,
      permit_issued = `Permit Issued`, permit_expires_date = `Permit Expires Date`,
      spud_date = `Spud Date`, completion_date = `Completion Date`,
      total_depth_ft = `Total Depth`, utm_easting = `UTM Easting`,
      utm_northing = `UTM Northing`, land_type = `Land Type`,
      elevation_ft = Elevation
    ) %>%
    mutate(
      permit = trimws(permit),
      well_name_raw = trimws(well_name_raw),
      total_depth_ft = suppressWarnings(as.numeric(total_depth_ft))
    ) %>%
    filter(!is.na(permit), permit != "")

  # --- UTM (NAD83 / UTM Zone 11N, EPSG:26911) -> lat/lon (EPSG:4326) ---
  raw$longitude <- NA_real_
  raw$latitude <- NA_real_
  has_utm <- !is.na(raw$utm_easting) & !is.na(raw$utm_northing)
  if (any(has_utm)) {
    pts <- st_as_sf(raw[has_utm, ], coords = c("utm_easting", "utm_northing"), crs = 26911, remove = FALSE)
    pts_wgs <- st_transform(pts, 4326)
    ll <- st_coordinates(pts_wgs)
    raw$longitude[has_utm] <- ll[, "X"]
    raw$latitude[has_utm] <- ll[, "Y"]
  }
  if (any(!has_utm)) {
    message("  -> ", sum(!has_utm), " row(s) have no UTM coordinate in the source file (",
            paste(raw$well_name_raw[!has_utm], collapse = ", "), ") -- coordinate left NULL for these.")
  }

  # --- Ambiguous single-character names: rename before any matching ---
  raw$well_name_resolved <- raw$well_name_raw
  raw$well_name_resolved[raw$well_name_raw == "1"] <- "TG-1"
  raw$well_name_resolved[raw$well_name_raw == "3"] <- "TG-3"

  # --- Confirmed spelling-variant map (NDOM name -> canonical Wells.well_name) ---
  variant_map <- c(
    "21-5"      = "21-5R",
    "13-5"      = "13-5R",
    "21B-5"     = "21B-5R",
    "83B-6"     = "83B-6R",
    "83C(82)-6" = "83C-6ST1",
    "23-33"     = "23-33RD",
    "46-28-2"   = "46-28"
  )

  # --- Well Type -> well_role ---
  role_map <- c("Obs" = "monitor", "TG" = "monitor", "Ind-Prod" = "production", "Ind-Inj" = "injection")

  # --- Which permits are already staged? (idempotency) ---
  existing_permits <- dbGetQuery(con, "SELECT permit FROM NDOM_Well_Records")$permit
  new_rows <- raw[!raw$permit %in% existing_permits, ]
  message("  -> ", nrow(raw), " NDOM row(s) total, ", nrow(new_rows), " new (", length(existing_permits), " already staged).")

  n_matched_exact <- 0L
  n_matched_alias <- 0L
  n_provisional <- 0L
  n_coords_filled <- 0L
  n_elev_filled <- 0L
  n_depth_filled <- 0L
  n_role_filled <- 0L
  n_ids_filled <- 0L
  discrepancies <- list()

  for (i in seq_len(nrow(new_rows))) {
    row <- new_rows[i, ]
    role <- unname(role_map[row$well_type])
    if (is.na(role)) role <- "unknown"

    candidate_name <- row$well_name_resolved
    canonical_name <- unname(variant_map[candidate_name])
    match_method <- NA_character_
    well_id <- NA_integer_
    resolved_well_name <- candidate_name

    if (!is.na(canonical_name)) {
      # Confirmed spelling-variant: must resolve to the existing canonical well
      w <- dbGetQuery(con, "SELECT well_id FROM Wells WHERE well_name = ?", params = list(canonical_name))
      if (nrow(w) > 0) {
        well_id <- w$well_id[1]
        match_method <- "alias"
        resolved_well_name <- canonical_name
        # Record the alias itself (idempotent)
        dbExecute(con, "
          INSERT OR IGNORE INTO Well_Aliases (well_id, alias, alias_type, source, notes)
          VALUES (?, ?, 'other', 'NDOM (Nevada Division of Minerals) permit data, via Keith Hayes',
                  'Confirmed spelling variant, registered by ingest_ndom_wells.R.')
        ", params = list(well_id, candidate_name))
      }
    }

    if (is.na(match_method)) {
      # exact name match
      w <- dbGetQuery(con, "SELECT well_id FROM Wells WHERE well_name = ?", params = list(candidate_name))
      if (nrow(w) > 0) {
        well_id <- w$well_id[1]
        match_method <- "exact_name"
      }
    }

    if (is.na(match_method)) {
      # existing alias match (not one of our hardcoded 7)
      w <- dbGetQuery(con, "
        SELECT w.well_id FROM Well_Aliases a JOIN Wells w ON w.well_id = a.well_id
        WHERE a.alias = ?
      ", params = list(candidate_name))
      if (nrow(w) > 0) {
        well_id <- w$well_id[1]
        match_method <- "alias"
      }
    }

    ndom_notes <- NA_character_
    if (candidate_name == "14-33") {
      ndom_notes <- "NDOM permit 0708, well name '14-33' -- similar to but NOT auto-merged with existing '14A-33' (permit 0669); flagged for manual review, kept as a separate well."
    }

    elevation_m <- if (!is.na(row$elevation_ft)) row$elevation_ft * 0.3048 else NA_real_
    has_coord <- !is.na(row$latitude) && !is.na(row$longitude)
    coord_key_val <- if (has_coord) paste0(row$latitude, "_", row$longitude) else NA_character_
    coord_source_val <- if (has_coord) "ndom_permit_data" else NA_character_
    coord_uncert_val <- if (has_coord) 30 else NA_real_

    if (is.na(match_method)) {
      # --- New provisional well ---
      dbExecute(con, "
        INSERT INTO Wells (
          well_name, well_role, latitude, longitude, coord_key, elevation_m, total_depth,
          coordinate_source, coordinate_uncertainty_m, notes,
          ndom_permit, api_number, blm_lease_number, well_status, spud_date, completion_date, field_name, land_type
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ", params = list(
        candidate_name, role, row$latitude, row$longitude,
        coord_key_val, elevation_m, row$total_depth_ft,
        coord_source_val, coord_uncert_val,
        ndom_notes,
        row$permit, row$api, row$blm_lease_number, row$status, row$spud_date, row$completion_date, row$field, row$land_type
      ))
      well_id <- dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id
      match_method <- "provisional_new"
      resolved_well_name <- candidate_name
      n_provisional <- n_provisional + 1L
      if (has_coord) n_coords_filled <- n_coords_filled + 1L
      if (!is.na(elevation_m)) n_elev_filled <- n_elev_filled + 1L
      if (!is.na(row$total_depth_ft)) n_depth_filled <- n_depth_filled + 1L
      n_role_filled <- n_role_filled + 1L
      n_ids_filled <- n_ids_filled + 1L
    } else {
      if (match_method == "exact_name") n_matched_exact <- n_matched_exact + 1L else n_matched_alias <- n_matched_alias + 1L

      existing <- dbGetQuery(con, "
        SELECT well_role, latitude, longitude, elevation_m, total_depth, ndom_permit,
               coordinate_source, coordinate_uncertainty_m
        FROM Wells WHERE well_id = ?
      ", params = list(well_id))

      # well_role: fill only if currently 'unknown'
      if (!is.na(existing$well_role[1]) && existing$well_role[1] == "unknown" && role != "unknown") {
        dbExecute(con, "UPDATE Wells SET well_role = ? WHERE well_id = ?", params = list(role, well_id))
        n_role_filled <- n_role_filled + 1L
      }

      # coordinates: fill only if currently NULL; else check for discrepancy
      if (is.na(existing$latitude[1])) {
        if (has_coord) {
          dbExecute(con, "
            UPDATE Wells SET latitude = ?, longitude = ?, coord_key = ?,
                              coordinate_source = ?, coordinate_uncertainty_m = ?
            WHERE well_id = ?
          ", params = list(row$latitude, row$longitude, coord_key_val, coord_source_val, coord_uncert_val, well_id))
          n_coords_filled <- n_coords_filled + 1L
        }
      } else if (has_coord) {
        d <- .haversine_m(existing$latitude[1], existing$longitude[1], row$latitude, row$longitude)
        if (!is.na(d) && d > coordinate_conflict_threshold_m) {
          discrepancies[[length(discrepancies) + 1]] <- data.frame(
            well_id = well_id, well_name = resolved_well_name, permit = row$permit,
            existing_lat = existing$latitude[1], existing_lon = existing$longitude[1],
            existing_coordinate_source = existing$coordinate_source[1],
            existing_coordinate_uncertainty_m = existing$coordinate_uncertainty_m[1],
            ndom_lat = row$latitude, ndom_lon = row$longitude,
            distance_m = round(d, 1)
          )
        }
      }

      # elevation: fill only if currently NULL
      if (is.na(existing$elevation_m[1]) && !is.na(elevation_m)) {
        dbExecute(con, "UPDATE Wells SET elevation_m = ? WHERE well_id = ?", params = list(elevation_m, well_id))
        n_elev_filled <- n_elev_filled + 1L
      }

      # total_depth: fill only if currently NULL
      if (is.na(existing$total_depth[1]) && !is.na(row$total_depth_ft)) {
        dbExecute(con, "UPDATE Wells SET total_depth = ? WHERE well_id = ?", params = list(row$total_depth_ft, well_id))
        n_depth_filled <- n_depth_filled + 1L
      }

      # identifier/status columns: fill only if currently NULL
      if (is.na(existing$ndom_permit[1])) {
        dbExecute(con, "
          UPDATE Wells SET ndom_permit = ?, api_number = ?, blm_lease_number = ?, well_status = ?,
                            spud_date = ?, completion_date = ?, field_name = ?, land_type = ?
          WHERE well_id = ?
        ", params = list(row$permit, row$api, row$blm_lease_number, row$status,
                          row$spud_date, row$completion_date, row$field, row$land_type, well_id))
        n_ids_filled <- n_ids_filled + 1L
      }

      if (!is.na(ndom_notes)) {
        dbExecute(con, "UPDATE Wells SET notes = COALESCE(notes || ' | ', '') || ? WHERE well_id = ?",
                  params = list(ndom_notes, well_id))
      }
    }

    # --- Stage the raw row (always, regardless of match outcome) ---
    dbExecute(con, "
      INSERT INTO NDOM_Well_Records (
        permit, well_name_raw, api, blm_lease_number, well_type, status, field, county, operator,
        permit_issued, permit_expires_date, spud_date, completion_date, total_depth_ft,
        utm_easting, utm_northing, land_type, elevation_ft, latitude, longitude,
        matched_well_id, match_method, resolved_well_name
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      row$permit, row$well_name_raw, row$api, row$blm_lease_number, row$well_type, row$status,
      row$field, row$county, row$operator, row$permit_issued, row$permit_expires_date,
      row$spud_date, row$completion_date, row$total_depth_ft, row$utm_easting, row$utm_northing,
      row$land_type, row$elevation_ft, row$latitude, row$longitude,
      well_id, match_method, resolved_well_name
    ))
  }

  # --- Write/append coordinate-discrepancy QC report ---
  if (length(discrepancies) > 0) {
    disc_df <- bind_rows(discrepancies)
    dir.create(dirname(discrepancy_csv), recursive = TRUE, showWarnings = FALSE)
    write.csv(disc_df, discrepancy_csv, row.names = FALSE)
    message("  -> ", nrow(disc_df), " coordinate discrepancy(ies) > ", coordinate_conflict_threshold_m,
            " m logged to ", discrepancy_csv, " (existing coordinates left untouched).")
  } else if (nrow(new_rows) > 0) {
    message("  -> No coordinate discrepancies > ", coordinate_conflict_threshold_m, " m found.")
  }

  message("  -> Matched exact name: ", n_matched_exact,
          " | Matched alias/variant: ", n_matched_alias,
          " | New provisional wells: ", n_provisional)
  message("  -> Filled: ", n_coords_filled, " coordinate(s), ", n_elev_filled, " elevation(s), ",
          n_depth_filled, " total_depth(s), ", n_role_filled, " well_role(s), ", n_ids_filled, " identifier set(s).")

  invisible(list(
    n_new_rows = nrow(new_rows), n_matched_exact = n_matched_exact, n_matched_alias = n_matched_alias,
    n_provisional = n_provisional, n_coords_filled = n_coords_filled, n_elev_filled = n_elev_filled,
    n_depth_filled = n_depth_filled, n_role_filled = n_role_filled, n_ids_filled = n_ids_filled,
    discrepancies = if (length(discrepancies) > 0) bind_rows(discrepancies) else NULL
  ))
}
