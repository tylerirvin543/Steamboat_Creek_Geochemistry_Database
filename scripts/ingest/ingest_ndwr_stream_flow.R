# ============================================================
# ingest_ndwr_stream_flow.R
#
# Purpose:
# Ingest NDWR spring/stream flow (discharge) data -- first supplied
# 2026-09-12 as "TM_Spring_Stream_Flowdata" (2 files: a small SiteData
# sheet with lat/lon/elevation for each gauged site, and a
# SpringAndStreamFlow sheet with daily discharge readings in cfs going
# back to 2017). Currently 4 sites, all on Whites Creek (Truckee
# Meadows basin).
#
# What this does:
#   1. Registers each site in SiteData as a Locations row
#      (site_type = 'creek'), matched/deduplicated on
#      external_station_code (NOT coord_key -- two of these four real
#      NDWR sites share an identical rounded lat/lon, e.g. a diversion
#      structure and its "above"/"below" companion points, so coord_key
#      is not a safe identity key here; this is the same class of bug
#      already fixed in ingest_field.R's Locations idempotency, see
#      AGENTS.md). Elevation (raw feet in the source file) is converted
#      to true meters at insert time, consistent with the project-wide
#      elevation_m fix.
#   2. Records an External_Location_Map crosswalk (source_system =
#      'NDWR_StreamFlow', external_id = the raw NDWR "Site Name") so
#      the discharge time series below can always be traced back to
#      its exact source site identifier.
#   3. Loads the daily discharge time series into
#      Stream_Flow_Observations (see
#      database/schema/10_ndwr_stream_flow_schema.R), joined to the
#      site's location_id via the external_station_code (not
#      coord_key). Units are normalized to lowercase 'cfs' (the raw
#      file mixes "cfs"/"CFS"). Idempotent on
#      (location_id, date, method) -- re-running with the same or an
#      updated file only inserts genuinely new rows.
#
# Designed to be pointed at any future NDWR spring/stream flow export
# with the same two-sheet shape, not hardcoded to today's single
# TM_Spring_Stream_Flowdata drop.
# ============================================================

library(DBI)
library(dplyr)
library(readxl)

ingest_ndwr_stream_flow <- function(
    con,
    site_file = "data/raw/ndwr/TM_Spring_Stream_Flowdata_2026_09_12_files/SiteData.xls.xlsx",
    flow_file = "data/raw/ndwr/TM_Spring_Stream_Flowdata_2026_09_12_files/SpringAndStreamFlow.xls.xlsx") {

  message("---- Ingesting NDWR spring/stream flow data ----")

  if (!file.exists(site_file) || !file.exists(flow_file)) {
    message("[ingest_ndwr_stream_flow] Missing ", site_file, " and/or ", flow_file, " -- nothing to ingest.")
    return(invisible(NULL))
  }

  site_raw <- read_excel(site_file, sheet = "SiteData") %>%
    rename(
      site_name = `Site Name`, location_name = `Location Name`,
      latitude = Latitude, longitude = Longtitude, elevation_ft = Elevation
    ) %>%
    mutate(
      site_name = trimws(site_name),
      latitude = round(as.numeric(latitude), 6),
      longitude = round(as.numeric(longitude), 6),
      coord_key = paste0(latitude, "_", longitude),
      elevation_m = elevation_ft * 0.3048,  # NDWR source Elevation column is in feet
      external_station_code = paste0("NDWR_SF_", gsub("[^A-Za-z0-9]+", "", site_name))
    ) %>%
    filter(!is.na(site_name), site_name != "") %>%
    distinct(external_station_code, .keep_all = TRUE)

  # --- Register Locations (matched on external_station_code -- NOT
  # coord_key, since two of these real sites share an identical
  # rounded lat/lon; see header) ---
  locations_db <- dbGetQuery(con, "SELECT location_id, external_station_code FROM Locations")

  new_locations <- site_raw %>%
    anti_join(locations_db, by = "external_station_code") %>%
    transmute(
      external_station_code, name = location_name,
      latitude, longitude, coord_key, elevation_m,
      site_type = "creek",
      crs = "EPSG:4326",
      notes = paste0("NDWR spring/stream flow site (data/raw/ndwr/TM_Spring_Stream_Flowdata_*); raw site name '",
                      site_name, "'.")
    )

  n_new_locations <- 0L
  if (nrow(new_locations) > 0) {
    dbWriteTable(con, "Locations", new_locations, append = TRUE)
    n_new_locations <- nrow(new_locations)
    message("  -> Registered ", n_new_locations, " new Locations row(s).")
  }

  # Reload after insert
  locations_db <- dbGetQuery(con, "SELECT location_id, external_station_code FROM Locations")

  # --- External_Location_Map crosswalk ---
  crosswalk <- site_raw %>%
    inner_join(locations_db, by = "external_station_code") %>%
    transmute(location_id, external_id = site_name, source_system = "NDWR_StreamFlow") %>%
    distinct()

  existing_map <- dbGetQuery(con, "SELECT external_id, source_system FROM External_Location_Map")
  crosswalk_new <- crosswalk %>% anti_join(existing_map, by = c("external_id", "source_system"))
  if (nrow(crosswalk_new) > 0) {
    dbWriteTable(con, "External_Location_Map", crosswalk_new, append = TRUE)
  }

  # --- Discharge time series ---
  flow_raw <- read_excel(flow_file, sheet = "SpringAndStreamFlow") %>%
    rename(
      site_name = `Site name`, measure_date = `Measure Date`, discharge_cfs = Discharge,
      units = Units, measured_by = `Measured by`, remarks = Remarks, method = Method
    ) %>%
    mutate(
      site_name = trimws(site_name),
      units = tolower(trimws(units)),
      date = as.character(as.Date(measure_date))
    ) %>%
    filter(!is.na(site_name), !is.na(date))

  n_bad_units <- sum(!is.na(flow_raw$units) & flow_raw$units != "cfs")
  if (n_bad_units > 0) {
    warning("[ingest_ndwr_stream_flow] ", n_bad_units,
            " row(s) have a discharge unit other than cfs -- not converted, left as-is.")
  }

  site_lookup <- site_raw %>%
    inner_join(locations_db, by = "external_station_code") %>%
    select(site_name, location_id)

  flow_joined <- flow_raw %>%
    left_join(site_lookup, by = "site_name")

  unmatched <- flow_joined %>% filter(is.na(location_id)) %>% distinct(site_name)
  if (nrow(unmatched) > 0) {
    warning("[ingest_ndwr_stream_flow] ", nrow(unmatched),
            " site name(s) in the flow data have no matching site in SiteData -- skipped: ",
            paste(unmatched$site_name, collapse = ", "))
  }

  flow_joined <- flow_joined %>%
    filter(!is.na(location_id)) %>%
    transmute(location_id, date, discharge_cfs, method, measured_by, remarks) %>%
    distinct(location_id, date, method, .keep_all = TRUE)

  existing_obs <- dbGetQuery(con, "SELECT location_id, date, method FROM Stream_Flow_Observations") %>%
    mutate(method_key = coalesce(as.character(method), ""))

  new_obs <- flow_joined %>%
    mutate(method_key = coalesce(as.character(method), "")) %>%
    anti_join(existing_obs, by = c("location_id", "date", "method_key")) %>%
    select(-method_key)

  n_new_obs <- 0L
  if (nrow(new_obs) > 0) {
    dbWriteTable(con, "Stream_Flow_Observations", new_obs, append = TRUE)
    n_new_obs <- nrow(new_obs)
  }

  message("  -> ", nrow(flow_raw), " raw discharge row(s) in source file, ", n_new_obs, " new row(s) inserted.")
  message("[ingest_ndwr_stream_flow] Complete.")

  invisible(list(n_new_locations = n_new_locations, n_new_observations = n_new_obs))
}
