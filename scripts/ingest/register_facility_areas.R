# ============================================================
# register_facility_areas.R
#
# Purpose:
# Ingest the user's ArcGIS-digitized power-plant/pad footprint
# polygons (data/raw/arcgis/*/Steamboat_power_plant_locations.shp --
# satellite imagery overlaid on the Dhakal et al. 2025 figure) into
# Facility_Areas (database/schema/06_facility_areas_schema.R), and use
# each polygon's centroid to give the corresponding Sampling_Ports row
# an approximate coordinate, since no port previously had one.
#
# Reads the shapefile directly with sf (not a CSV) since the payload
# is genuinely spatial (polygon geometry), not tabular. Reprojects to
# EPSG:4326 regardless of the source CRS.
#
# Facility_name -> Sampling_Ports.port_name mapping (the shapefile
# attribute uses short codes, Sampling_Ports uses the full Dhakal
# diagram names seeded in 05_well_network_schema.R):
#   G1     -> Galena 1
#   G2     -> Galena 2
#   G3     -> Galena 3
#   SBHR   -> SBHR
#   SB2/3  -> BOTH SB2 and SB3 (the source polygon is a single combined
#             pad covering both ports -- see the schema file's
#             "Known limitation" note; both ports get the SAME
#             centroid, which is an approximation, not two independent
#             fixes).
#
# Idempotency: Facility_Areas is matched on facility_name (UNIQUE);
# an existing polygon is left untouched, never overwritten. The
# Sampling_Ports centroid fill only happens when a port's latitude is
# currently NULL.
# ============================================================

library(DBI)
library(sf)
library(fs)

register_facility_areas <- function(
    con,
    shapefile = "data/raw/arcgis/dhakal .shp/Steamboat_power_plant_locations.shp") {

  message("---- Registering facility-area polygons ----")

  if (!file_exists(shapefile)) {
    message("[register facility areas] No shapefile at ", shapefile, " -- nothing to register.")
    return(invisible(NULL))
  }

  pp <- st_read(shapefile, quiet = TRUE)
  pp <- st_transform(pp, 4326)

  if (!"Powerplant" %in% names(pp)) {
    stop("[register facility areas] Expected column 'Powerplant' not found in ", shapefile)
  }

  existing <- dbGetQuery(con, "SELECT facility_name FROM Facility_Areas")$facility_name
  polygons_inserted <- 0L

  for (i in seq_len(nrow(pp))) {
    fname <- pp$Powerplant[i]

    if (fname %in% existing) next

    wkt <- st_as_text(st_geometry(pp)[i])

    dbExecute(con, "
      INSERT INTO Facility_Areas (facility_name, geom_wkt, crs, source, notes)
      VALUES (?, ?, 'EPSG:4326', ?, ?)
    ", params = list(
      fname, wkt,
      "ArcGIS satellite-overlay digitization of Dhakal et al. (2025) figure, by project user",
      paste0("Digitized power-plant/pad footprint. Source file: ", shapefile, ".")
    ))
    polygons_inserted <- polygons_inserted + 1L
  }

  message("  -> Facility_Areas polygons inserted: ", polygons_inserted,
          " (", length(existing), " already present, left untouched)")

  # -----------------------
  # SAMPLING_PORTS CENTROID FILL
  # -----------------------
  facility_to_port <- list(
    "G1" = "Galena 1",
    "G2" = "Galena 2",
    "G3" = "Galena 3",
    "SBHR" = "SBHR",
    "SB2/3" = "SB2/3"
  )

  ports_updated <- character(0)

  for (fname in names(facility_to_port)) {
    row <- pp[pp$Powerplant == fname, ]
    if (nrow(row) == 0) next

    centroid <- st_coordinates(st_centroid(st_geometry(row)))
    lon <- centroid[1, "X"]
    lat <- centroid[1, "Y"]

    for (port_name in facility_to_port[[fname]]) {
      port <- dbGetQuery(con, "SELECT port_id, latitude FROM Sampling_Ports WHERE port_name = ?",
                          params = list(port_name))
      if (nrow(port) == 0 || !is.na(port$latitude[1])) next

      dbExecute(con, "
        UPDATE Sampling_Ports
        SET latitude = ?, longitude = ?,
            coordinate_source = 'arcgis_facility_polygon_centroid',
            coordinate_uncertainty_m = ?,
            notes = COALESCE(notes || ' ', '') || ?
        WHERE port_id = ?
      ", params = list(
        lat, lon,
        75,
        paste0("Coordinate is the centroid of the '", fname, "' facility polygon in Facility_Areas."),
        port$port_id[1]
      ))
      ports_updated <- c(ports_updated, port_name)
    }
  }

  message("  -> Sampling_Ports given a centroid coordinate: ",
          if (length(ports_updated) > 0) paste(ports_updated, collapse = ", ") else "(none -- all already set)")

  invisible(list(polygons_inserted = polygons_inserted, ports_updated = ports_updated))
}
