# --------------------------------------------------
# NDEP Locations helper
# Parses StationData.csv and inserts Locations
# --------------------------------------------------

library(DBI)
library(dplyr)
library(readr)

# --------------------------------------------------
# Parse NDEP StationData into Locations format
# --------------------------------------------------

parse_ndep_locations <- function(station_csv) {
  
  stations <- read.csv(station_csv, stringsAsFactors = FALSE)
  
  # Clean names safely (NO pipe)
  names(stations) <- trimws(names(stations))
  names(stations) <- gsub("^X\\.\\.\\.", "", names(stations))
  names(stations) <- gsub("\ufeff", "", names(stations))
  names(stations) <- toupper(names(stations))
  
  # Remove empty column names
  valid_cols <- !is.na(names(stations)) & names(stations) != ""
  stations <- stations[, valid_cols]
  
  print(names(stations))
  
  col <- grep("MONITORINGLOCATIONID", names(stations), value = TRUE)[1]
  
  if (is.na(col)) {
    stop("MonitoringLocationID column not found")
  }
  
  # 2026-09-26: site_type used to be hardcoded "background" for every
  # NDEP station regardless of what kind of site it actually is.
  # Confirmed directly: every real NDEP StationData.csv station on
  # file so far is a creek/ditch surface-water monitoring point (by
  # name), so it should be site_type='creek', not the generic
  # 'background' fallback -- fixed via a real name/waterbody-based
  # classifier below rather than a blind constant, so a genuinely
  # ambiguous future NDEP station still safely falls back to
  # 'background' (a legitimate, if uninformative, schema value) and
  # is flagged for human review rather than guessed at.
  .classify_ndep_site_type <- function(station_name, waterbody_name) {
    combined <- paste(station_name, waterbody_name)
    ifelse(grepl("creek|ditch", combined, ignore.case = TRUE), "creek", "background")
  }

  locations <- stations |>
    dplyr::mutate(.site_type = .classify_ndep_site_type(STATIONNAME, WATERBODYNAME)) |>
    dplyr::transmute(
      external_station_code = .data[[col]],
      name = STATIONNAME,
      latitude = as.numeric(LATITUDE),
      longitude = as.numeric(LONGITUDE),
      elevation_m = NA_real_,
      geom = NA_character_,
      crs = "EPSG:4326",
      site_type = .site_type,
      notes = paste(
        "NDEP Station",
        "WaterBody:", WATERBODYNAME,
        "County:", COUNTY,
        sep = "; "
      )
    ) |>
    dplyr::mutate(
      latitude = round(latitude, 6),
      longitude = round(longitude, 6),
      coord_key = paste0(latitude, "_", longitude)
    ) |>
    dplyr::distinct(external_station_code, .keep_all = TRUE)
  
  print(names(locations))

  unmatched <- locations$name[locations$site_type == "background"]
  if (length(unmatched) > 0) {
    message("[ndep_locations] ", length(unmatched), " NDEP station(s) did not match a known ",
            "site-type pattern (creek/ditch) and stay 'background' -- review by name: ",
            paste(unmatched, collapse = "; "))
  }

  locations
}

# --------------------------------------------------
# Insert new NDEP locations into Locations table
# --------------------------------------------------

insert_ndep_locations <- function(con, locations_df) {
  
  existing <- DBI::dbReadTable(con, "Locations")
  
  if (nrow(existing) == 0) {
    new_locations <- locations_df
  } else {
    new_locations <- locations_df[
      !locations_df$external_station_code %in%
        existing$external_station_code,
      ,
      drop = FALSE
    ]
  }
  
  if (nrow(new_locations) == 0) {
    message("No new NDEP locations to insert.")
    return(invisible(NULL))
  }
  
  cols <- c(
    "external_station_code",
    "name",
    "latitude",
    "longitude",
    "elevation_m",
    "crs",
    "site_type",
    "notes"
  )
  
  missing_cols <- setdiff(cols, names(new_locations))
  if (length(missing_cols) > 0) {
    stop(
      "insert_ndep_locations(): missing columns: ",
      paste(missing_cols, collapse = ", ")
    )
  }
  
  print(names(new_locations))
  
  DBI::dbAppendTable(
    con,
    "Locations",
    new_locations |> select(all_of(cols))
  )
  
  message(nrow(new_locations), " NDEP locations inserted.")
}

# --------------------------------------------------
# Retroactive backfill: fix site_type for existing NDEP Locations rows
# --------------------------------------------------
#
# Ingestion is idempotent on external_station_code, so fixing the
# classifier above (parse_ndep_locations) alone does nothing for rows
# already in the database from before the fix. This backfill applies
# the exact same creek/ditch name-pattern rule directly to existing
# rows -- only ever changes a row currently 'background' whose name
# now matches (never touches a row already something else, never
# guesses at a genuinely ambiguous name).
backfill_ndep_site_types <- function(con) {
  bg <- DBI::dbGetQuery(con, "SELECT location_id, name FROM Locations WHERE site_type = 'background'")
  if (nrow(bg) == 0) {
    message("[ndep_locations] No 'background' rows to backfill.")
    return(invisible(0L))
  }
  bg$matches_creek <- grepl("creek|ditch", bg$name, ignore.case = TRUE)
  to_fix <- bg[bg$matches_creek, ]
  if (nrow(to_fix) > 0) {
    for (i in seq_len(nrow(to_fix))) {
      DBI::dbExecute(con, "UPDATE Locations SET site_type = 'creek' WHERE location_id = ?",
                      params = list(to_fix$location_id[i]))
    }
    message("[ndep_locations] Backfilled site_type 'background' -> 'creek' for ", nrow(to_fix),
            " existing row(s): ", paste(to_fix$name, collapse = "; "))
  }
  still_unmatched <- bg[!bg$matches_creek, ]
  if (nrow(still_unmatched) > 0) {
    message("[ndep_locations] ", nrow(still_unmatched), " existing 'background' row(s) still ",
            "unmatched, left as-is for human review: ", paste(still_unmatched$name, collapse = "; "))
  }
  invisible(nrow(to_fix))
}
