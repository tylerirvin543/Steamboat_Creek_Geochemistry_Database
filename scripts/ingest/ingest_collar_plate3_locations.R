# ------------------------------------------------------------
# ingest_collar_plate3_locations.R
#
# Locations the user georeferenced from Collar (1990) Plate 3 in ArcGIS
# (data/raw/arcgis/excel ingest/Collar_plate3_well_and_spring_locations.xlsx,
# cleaned to collar_plate3_clean.csv with a human-reviewed match for each row).
#   match_type 'well'     : Wells row matched by well_name (or Well_Aliases)
#   match_type 'location' : Locations row matched by name
#   match_type 'new'      : no existing record; a Locations row is created
# Rules: a missing coordinate is filled (and the linked Locations row too); a
# coordinate that is only a PLSS section centroid is replaced by the plate point;
# any other existing coordinate is never overwritten, the distance is logged to
# data/derived/collar_plate3_coordinate_comparison.csv for review.
# Plate points are digitized from a scanned map: uncertainty is set to 50 m.
# ------------------------------------------------------------
suppressPackageStartupMessages(library(DBI))

ingest_collar_plate3_locations <- function(con,
    csv_path = "data/raw/arcgis/excel ingest/collar_plate3_clean.csv",
    compare_csv = "data/derived/collar_plate3_coordinate_comparison.csv") {
  message("---- Ingesting Collar (1990) Plate 3 georeferenced locations ----")
  if (!file.exists(csv_path)) { message("  no file at ", csv_path); return(invisible(NULL)) }
  d <- read.csv(csv_path, stringsAsFactors = FALSE, na.strings = "")
  src <- "collar1990_plate3_georeferenced"; unc <- 50
  hav <- function(la1, lo1, la2, lo2) { p <- pi/180; a <- sin((la2-la1)*p/2)^2 + cos(la1*p)*cos(la2*p)*sin((lo2-lo1)*p/2)^2; 6371000*2*asin(sqrt(a)) }
  filled <- replaced <- created <- 0L; cmp <- list()
  add_cmp <- function(r, kind, id, nm, la, lo, action) {
    cmp[[length(cmp)+1]] <<- data.frame(plate_feature = r$feature_display, target = kind, target_id = id, target_name = nm,
      existing_lat = la, existing_lon = lo, plate_lat = r$latitude, plate_lon = r$longitude,
      distance_m = if (is.na(la)) NA else round(hav(la, lo, r$latitude, r$longitude)), action = action, stringsAsFactors = FALSE)
  }
  note <- function(r) sprintf("Collar (1990) Plate 3 georeferenced point '%s' (+/-%d m).", r$feature_display, unc)

  for (i in seq_len(nrow(d))) {
    r <- d[i, ]
    if (r$match_type == "new") {
      if (nrow(dbGetQuery(con, "SELECT 1 FROM Locations WHERE external_station_code = ?", params = list(r$external_station_code)))) next
      dbExecute(con, "INSERT INTO Locations (external_station_code, name, latitude, longitude, crs, site_type, coordinate_source, coordinate_uncertainty_m, notes) VALUES (?,?,?,?,'EPSG:4326',?,?,?,?)",
                params = list(r$external_station_code, r$feature_display, r$latitude, r$longitude, r$site_type, src, unc,
                              paste(note(r), if (!is.na(r$notes)) paste("Note:", r$notes))))
      created <- created + 1L; next
    }
    if (r$match_type == "well") {
      w <- dbGetQuery(con, "SELECT well_id, latitude, longitude, coordinate_source, location_id FROM Wells WHERE well_name = ?", params = list(r$match_name))
      if (nrow(w) == 0) w <- dbGetQuery(con, "SELECT w.well_id, w.latitude, w.longitude, w.coordinate_source, w.location_id FROM Wells w JOIN Well_Aliases a USING(well_id) WHERE a.alias = ?", params = list(r$match_name))
      if (nrow(w) != 1) { warning("Plate 3: no unique well for '", r$match_name, "'"); next }
      if (is.na(w$latitude)) {
        dbExecute(con, "UPDATE Wells SET latitude=?, longitude=?, coordinate_source=?, coordinate_uncertainty_m=? WHERE well_id=?", params = list(r$latitude, r$longitude, src, unc, w$well_id))
        if (!is.na(w$location_id)) dbExecute(con, "UPDATE Locations SET latitude=?, longitude=?, coordinate_source=?, coordinate_uncertainty_m=? WHERE location_id=? AND latitude IS NULL", params = list(r$latitude, r$longitude, src, unc, w$location_id))
        filled <- filled + 1L; add_cmp(r, "Wells", w$well_id, r$match_name, NA, NA, "filled")
      } else if (identical(w$coordinate_source, "plss_section_centroid")) {
        add_cmp(r, "Wells", w$well_id, r$match_name, w$latitude, w$longitude, "replaced_plss_centroid")
        dbExecute(con, "UPDATE Wells SET latitude=?, longitude=?, coordinate_source=?, coordinate_uncertainty_m=? WHERE well_id=?", params = list(r$latitude, r$longitude, src, unc, w$well_id))
        replaced <- replaced + 1L
      } else add_cmp(r, "Wells", w$well_id, r$match_name, w$latitude, w$longitude, "kept_existing")
    } else {
      l <- dbGetQuery(con, "SELECT location_id, latitude, longitude FROM Locations WHERE name = ?", params = list(r$match_name))
      if (nrow(l) != 1) { warning("Plate 3: no unique location for '", r$match_name, "'"); next }
      if (is.na(l$latitude)) {
        dbExecute(con, "UPDATE Locations SET latitude=?, longitude=?, coordinate_source=?, coordinate_uncertainty_m=? WHERE location_id=?", params = list(r$latitude, r$longitude, src, unc, l$location_id))
        filled <- filled + 1L; add_cmp(r, "Locations", l$location_id, r$match_name, NA, NA, "filled")
      } else add_cmp(r, "Locations", l$location_id, r$match_name, l$latitude, l$longitude, "kept_existing")
    }
  }
  # Only write the log when this run changed something, so a no-op re-run does not erase the first run's distances
  if (length(cmp) && (filled + replaced + created > 0 || !file.exists(compare_csv))) { dir.create(dirname(compare_csv), showWarnings = FALSE, recursive = TRUE); write.csv(do.call(rbind, cmp), compare_csv, row.names = FALSE) }
  message("  -> coordinates filled: ", filled, " | PLSS centroids replaced: ", replaced, " | new Locations: ", created, " | comparison log: ", compare_csv)
  invisible(list(filled = filled, replaced = replaced, created = created))
}
