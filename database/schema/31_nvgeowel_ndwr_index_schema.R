#31_nvgeowel_ndwr_index_schema
# ------------------------------------------------------------
# Two staging tables that keep a well-list source traceable down to the row.
#
# NVGEOWEL_Records: hand-transcribed rows of the NBMG "Nevada Geothermal Well Database
#   List - NVGEOWEL - 2009" (Washoe, T17N-T18N, R19E-R20E). Each row records how it was
#   matched to the 2019 NBMG compilation (NBMG_Compilation_Records) and to Wells, and
#   which Wells row, if any, it created.
# NDWR_WellLog_Index: rows of the NDWR Well Log Query (tools.water.nv.gov) for Washoe
#   T18N R20E Section 27, loaded from the basin table already on disk. NDWR lat/lon are
#   PLSS/parcel-assigned, so many logs share one coordinate.
# Both carry source_id -> Data_Sources.
# ------------------------------------------------------------
library(DBI)
if (!exists("con")) stop("Database connection `con` not found. Run via run_pipeline.R.")

dbExecute(con, "
CREATE TABLE IF NOT EXISTS NVGEOWEL_Records (
  record_id INTEGER PRIMARY KEY,
  source_id INTEGER REFERENCES Data_Sources(source_id),
  screenshot TEXT,
  twn TEXT, rng TEXT, sec TEXT, qtrqtr TEXT, county TEXT, permit TEXT,
  operator TEXT, well_name TEXT, date_text TEXT, status_class TEXT, td_ft REAL, remarks TEXT,
  match_method TEXT,
  nbmg_record_id INTEGER REFERENCES NBMG_Compilation_Records(record_id),
  matched_well_id INTEGER REFERENCES Wells(well_id),
  disposition TEXT,
  loaded_well_id INTEGER REFERENCES Wells(well_id),
  flags TEXT,
  row_hash TEXT
)")
dbExecute(con, "CREATE UNIQUE INDEX IF NOT EXISTS idx_nvgeowel_key
  ON NVGEOWEL_Records (COALESCE(twn,''), COALESCE(rng,''), COALESCE(sec,''), COALESCE(permit,''), COALESCE(well_name,''), COALESCE(date_text,''), COALESCE(td_ft,-1))")

dbExecute(con, "
CREATE TABLE IF NOT EXISTS NDWR_WellLog_Index (
  index_id INTEGER PRIMARY KEY,
  source_id INTEGER REFERENCES Data_Sources(source_id),
  basin TEXT, log_number TEXT, county TEXT, twn TEXT, rng TEXT, sec TEXT, qtrqtr TEXT,
  owner TEXT, comp_date TEXT, driller_license TEXT, driller_name TEXT,
  drill_depth_ft REAL, static_water_level_ft REAL, casing_diameter_in REAL,
  work_type_code TEXT, work_type TEXT, proposed_use_code TEXT, proposed_use TEXT, permit TEXT,
  latitude REAL, longitude REAL,
  coord_shared_by INTEGER,
  disposition TEXT,
  loaded_well_id INTEGER REFERENCES Wells(well_id),
  note TEXT
)")
dbExecute(con, "CREATE UNIQUE INDEX IF NOT EXISTS idx_ndwr_index_log ON NDWR_WellLog_Index (log_number)")
message("[SCHEMA] NVGEOWEL_Records and NDWR_WellLog_Index ready.")
