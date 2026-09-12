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

# ------------------------------------------------------------
# ADDITIVE MIGRATION (2026-09-12, session 24): larger NDWR/ArcGIS
# well-log batch (64 log numbers, many with a second "(2)"
# reformatted/streamlined scan per log number). New capability added:
#   - PLSS (Section/Township/Range) extraction, used as lat/lon
#     fallback level 4 (see parse_well_log_pdf.R's
#     .convert_plss_to_latlon(), backed by BLM's public PLSS
#     CadNSDI ArcGIS REST service -- confirmed reachable and correct
#     against a known ground-truth point, section 2 T17N R19E
#     correctly contains the real Shonnard well coordinate, before
#     this was relied on).
#   - Type of work (new/deepening/abandonment/etc.), proposed use,
#     and hole/casing diameter -- lets a 1" piezometer be told apart
#     from a full-scale geothermal production well, and lets a
#     well's status be tracked as it changes over time (new
#     Well_Work_Events table below), not just captured once.
#   - A second source file per log number (the "(2)" scan) is tracked
#     alongside the primary one rather than as a separate document.
# ------------------------------------------------------------

doc_cols <- dbListFields(con, "Well_Log_Documents")
new_doc_cols <- list(
  alt_file_path = "TEXT",
  alt_file_hash = "TEXT",
  alt_has_text_layer = "INTEGER DEFAULT 0",
  section = "TEXT",
  township = "TEXT",
  range = "TEXT",
  plss_latlon_method = "TEXT",
  work_type = "TEXT",
  proposed_use = "TEXT",
  hole_diameter_in = "REAL",
  casing_diameter_in = "REAL",
  source_batch = "TEXT",
  duplicate_of_document_id = "INTEGER"
)
for (col in names(new_doc_cols)) {
  if (!col %in% doc_cols) {
    message("[MIGRATION] Well_Log_Documents.", col, " missing -- adding.")
    dbExecute(con, paste0("ALTER TABLE Well_Log_Documents ADD COLUMN ", col, " ", new_doc_cols[[col]]))
  }
}

wells_cols_07 <- dbListFields(con, "Wells")
if (!"diameter_in" %in% wells_cols_07) {
  message("[MIGRATION] Wells.diameter_in missing -- adding.")
  dbExecute(con, "ALTER TABLE Wells ADD COLUMN diameter_in REAL")
}

# Well_Lithology.well_id was originally NOT NULL, on the assumption
# lithology would only ever be written after a document is promoted to
# a confirmed well. Session 24 changed this: lithology is now staged
# at INGEST time (well_id still unknown), same staging-first posture
# as everything else in this table, then backfilled with the real
# well_id once promote_well_log_documents()/register_provisional_well_
# logs() resolves an identity. SQLite can't drop a NOT NULL constraint
# via ALTER TABLE, so this rebuilds the table (safe either way -- it
# preserves any existing rows).
lith_info <- dbGetQuery(con, "PRAGMA table_info(Well_Lithology)")
well_id_notnull <- lith_info$notnull[lith_info$name == "well_id"]
if (length(well_id_notnull) == 1 && well_id_notnull == 1) {
  message("[MIGRATION] Well_Lithology.well_id is NOT NULL -- rebuilding table to allow NULL (staging before a well is identified).")
  dbExecute(con, "ALTER TABLE Well_Lithology RENAME TO Well_Lithology_old_notnull")
  dbExecute(con, "
    CREATE TABLE Well_Lithology (
      lithology_id INTEGER PRIMARY KEY,
      well_id INTEGER,
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
  dbExecute(con, "
    INSERT INTO Well_Lithology (lithology_id, well_id, depth_from_ft, depth_to_ft, description, units, source_document_id, notes)
    SELECT lithology_id, well_id, depth_from_ft, depth_to_ft, description, units, source_document_id, notes FROM Well_Lithology_old_notnull
  ")
  dbExecute(con, "DROP TABLE Well_Lithology_old_notnull")
}

# Well_Work_Events: one row per well-log document that reports a type
# of work, so a well's status history (new -> deepened -> abandoned,
# etc.) is a real, queryable time series instead of a single Wells
# snapshot. Deliberately keyed to source_document_id (not just
# well_id) so every report stays traceable to its source PDF.
dbExecute(con, "
CREATE TABLE IF NOT EXISTS Well_Work_Events (
  event_id INTEGER PRIMARY KEY,
  well_id INTEGER NOT NULL,
  source_document_id INTEGER,
  work_type TEXT,              -- 'new' | 'deepening' | 'reconstruction' | 'repair' | 'abandonment' | 'change_of_use' | 'other' | NULL
  proposed_use TEXT,
  event_date TEXT,             -- completion date of the report describing this event, NULL if unparseable (never guessed)
  hole_diameter_in REAL,
  casing_diameter_in REAL,
  notes TEXT,
  FOREIGN KEY (well_id) REFERENCES Wells(well_id),
  FOREIGN KEY (source_document_id) REFERENCES Well_Log_Documents(document_id)
);
")
dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_well_work_events_well ON Well_Work_Events(well_id, event_date)")

message("[SCHEMA] Well logs schema ready (Well_Log_Documents, Well_Lithology, Well_Work_Events).")
