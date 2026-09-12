#10_ndwr_stream_flow_schema
# ------------------------------------------------------------
# Additive schema for NDWR spring/stream flow (discharge) data, first
# supplied 2026-09-12 as TM_Spring_Stream_Flowdata (4 gauged sites on
# Whites Creek, Truckee Meadows basin -- daily manual discharge
# readings in cfs, going back to 2017). These sites are not at
# Steamboat itself, but are part of this project's broader hydrologic
# context (Whites Creek is one of the drainages downstream of/adjacent
# to the Steamboat outflow system this project otherwise tracks via
# the PVCC/downstream conductivity loggers and the USGS gauge).
#
# Sites are registered as ordinary Locations rows (site_type =
# 'creek') so they slot directly into the same spatial/GIS machinery
# (vw_locations_gis, the GeoPackage export, the website leaflet maps)
# as every other location in this project -- no new spatial concept
# needed. Only the time series itself (Stream_Flow_Observations) is
# new.
#
# Sourced immediately after 01-09 (both at initial connection and
# inside the DEMO reset block in run_pipeline.R).
# ------------------------------------------------------------

library(DBI)
library(RSQLite)

if (!exists("con")) {
  stop("Database connection `con` not found. Run via run_pipeline.R.")
}

dbExecute(con, "PRAGMA foreign_keys = ON;")

dbExecute(con, "
CREATE TABLE IF NOT EXISTS Stream_Flow_Observations (
  observation_id INTEGER PRIMARY KEY,

  location_id INTEGER NOT NULL,
  date TEXT NOT NULL,

  discharge_cfs REAL,

  method TEXT,        -- raw driller/gauge method text (flume, weir, stage-discharge rating, estimated, ...)
  measured_by TEXT,   -- e.g. TMWA, NDWR
  remarks TEXT,

  source TEXT DEFAULT 'NDWR (data/raw/ndwr/TM_Spring_Stream_Flowdata_*)',

  UNIQUE (location_id, date, method),

  FOREIGN KEY (location_id) REFERENCES Locations(location_id)
);
")

dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_stream_flow_location ON Stream_Flow_Observations(location_id)")
dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_stream_flow_date ON Stream_Flow_Observations(date)")

message("[SCHEMA] NDWR stream flow schema ready (Stream_Flow_Observations).")
