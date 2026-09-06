#07_well_logs_schema
# ------------------------------------------------------------
# Additive schema for well-log documents (NDWR "WELL DRILLER'S
# REPORT" PDFs, currently data/raw/ndwr/Ormat_well_logs/) and the
# depth-interval geologic data they carry, aimed at eventually
# supporting 3-D subsurface visualization/modeling.
#
# Deliberately does NOT duplicate what Wells already has:
#   - location (Wells.latitude/longitude)      -- already exists
#   - elevation (Wells.elevation_m)             -- already exists
#   - total depth (Wells.total_depth)           -- already exists
#   - slotted/screened interval
#     (Wells.top_perforation/bottom_perforation) -- already exists
# ingest_well_logs.R fills those existing Wells columns (only when
# NULL, never overwriting) rather than creating parallel ones.
# "Static water level" is a ONE-TIME historical reading, not a
# time series -- it is written into the existing
# Water_Level_Observations table (method_type = 'driller_report')
# rather than a new column, for the same reason.
#
# What's genuinely new here:
#   Well_Log_Documents  -- one row per source PDF processed, tracking
#                          idempotency (file hash), whether it had an
#                          extractable text layer, which well (if any)
#                          it was confidently matched to, and the raw
#                          OCR'd text for human review when automated
#                          extraction isn't trustworthy (e.g. the
#                          lithology table -- see parse_well_log_pdf.R
#                          for why that specific table isn't parsed
#                          automatically).
#   Well_Lithology       -- structured depth-interval geologic
#                          formation data (depth_from/depth_to +
#                          description), one-to-many per well. Left
#                          EMPTY by the automated parser for now
#                          (deliberately -- see above); populated
#                          either by a future OCR-capable session or
#                          by human transcription via
#                          data/raw/ndwr/well_lithology_manual.csv
#                          (same human-in-the-loop CSV pattern used
#                          throughout this project for anything that
#                          can't be safely automated).
# ------------------------------------------------------------

library(DBI)
library(RSQLite)

if (!exists("con")) {
  stop("Database connection `con` not found. Run via run_pipeline.R.")
}

dbExecute(con, "PRAGMA foreign_keys = ON;")

dbExecute(con, "
CREATE TABLE IF NOT EXISTS Well_Log_Documents (
  document_id INTEGER PRIMARY KEY,
  file_path TEXT NOT NULL,
  file_hash TEXT NOT NULL,
  log_number TEXT,
  well_id INTEGER,                 -- NULL until confidently matched to a Wells row
  well_name_parsed TEXT,           -- whatever name the parser/cross-reference found, even if not yet matched to well_id
  has_text_layer INTEGER NOT NULL DEFAULT 0,
  latitude REAL,
  longitude REAL,
  depth_drilled_ft REAL,
  cased_depth_ft REAL,
  static_water_level_ft REAL,
  slot_from_ft REAL,
  slot_to_ft REAL,
  completion_date_raw TEXT,
  match_method TEXT,               -- 'parsed_text' | 'ndwr_log_number_crossref' | 'manual' | NULL
  lithology_raw_text TEXT,         -- verbatim OCR text, for human review; not parsed into intervals
  flags TEXT,                      -- parser/cross-reference caveats, pipe-separated
  processed_at TEXT NOT NULL,
  notes TEXT,
  UNIQUE (file_path, file_hash),
  FOREIGN KEY (well_id) REFERENCES Wells(well_id)
);
")

dbExecute(con, "
CREATE TABLE IF NOT EXISTS Well_Lithology (
  lithology_id INTEGER PRIMARY KEY,
  well_id INTEGER NOT NULL,
  depth_from_ft REAL NOT NULL,
  depth_to_ft REAL NOT NULL,
  description TEXT,
  units TEXT DEFAULT 'ft',
  source_document_id INTEGER,
  notes TEXT,
  FOREIGN KEY (well_id) REFERENCES Wells(well_id),
  FOREIGN KEY (source_document_id) REFERENCES Well_Log_Documents(document_id)
);
")

dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_well_log_docs_well ON Well_Log_Documents(well_id)")
dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_well_lithology_well ON Well_Lithology(well_id)")
dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_well_lithology_depth ON Well_Lithology(well_id, depth_from_ft)")

message("[SCHEMA] Well logs schema ready (Well_Log_Documents, Well_Lithology).")
