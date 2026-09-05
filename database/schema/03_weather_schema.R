# ------------------------------------------------------------
# 03_weather_schema.R
#
# Purpose:
# Support NOAA weather (precipitation + temperature) ingestion
# (scripts/ingest/ingest_noaa_weather.R). Extends the core schema;
# sourced after 01_define_schema.R / 02_conductivity_schema.R.
#
# Design:
# - Long format (one row per station/date/parameter) rather than one
#   column per variable, because the two NOAA export formats this
#   project has seen so far carry different, non-overlapping column
#   sets (see ingest_noaa_weather.R's format detector) -- long format
#   means a third/fourth future format just adds new `parameter`
#   values, not a schema migration.
# - Values are stored AS REPORTED (raw-data-untouched principle, same
#   as everywhere else in this project) -- one format is °F/inches,
#   the other is °C/mm -- with `unit` carried per row. Unit conversion
#   happens in vw_weather_metric (see create_analysis_views.R), not
#   at ingest time.
# ------------------------------------------------------------

dbExecute(con, "
CREATE TABLE IF NOT EXISTS Weather_Stations (
  station_id TEXT PRIMARY KEY,
  name TEXT,
  latitude REAL,
  longitude REAL,
  elevation_m REAL,
  source TEXT
);
")

dbExecute(con, "
CREATE TABLE IF NOT EXISTS Weather_Observations (
  station_id TEXT NOT NULL,
  date TEXT NOT NULL,
  parameter TEXT NOT NULL,
  value REAL,
  unit TEXT,
  quality_flag TEXT,
  source_file TEXT,
  PRIMARY KEY (station_id, date, parameter),
  FOREIGN KEY (station_id) REFERENCES Weather_Stations(station_id)
);
")

dbExecute(con, "
CREATE INDEX IF NOT EXISTS idx_weather_obs_date
ON Weather_Observations(date);
")

dbExecute(con, "
CREATE TABLE IF NOT EXISTS Weather_Files_Processed (
  file_name TEXT PRIMARY KEY,
  format TEXT,
  processed_at TEXT
);
")
