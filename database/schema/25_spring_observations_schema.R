#25_spring_observations_schema
# ------------------------------------------------------------
# Dated hot-spring observations (activity, temperature, depth to water in the
# vent, flow) per spring. First source: Collar (1990) Appendix A, Jun 1977 - Apr
# 1988, from Nehring, GOSA, Hudson, BLM and NDEP notes. The table is source-
# agnostic so later observations (e.g. 2026 field visits, Lindsey et al.) can be
# appended with a different source_document.
#
# location_id is NULL until the spring has a Locations row (matched by spring
# number in Locations.name); a re-run of the ingest fills it once one exists.
# raw_text is the observer's wording as read from the OCR; the parsed columns
# are extracted from it and can be wrong where the OCR is poor.
# ------------------------------------------------------------
library(DBI)

if (!exists("con")) stop("Database connection `con` not found. Run via run_pipeline.R.")

dbExecute(con, "
CREATE TABLE IF NOT EXISTS Spring_Observations (
  obs_id INTEGER PRIMARY KEY,
  obs_key TEXT NOT NULL UNIQUE,
  location_id INTEGER REFERENCES Locations(location_id),
  spring_id TEXT NOT NULL,          -- White (1968) / Collar spring number, e.g. '12sw'
  id_range_end TEXT,                -- set when the source gave a range such as 16-16se
  terrace TEXT,
  obs_date TEXT NOT NULL,           -- ISO date
  date_note TEXT,
  source_code TEXT,                 -- NN, GOSA, DH, BLM, NDEP (joined with + when several)
  source_name TEXT,
  status TEXT,                      -- erupting, flowing, dry, almost_dry, steaming, boiling, seep, active, water_in_vent, other
  temperature_c REAL,
  depth_to_water_ft REAL,
  depth_basis TEXT,                 -- below_rim, depth_to_water, unspecified
  depth_estimated INTEGER,
  depth_alt_ft REAL,                -- second reading when two observers reported
  depth_alt_source TEXT,
  flow_lpm REAL,
  raw_text TEXT,
  source_document TEXT
)")
dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_spring_obs_spring ON Spring_Observations(spring_id, obs_date)")
dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_spring_obs_loc ON Spring_Observations(location_id)")

dbExecute(con, "DROP VIEW IF EXISTS vw_spring_observations_gis")
dbExecute(con, "
CREATE VIEW vw_spring_observations_gis AS
SELECT o.*, l.name AS location_name, l.latitude, l.longitude,
       'POINT(' || l.longitude || ' ' || l.latitude || ')' AS geom_wkt
FROM Spring_Observations o JOIN Locations l ON l.location_id = o.location_id
WHERE l.latitude IS NOT NULL AND l.longitude IS NOT NULL")
