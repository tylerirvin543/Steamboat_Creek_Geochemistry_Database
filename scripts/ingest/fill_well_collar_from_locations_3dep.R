# ------------------------------------------------------------
# fill_well_collar_from_locations_3dep.R
#
# Makes more Wells collar-ready for the Leapfrog export. Fill-only, never
# overwrites an existing value.
#   1. Registers a Wells row for any Location that has chemistry, a coordinate,
#      a well-type name, and no Wells row (Jeppson, Rogers).
#   2. Copies latitude/longitude (and coordinate_source/uncertainty) from the
#      linked Locations row onto Wells when Wells has none.
#   3. Fills Wells.elevation_m (and Locations.elevation_m) from the USGS 3DEP
#      Elevation Point Query Service where a coordinate exists but no elevation.
#      Source is appended to Wells.notes; 3DEP is ground surface, not collar-surveyed.
# total_depth is NOT filled here; wells still lacking it stay out of collar.csv.
# ------------------------------------------------------------
suppressPackageStartupMessages(library(DBI))

.query_3dep <- function(lat, lon) {
  url <- sprintf("https://epqs.nationalmap.gov/v1/json?x=%f&y=%f&units=Meters&wkid=4326", lon, lat)
  r <- tryCatch(jsonlite::fromJSON(url), error = function(e) NULL)
  v <- suppressWarnings(as.numeric(r$value))
  if (length(v) == 1 && !is.na(v) && v > -500) round(v, 1) else NA_real_
}

fill_well_collar_from_locations_3dep <- function(con, register = c("Jeppson Geothermal Well", "Rogers Domestic Well")) {
  message("---- Filling well collar fields from Locations and USGS 3DEP ----")
  # 1. register missing Wells rows
  for (nm in register) {
    loc <- dbGetQuery(con, "SELECT location_id FROM Locations WHERE name = ?", params = list(nm))
    if (nrow(loc) != 1) next
    if (nrow(dbGetQuery(con, "SELECT 1 FROM Wells WHERE location_id = ?", params = list(loc$location_id)))) next
    dbExecute(con, "INSERT INTO Wells (well_name, location_id, well_role, notes) VALUES (?, ?, 'domestic', ?)",
              params = list(sub(" Geothermal Well", " Domestic Well", nm), loc$location_id,
                            "Registered for Leapfrog export so its sampled chemistry is not hidden; no total_depth on file."))
    message("  -> registered Wells row for ", nm)
  }
  # 2. coordinates from Locations
  n_xy <- dbExecute(con, "UPDATE Wells SET
      latitude = (SELECT l.latitude FROM Locations l WHERE l.location_id = Wells.location_id),
      longitude = (SELECT l.longitude FROM Locations l WHERE l.location_id = Wells.location_id),
      coordinate_source = COALESCE(coordinate_source, (SELECT l.coordinate_source FROM Locations l WHERE l.location_id = Wells.location_id)),
      coordinate_uncertainty_m = COALESCE(coordinate_uncertainty_m, (SELECT l.coordinate_uncertainty_m FROM Locations l WHERE l.location_id = Wells.location_id))
    WHERE latitude IS NULL AND location_id IS NOT NULL
      AND (SELECT l.latitude FROM Locations l WHERE l.location_id = Wells.location_id) IS NOT NULL")
  message("  -> ", n_xy, " Wells row(s) got coordinates from their Locations row")
  # 3. 3DEP elevations
  todo <- dbGetQuery(con, "SELECT well_id, location_id, latitude, longitude FROM Wells WHERE elevation_m IS NULL AND latitude IS NOT NULL")
  n_el <- 0L
  for (i in seq_len(nrow(todo))) {
    z <- .query_3dep(todo$latitude[i], todo$longitude[i])
    if (is.na(z)) next
    dbExecute(con, "UPDATE Wells SET elevation_m = ?, notes = TRIM(COALESCE(notes,'') || ' [elevation_m from USGS 3DEP point query, ground surface]') WHERE well_id = ?", params = list(z, todo$well_id[i]))
    if (!is.na(todo$location_id[i]))
      dbExecute(con, "UPDATE Locations SET elevation_m = ? WHERE location_id = ? AND elevation_m IS NULL", params = list(z, todo$location_id[i]))
    n_el <- n_el + 1L
  }
  message("  -> ", n_el, " of ", nrow(todo), " well elevation(s) filled from 3DEP")
  invisible(list(coords = n_xy, elevations = n_el))
}
