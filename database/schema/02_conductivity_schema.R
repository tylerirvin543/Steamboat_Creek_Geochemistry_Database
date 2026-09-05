#02_conductivity_schema
# ------------------------------------------------------------
# Additive schema extension for stream conductivity loggers
# (HOBO/Onset "Full Range" EC loggers, distinct from the
# Elitech Temperature_Loggers/Temperature_Observations pair).
#
# Sourced immediately after 01_define_schema.R (both at initial
# connection and inside the DEMO reset block in run_pipeline.R).
#
# Design mirrors Temperature_Loggers / Temperature_Observations:
#   Conductivity_Loggers       -> logger + deployment metadata
#   Conductivity_Observations  -> append-only time series
#
# This file also seeds the one new Location required for the
# downstream logger (SBGG), since it did not exist in the
# Locations spreadsheet prior to this deployment. Long-term, this
# location should be reconciled into data/raw/field/locations.xlsx
# so it flows through ingest_field.R like other curated locations.
# ------------------------------------------------------------

library(DBI)
library(RSQLite)

if (!exists("con")) {
  stop("Database connection `con` not found. Run via run_pipeline.R.")
}

dbExecute(con, "PRAGMA foreign_keys = ON;")

# -----------------------
# NEW LOCATION: SBGG (Logger 2, downstream)
# -----------------------
# Coordinates and role provided directly by the PI; not yet present
# in the field locations template. Inserted idempotently.

dbExecute(con, "
INSERT OR IGNORE INTO Locations
  (external_station_code, name, latitude, longitude, elevation_m, crs, site_type, notes)
VALUES
  ('SBGG', 'Steamboat Creek — downstream conductivity logger (SBGG)',
   39.40584, -119.74213, NULL, 'EPSG:4326', 'creek',
   'Added via 02_conductivity_schema.R for downstream HOBO conductivity logger deployment; reconcile into data/raw/field/locations.xlsx when convenient.')
")

# -----------------------
# CONDUCTIVITY LOGGERS (metadata)
# -----------------------

dbExecute(con, "
CREATE TABLE IF NOT EXISTS Conductivity_Loggers (
  logger_id INTEGER PRIMARY KEY,
  logger_name TEXT,
  manufacturer TEXT DEFAULT 'Onset/HOBO',
  model TEXT,
  serial_number TEXT UNIQUE NOT NULL,
  location_id INTEGER,
  role TEXT CHECK (role IN ('upstream_control', 'downstream')),
  deployment_start DATETIME,
  deployment_end DATETIME,
  status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'retrieved', 'destroyed', 'lost', 'standby')),
  notes TEXT,
  CHECK (status = 'standby' OR location_id IS NOT NULL),
  FOREIGN KEY (location_id) REFERENCES Locations(location_id)
);
")

# -----------------------
# CONDUCTIVITY OBSERVATIONS (time series)
# -----------------------

dbExecute(con, "
CREATE TABLE IF NOT EXISTS Conductivity_Observations (
  observation_id INTEGER PRIMARY KEY,
  logger_id INTEGER NOT NULL,
  timestamp TEXT NOT NULL,       -- UTC, same convention as Temperature_Observations
  ec_raw REAL,                   -- 'Full Range' EC as logged, uncompensated, uS/cm
  temperature_c REAL,
  sc_25c REAL,                   -- specific conductance @ 25C, derived, uS/cm
  units TEXT DEFAULT 'uS/cm',
  logger_event TEXT,             -- 'Logged' | 'Coupler Detached' | 'Coupler Attached' | 'Stopped' | 'End Of File'
  qc_flag TEXT,                  -- NULL | 'spike' | 'dropout' | 'field_visit_disturbance' | 'gap_boundary'
  source_id INTEGER,

  FOREIGN KEY (logger_id) REFERENCES Conductivity_Loggers(logger_id),
  FOREIGN KEY (source_id) REFERENCES Data_Sources(source_id)
);
")

dbExecute(con, "
CREATE UNIQUE INDEX IF NOT EXISTS idx_cond_obs_unique
ON Conductivity_Observations (logger_id, timestamp);
")

dbExecute(con, "
CREATE INDEX IF NOT EXISTS idx_cond_obs_time
ON Conductivity_Observations(timestamp);
")

dbExecute(con, "
CREATE INDEX IF NOT EXISTS idx_cond_logger_location
ON Conductivity_Loggers(location_id);
")

message("[SCHEMA] Conductivity schema ready (Conductivity_Loggers, Conductivity_Observations, Locations.SBGG).")
