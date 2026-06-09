# ============================================================
# NDWR INGEST FUNCTION
# ============================================================
# Description:
# Ingests Nevada Division of Water Resources (NDWR) well metadata
# and water level time-series data into the database.
#
# This function:
#  - Cleans and standardizes site metadata
#  - Matches or creates spatial Locations
#  - Maintains External_Location_Map (NDWR ↔ internal IDs)
#  - Inserts new Wells (deduplicated)
#  - Inserts Water Level Observations (time series, multi-method)
#
# Key Design Features:
#  - Idempotent (safe to rerun without duplicates)
#  - Preserves multiple measurements per day (method-aware)
#  - Handles messy real-world NDWR data (missing, malformed rows)
#  - Uses stable IDs based on NDWR site identifiers
#
# Inputs:
#  con         : database connection
#  site_file   : path to NDWR site metadata Excel file
#  wl_file     : path to NDWR water level Excel file
#  basin_label : optional basin grouping label
#
# ============================================================

# ============================================================
# NDWR INGEST FUNCTION
# ============================================================

ingest_ndwr <- function(con, site_file, wl_file, basin_label = NULL) {
  
  library(dplyr)
  library(readxl)
  library(lubridate)
  
  #-----------------------------
  # Validate inputs
  #-----------------------------
  if (!file.exists(site_file)) stop("Missing site file")
  if (!file.exists(wl_file)) stop("Missing water level file")
  
  site <- read_xlsx(site_file)
  wl   <- read_xlsx(
    wl_file,
    col_types = c("text","date","numeric","numeric","text","text","text")
  )
  
  message("[NDWR] Loaded files")
  
  #-----------------------------
  # CLEAN SITE DATA
  #-----------------------------
  site_clean <- site |>
    rename(
      ndwr_site_id = `Site Name`,
      well_name  = `Well Name`,
      owner      = Owner,
      latitude   = `Lat DD NAD83`,
      longitude  = `Lon DD NAD83`,
      elevation  = Elev,
      total_depth = `Well Depth`,
      perfs_from  = `Perfs From`,
      perfs_to    = `Perfs To`,
      basin       = Basin,
      basin_name  = `basin name`
    ) |>
    mutate(
      ndwr_site_id = trimws(ndwr_site_id),
      latitude  = as.numeric(trimws(latitude)),
      longitude = as.numeric(trimws(longitude))
    ) |>
    mutate(
      latitude  = round(latitude, 6),
      longitude = round(longitude, 6),
      coord_key = paste0(latitude, "_", longitude),
      mid_screen_depth = perfs_from + (perfs_to - perfs_from) / 2,
      blended_flag = (perfs_to - perfs_from) > 300
    ) |>
    distinct(coord_key, .keep_all = TRUE)
  
  if (any(is.na(site_clean$coord_key))) {
    stop("Invalid NDWR coordinates detected")
  }
  
  #-----------------------------
  # LOCATIONS
  #-----------------------------
  locations_db <- dbReadTable(con, "Locations") |>
    select(location_id, coord_key)
  
  site_joined <- site_clean |>
    left_join(locations_db, by = "coord_key")
  
  new_locations <- site_joined |>
    filter(is.na(location_id)) |>
    transmute(
      external_station_code = paste0("NDWR_", gsub("\\s+", "", ndwr_site_id)),
      name = well_name,
      latitude,
      longitude,
      coord_key,
      elevation_m = elevation,
      site_type = "well",
      crs = "EPSG:4326"
    )
  
  new_locations <- new_locations |>
    anti_join(locations_db, by = "coord_key")
  
  if (nrow(new_locations) > 0) {
    dbWriteTable(con, "Locations", new_locations, append = TRUE)
    message("[NDWR] Inserted locations: ", nrow(new_locations))
  }
  
  # Reload
  locations_db <- dbReadTable(con, "Locations") |>
    select(location_id, coord_key)
  
  #-----------------------------
  # EXTERNAL LOCATION MAP
  #-----------------------------
  crosswalk <- site_clean |>
    left_join(locations_db, by = "coord_key") |>
    transmute(
      location_id,
      external_id = ndwr_site_id,
      source_system = "NDWR"
    ) |>
    filter(!is.na(location_id)) |>
    distinct(external_id, source_system, .keep_all = TRUE)
  
  existing_map <- dbReadTable(con, "External_Location_Map")
  
  crosswalk_new <- crosswalk |>
    anti_join(existing_map, by = c("external_id","source_system"))
  
  if (nrow(crosswalk_new) > 0) {
    dbWriteTable(con, "External_Location_Map", crosswalk_new, append = TRUE)
  }
  
  #-----------------------------
  # WELLS
  #-----------------------------
  wells <- site_clean |>
    left_join(locations_db, by = "coord_key") |>
    mutate(
      elevation_m = elevation,
      top_perforation = perfs_from,
      bottom_perforation = perfs_to
    ) |>
    select(
      ndwr_site_id, well_name, owner,
      latitude, longitude, coord_key,
      elevation_m, total_depth,
      top_perforation, bottom_perforation,
      mid_screen_depth, basin, basin_name,
      location_id
    ) |>
    distinct(ndwr_site_id, .keep_all = TRUE)
  
  wells_db <- dbReadTable(con, "Wells")
  
  wells_new <- wells |>
    anti_join(wells_db, by = "ndwr_site_id")
  
  if (nrow(wells_new) > 0) {
    dbWriteTable(con, "Wells", wells_new, append = TRUE)
    message("[NDWR] Inserted wells: ", nrow(wells_new))
  }
  
  #-----------------------------
  # WATER LEVELS
  #-----------------------------
  wl_clean <- wl |>
    rename(
      ndwr_site_id = `Site Name`,
      timestamp = `Measure Date`,
      depth_to_water = `Depth To Water`,
      water_level_elevation = `Water Surface Elevation`,
      method = Method,
      notes = remarks
    ) |>
    mutate(
      ndwr_site_id = trimws(ndwr_site_id),
      timestamp = if (inherits(timestamp,"POSIXct")) timestamp else parse_datetime_safe(timestamp),
      method_type = case_when(
        method == "T" ~ "manual",
        method == "F" ~ "transducer",
        TRUE ~ "other"
      )
    )
  
  wells_lookup <- dbReadTable(con, "Wells") |>
    select(well_id, ndwr_site_id, coord_key)
  
  obs <- wl_clean |>
    left_join(wells_lookup, by = "ndwr_site_id") |>
    filter(
      !is.na(well_id),
      !is.na(timestamp),
      !(is.na(depth_to_water) & is.na(water_level_elevation))
    ) |>
    select(
      well_id, coord_key, timestamp,
      depth_to_water, water_level_elevation,
      method, method_type, notes
    ) |>
    distinct(well_id, timestamp, method, .keep_all = TRUE)
  
  existing_obs <- dbReadTable(con, "Water_Level_Observations") |>
    mutate(timestamp = as.character(timestamp))
  
  obs <- obs |>
    mutate(timestamp = format(timestamp, "%Y-%m-%d %H:%M:%S"))
  
  obs_new <- obs |>
    anti_join(existing_obs, by = c("well_id","timestamp","method"))
  
  if (nrow(obs_new) > 0) {
    dbWriteTable(con, "Water_Level_Observations", obs_new, append = TRUE)
    message("[NDWR] Inserted observations: ", nrow(obs_new))
  }
  
  #-----------------------------
  # LOGGING
  #-----------------------------
  dbExecute(con, "
    INSERT INTO Ingest_Run_Log
    (timestamp, data_source, script_name, measurements_inserted, notes)
    VALUES (?, ?, ?, ?, ?)
  ", params = list(
    Sys.time(),
    "NDWR",
    "ingest_ndwr.R",
    nrow(obs_new),
    basename(site_file)
  ))
  
  message("✅ NDWR ingest complete")
}