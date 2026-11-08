#29_nbmg_compilation_schema
# ------------------------------------------------------------
# Staging table for the NBMG statewide well/permit compilation
# (data/raw/nbmg/GEOTHERM06102019.csv), Steamboat-area rows only. Every in-scope
# source row is kept verbatim (src_* columns), including expired / not-drilled
# permits and project-area rows, which are never turned into Wells rows
# (permit_only = 1). row_hash lets a changed source row be noticed.
# ------------------------------------------------------------
library(DBI)
if (!exists("con")) stop("Database connection `con` not found. Run via run_pipeline.R.")

dbExecute(con, "
CREATE TABLE IF NOT EXISTS NBMG_Compilation_Records (
  record_id INTEGER PRIMARY KEY,
  src_api TEXT, src_conf TEXT, src_county TEXT, src_kgra TEXT, src_permit TEXT, src_file_no TEXT,
  src_operator TEXT, src_well TEXT, src_s TEXT, src_t TEXT, src_r TEXT, src_partsect TEXT,
  src_distfromli TEXT, src_permit_iss TEXT, src_spud_date TEXT, src_compl_date TEXT,
  src_status TEXT, src_class TEXT, src_td TEXT, src_elevation TEXT, src_tops TEXT,
  src_analyses TEXT, src_logs TEXT, src_samples TEXT, src_depth_temp TEXT, src_remarks TEXT,
  src_utmn TEXT, src_utme TEXT, src_nad TEXT, src_zone TEXT,
  scope TEXT,                  -- steamboat_kgra | box_context_only
  utm_crs TEXT, latitude REAL, longitude REAL,   -- converted per the row's own datum
  match_method TEXT, n_candidates INTEGER, matched_well_id INTEGER REFERENCES Wells(well_id),
  review_flag TEXT,            -- ok | flag_distance_100_200m | HOLD_* | no_match
  distance_m REAL,
  permit_only INTEGER DEFAULT 0,
  disposition TEXT,            -- created_well | filled_existing | held_probable | staging_only_permit | staging_only_context | no_action
  loaded_well_id INTEGER REFERENCES Wells(well_id),
  row_hash TEXT
)")
dbExecute(con, "CREATE UNIQUE INDEX IF NOT EXISTS idx_nbmg_comp_key
  ON NBMG_Compilation_Records (COALESCE(src_api,''), COALESCE(src_permit,''), COALESCE(src_well,''))")
