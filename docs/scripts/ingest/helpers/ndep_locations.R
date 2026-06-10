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
  
  locations <- stations |>
    dplyr::transmute(
      external_station_code = .data[[col]],
      name = STATIONNAME,
      latitude = as.numeric(LATITUDE),
      longitude = as.numeric(LONGITUDE),
      elevation_m = NA_real_,
      geom = NA_character_,
      crs = "EPSG:4326",
      site_type = "background",
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