# 12_earthquake_schema.R
# ------------------------------------------------------------
# Additive schema for a real (not synthetic) local seismicity catalog,
# used to check whether nearby earthquakes coincide with detectable
# water-level, temperature, or barometric-response anomalies in the
# Steamboat system -- Sorey & Colvard (1992) explicitly name
# earthquakes, alongside barometric pressure and precipitation, as a
# real historical influence on spring/well water levels at this site.
#
# Earthquake_Events -- one row per USGS-catalogued event within a
# regional bounding box (see data/raw/earthquakes/README.md for the
# exact query), with a pre-computed distance to the Steamboat Hills
# field center so downstream analysis doesn't repeat the haversine
# calculation. This is intentionally a thin, single-purpose table
# (not a general seismology archive) -- if a future need wants more
# fields (focal mechanism, etc.), extend rather than replace.
# ------------------------------------------------------------

library(DBI)

if (!exists("con")) {
  stop("Database connection `con` not found. Run via run_pipeline.R.")
}

dbExecute(con, "
CREATE TABLE IF NOT EXISTS Earthquake_Events (
  event_id TEXT PRIMARY KEY,       -- USGS event id (e.g. 'nn00895746')
  event_time TEXT NOT NULL,        -- ISO 8601 UTC
  latitude REAL,
  longitude REAL,
  depth_km REAL,
  magnitude REAL,
  mag_type TEXT,
  place TEXT,
  event_type TEXT,                 -- 'earthquake' or 'explosion' (USGS-classified)
  dist_to_steamboat_km REAL,       -- haversine distance to 39.385 N, -119.755 W
  source TEXT DEFAULT 'USGS FDSN Event Web Service',
  retrieved_at TEXT
);
")

dbExecute(con, "
CREATE INDEX IF NOT EXISTS idx_earthquake_time ON Earthquake_Events(event_time);
")
dbExecute(con, "
CREATE INDEX IF NOT EXISTS idx_earthquake_dist ON Earthquake_Events(dist_to_steamboat_km);
")

message("[SCHEMA] Earthquake_Events ready.")
