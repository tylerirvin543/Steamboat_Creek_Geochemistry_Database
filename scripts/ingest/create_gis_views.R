library(DBI)

create_gis_views <- function(con) {
  
  message("---- Creating GIS views ----")
  
  if (missing(con)) {
    stop("Database connection `con` not provided.")
  }
  
  dbExecute(con, "PRAGMA foreign_keys = ON;")
  
  # ==================================================
  # DROP EXISTING VIEWS
  # ==================================================
  
  dbExecute(con, "DROP VIEW IF EXISTS vw_locations_gis")
  dbExecute(con, "DROP VIEW IF EXISTS vw_logger_locations")
  # vw_temperature_timeseries is NOT dropped/recreated here anymore --
  # see create_analysis_views.R (session 26 fix). This file used to
  # define its own competing version (observation_id/coord_key/geom_wkt
  # but no logger_id, and critically never converted the stored
  # Unix-epoch timestamp at all) which silently won or lost depending
  # purely on which of the two functions ran last in run_pipeline.R --
  # a real, order-dependent bug, not just a style duplication. The
  # single surviving definition now carries every column either
  # consumer (build_thermal_summary()'s need for logger_id, or
  # export_geopackage()'s need for geom_wkt) actually needs.
  message("→ Creating base spatial layers")
  
  # ==================================================
  # LOCATIONS
  # ==================================================
  
  dbExecute(con, "
  CREATE VIEW vw_locations_gis AS
  SELECT
    location_id,
    coord_key,
    name,
    site_type,
    latitude,
    longitude,
    elevation_m,
    'POINT(' || longitude || ' ' || latitude || ')' AS geom_wkt
  FROM Locations
  WHERE latitude IS NOT NULL
    AND longitude IS NOT NULL
  ")
  
  # ==================================================
  # LOGGER LOCATIONS
  # ==================================================
  
  dbExecute(con, "
  CREATE VIEW vw_logger_locations AS
  SELECT
    lg.logger_id,
    lg.logger_name,
    l.location_id,
    l.coord_key,
    l.name AS location,
    l.latitude,
    l.longitude,
    lg.deployment_start,
    lg.deployment_end,
    'POINT(' || l.longitude || ' ' || l.latitude || ')' AS geom_wkt
  FROM Temperature_Loggers lg
  JOIN Locations l ON lg.location_id = l.location_id
  WHERE l.latitude IS NOT NULL
  ")
  
  message("✅ GIS views rebuilt successfully (vw_locations_gis, vw_logger_locations)")
}
