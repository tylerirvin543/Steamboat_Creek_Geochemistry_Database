#26_well_identity_leads_schema
# ------------------------------------------------------------
# Candidate identities for a well whose identity is not confirmed (first use:
# SBW_0003, the shallow pipe that erupted next to the Lower Sinter Terrace
# fissure in June 2025). One row per candidate record (an NDWR log, an NBMG well,
# a plate point). Nothing here asserts an identity; status stays 'unconfirmed'
# until a person changes it, e.g. after the pipe is measured in the field.
# ------------------------------------------------------------
library(DBI)
if (!exists("con")) stop("Database connection `con` not found. Run via run_pipeline.R.")

dbExecute(con, "
CREATE TABLE IF NOT EXISTS Well_Identity_Leads (
  lead_id INTEGER PRIMARY KEY,
  well_id INTEGER NOT NULL REFERENCES Wells(well_id),
  lead_source TEXT NOT NULL,        -- ndwr_log, nbmg_geothermal_wells, collar_plate, white_plate
  lead_ref TEXT NOT NULL,           -- log number, NBMG apino, or plate label
  lead_name TEXT,
  owner TEXT,
  completion_date TEXT,
  depth_ft REAL,
  static_water_level_ft REAL,
  diameter_in REAL,
  location_basis TEXT,              -- e.g. 'section centroid', 'SW1/4 NE1/4 Sec 33', 'plate point +/-50 m'
  latitude REAL,
  longitude REAL,
  distance_m REAL,                  -- from the target well's coordinate
  rationale TEXT,
  status TEXT NOT NULL DEFAULT 'unconfirmed' CHECK (status IN ('unconfirmed', 'rejected', 'confirmed')),
  UNIQUE (well_id, lead_source, lead_ref)
)")
