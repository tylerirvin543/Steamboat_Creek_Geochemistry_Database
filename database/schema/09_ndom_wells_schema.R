#09_ndom_wells_schema
# ------------------------------------------------------------
# Additive schema extension for NDOM (Nevada Division of Minerals)
# well-permit data (data/raw/ndom/Ormat Steamboat Wells.xlsx, supplied
# by Keith Hayes/NDOM 2026-09). This is the official state permit
# record for every Ormat well at Steamboat -- permit number, API
# number, BLM lease number, well type, in-use/shut-in status, spud/
# completion dates, total depth, elevation, and UTM coordinates -- and
# is used both to cross-validate coordinates already in Wells (sourced
# from NBMG/ArcGIS digitization in earlier sessions) and to fill gaps
# for wells not previously matched to any coordinate at all.
#
# Sourced immediately after 01-08 (both at initial connection and
# inside the DEMO reset block in run_pipeline.R).
#
# Two things happen here:
#   1. MIGRATION: new Wells identifier/status columns, plus a one-time
#      fix for a pre-existing unit bug (see below).
#   2. NDOM_Well_Records: a staging table (mirrors Well_Log_Documents /
#      Staging_NDEP_WQ) holding the raw NDOM spreadsheet verbatim, one
#      row per Permit, plus the UTM->lat/lon conversion and a record of
#      how (if at all) each row was matched to an existing Wells row.
#      Actual matching/upserting into Wells happens in
#      scripts/ingest/ingest_ndom_wells.R, not here -- this file only
#      defines structure, consistent with every other *_schema.R file
#      in this project.
#
# ------------------------------------------------------------
# ELEVATION UNIT BUG (found while scoping this NDOM ingestion)
# ------------------------------------------------------------
# Wells.elevation_m has been storing raw FEET since it was first
# populated by ingest_ndwr.R -- e.g. "Sky Tavern Ski Resort" =
# 7619, "Galena Creek Park" = 6017. Steamboat-area true elevations are
# ~1450-1750 m; even the highest surrounding peaks are nowhere near
# 6000-7600 true meters. All 73 currently-populated rows fall in the
# 4411-7619 range, consistent with 100% of them being feet, not a
# per-row mix -- confirmed before writing this migration.
#
# Fixed once, here: any Wells.elevation_m > 3000 is assumed to be
# stored in feet and is converted to true meters (* 0.3048). This
# migration is naturally idempotent -- post-conversion, Steamboat-area
# elevations top out around 1450-2325 m, safely under the 3000
# threshold, so a second run finds nothing left to convert. NDOM's own
# elevations (also supplied in feet) are converted correctly by
# ingest_ndom_wells.R using the same 0.3048 factor before insert, so
# the column is consistent both going forward and retroactively.
# ------------------------------------------------------------

library(DBI)
library(RSQLite)

if (!exists("con")) {
  stop("Database connection `con` not found. Run via run_pipeline.R.")
}

dbExecute(con, "PRAGMA foreign_keys = ON;")

# -----------------------
# MIGRATION: Wells identifier/status columns
# -----------------------
wells_cols <- dbListFields(con, "Wells")
new_well_cols <- c(
  "ndom_permit", "api_number", "blm_lease_number", "well_status",
  "spud_date", "completion_date", "field_name", "land_type"
)
for (col in new_well_cols) {
  if (!col %in% wells_cols) {
    message("[MIGRATION] Wells.", col, " missing -- adding.")
    dbExecute(con, paste0("ALTER TABLE Wells ADD COLUMN ", col, " TEXT"))
  }
}

# -----------------------
# MIGRATION: one-time elevation_m feet -> meters fix (see header)
# -----------------------
n_bad_elev <- dbGetQuery(con, "SELECT COUNT(*) AS n FROM Wells WHERE elevation_m > 3000")$n
if (n_bad_elev > 0) {
  message("[MIGRATION] Converting ", n_bad_elev,
          " Wells.elevation_m value(s) from feet to true meters (one-time fix).")
  dbExecute(con, "UPDATE Wells SET elevation_m = elevation_m * 0.3048 WHERE elevation_m > 3000")
} else {
  message("[MIGRATION] Wells.elevation_m unit fix already applied (or not needed) -- 0 rows > 3000.")
}

# Same bug, same root cause (ingest_ndwr.R), also affects Locations.elevation_m
# (found 2026-09-12 while idempotency-testing the NDOM stage in a fresh DEMO
# rebuild -- the original Session 21 fix only covered Wells). ingest_ndwr.R
# itself is now fixed to convert at insert time for both tables, so this
# retroactive pass should become a permanent no-op going forward.
n_bad_elev_loc <- dbGetQuery(con, "SELECT COUNT(*) AS n FROM Locations WHERE elevation_m > 3000")$n
if (n_bad_elev_loc > 0) {
  message("[MIGRATION] Converting ", n_bad_elev_loc,
          " Locations.elevation_m value(s) from feet to true meters (one-time fix).")
  dbExecute(con, "UPDATE Locations SET elevation_m = elevation_m * 0.3048 WHERE elevation_m > 3000")
} else {
  message("[MIGRATION] Locations.elevation_m unit fix already applied (or not needed) -- 0 rows > 3000.")
}

# -----------------------
# NDOM WELL RECORDS (staging: raw spreadsheet + computed lat/lon +
# match outcome)
# -----------------------
dbExecute(con, "
CREATE TABLE IF NOT EXISTS NDOM_Well_Records (
  ndom_record_id INTEGER PRIMARY KEY,

  permit TEXT UNIQUE NOT NULL,
  well_name_raw TEXT,
  api TEXT,
  blm_lease_number TEXT,
  well_type TEXT,
  status TEXT,
  field TEXT,
  county TEXT,
  operator TEXT,
  permit_issued TEXT,
  permit_expires_date TEXT,
  spud_date TEXT,
  completion_date TEXT,
  total_depth_ft REAL,
  utm_easting REAL,
  utm_northing REAL,
  land_type TEXT,
  elevation_ft REAL,

  latitude REAL,
  longitude REAL,

  matched_well_id INTEGER,
  match_method TEXT CHECK (
    match_method IN ('exact_name', 'alias', 'provisional_new', 'unresolved')
  ),
  resolved_well_name TEXT,

  source TEXT DEFAULT 'NDOM (Nevada Division of Minerals), via Keith Hayes, data/raw/ndom/Ormat Steamboat Wells.xlsx',
  ingested_at TEXT DEFAULT CURRENT_TIMESTAMP,

  FOREIGN KEY (matched_well_id) REFERENCES Wells(well_id)
);
")

dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_ndom_records_well ON NDOM_Well_Records(matched_well_id)")

message("[SCHEMA] NDOM wells schema ready (Wells identifier columns, elevation_m unit fix, NDOM_Well_Records).")
