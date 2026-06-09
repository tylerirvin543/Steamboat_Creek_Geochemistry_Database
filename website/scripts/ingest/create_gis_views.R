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
  dbExecute(con, "DROP VIEW IF EXISTS vw_temperature_timeseries")
  
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
  
  # ==================================================
  # TEMPERATURE TIMESERIES
  # ==================================================
  
  dbExecute(con, "
  CREATE VIEW vw_temperature_timeseries AS
  SELECT
    t.observation_id,
    l.location_id,
    l.coord_key,
    l.name AS location,
    l.latitude,
    l.longitude,
    t.timestamp,
    t.temperature,
    'POINT(' || l.longitude || ' ' || l.latitude || ')' AS geom_wkt
  FROM Temperature_Observations t
  JOIN Temperature_Loggers lg ON t.logger_id = lg.logger_id
  JOIN Locations l ON lg.location_id = l.location_id
  WHERE l.latitude IS NOT NULL
  ")
  
  message("✅ GIS views rebuilt successfully")
}