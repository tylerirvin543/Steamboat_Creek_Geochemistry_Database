# ============================================================
# register_monitor_well_locations.R
#
# Purpose:
# Register human-confirmed Locations for groundwater monitor wells
# identified from literature (currently: Klein et al. 2007's Fig. 1
# monitor-well network around Steamboat) via NDWR WellLogQuery /
# NBMG well-database matching, when those wells carry no NDEP PRR
# chemistry of their own (so promote_staged_ndep.R's pipeline does
# not apply -- there is nothing to promote, just a location to add).
#
# Mapping file: data/raw/ndwr/klein2007_monitor_well_locations.csv
#   columns: external_station_code, name, site_type, latitude,
#            longitude, coordinate_source, coordinate_uncertainty_m,
#            notes
#   The `notes` column documents exactly how each coordinate was
#   found (source search, which candidate was chosen and why,
#   competing candidates rejected) -- see that file for the full
#   provenance record, not repeated here.
#
# Idempotency: keyed on Locations.external_station_code (UNIQUE);
# rows already present are left untouched (not updated) so a manual
# in-database correction is never silently clobbered by a re-run --
# edit the CSV *and* the existing Locations row together if a
# coordinate needs to change.
# ============================================================

library(DBI)
library(dplyr)
library(readr)
library(fs)

register_monitor_well_locations <- function(
    con,
    map_csv = "data/raw/ndwr/klein2007_monitor_well_locations.csv") {

  message("---- Registering literature-sourced monitor well locations ----")

  if (!file_exists(map_csv)) {
    message("[register monitor wells] No location map at ", map_csv, " -- nothing to register.")
    return(invisible(NULL))
  }

  map <- read_csv(map_csv, show_col_types = FALSE) |>
    filter(!is.na(latitude), !is.na(longitude), !is.na(external_station_code))

  if (nrow(map) == 0) {
    message("[register monitor wells] No resolved (lat/lon-having) rows in the map.")
    return(invisible(NULL))
  }

  existing <- dbGetQuery(con, "SELECT external_station_code FROM Locations")
  new_locs <- map |> filter(!(external_station_code %in% existing$external_station_code))

  if (nrow(new_locs) == 0) {
    message("[register monitor wells] All ", nrow(map), " mapped location(s) already registered.")
    return(invisible(NULL))
  }

  to_insert <- new_locs |>
    transmute(
      external_station_code,
      name,
      latitude, longitude,
      crs = "EPSG:4326",
      site_type,
      coordinate_source, coordinate_uncertainty_m,
      notes
    )
  dbAppendTable(con, "Locations", to_insert)

  message("  -> Registered ", nrow(to_insert), " new Location(s): ",
          paste(to_insert$external_station_code, collapse = ", "))
  invisible(to_insert)
}
