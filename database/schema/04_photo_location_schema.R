# ------------------------------------------------------------
# 04_photo_location_schema.R
#
# Purpose:
# Support the exiftool-based photo-GPS location workflow
# (scripts/ingest/ingest_image_locations.R). Extends (does not
# replace) the core schema; sourced after 01_define_schema.R.
#
# Design:
# - Photo_Location_Candidates: raw, append-only EXIF GPS extraction
#   per photo filename -- exiftool output, never hand-edited. This is
#   the automatic half of the workflow.
# - Photo_Location_QC: whenever a mapped photo's GPS lands on an
#   *already-registered* location, the photo-derived coordinate is
#   compared to the registered one and logged here rather than
#   silently overwriting curated coordinates -- this is what would
#   have caught the SBF_0001/IMG_4571 duplicate-coordinate mixup
#   automatically instead of requiring a manual check.
# - New Locations are only ever created from a *human-confirmed*
#   filename -> external_station_code mapping
#   (data/raw/images/image_location_map.csv, not a DB table -- see
#   ingest_image_locations.R), never automatically from GPS alone.
# ------------------------------------------------------------

dbExecute(con, "
CREATE TABLE IF NOT EXISTS Photo_Location_Candidates (
  filename TEXT PRIMARY KEY,
  gps_lat REAL,
  gps_lon REAL,
  gps_alt_m REAL,
  taken_at TEXT,
  source_dir TEXT,
  ingested_at TEXT
);
")

dbExecute(con, "
CREATE TABLE IF NOT EXISTS Photo_Location_QC (
  qc_id INTEGER PRIMARY KEY,
  filename TEXT,
  external_station_code TEXT,
  registered_lat REAL,
  registered_lon REAL,
  photo_lat REAL,
  photo_lon REAL,
  distance_m REAL,
  flagged_at TEXT
);
")

# ------------------------------------------------------------
# MIGRATION: Photo_Location_Candidates.gps_h_accuracy_m
#
# Records the EXIF GPSHPositioningError tag (device-reported horizontal
# accuracy, meters) when present, so downstream consumers of a photo-
# derived coordinate know how much to trust it -- see the
# coordinate_source/coordinate_uncertainty_m migration on Locations
# below and notebooks/04_photo_location_workflow.qmd for the reasoning.
# ------------------------------------------------------------
photo_cand_cols <- dbListFields(con, "Photo_Location_Candidates")
if (!"gps_h_accuracy_m" %in% photo_cand_cols) {
  dbExecute(con, "ALTER TABLE Photo_Location_Candidates ADD COLUMN gps_h_accuracy_m REAL")
}

# ------------------------------------------------------------
# MIGRATION: Locations.coordinate_source / coordinate_uncertainty_m
#
# Not every Locations row has the same positional confidence -- a
# surveyed point, a digitized map point, and a phone-photo GPS fix are
# not equally precise, but until now nothing recorded which was which.
# Additive, backfills nothing for existing rows (NULL = unknown/legacy,
# not "surveyed"), so this is a no-op for rows that already have a
# real coordinate provenance recorded some other way.
# ------------------------------------------------------------
loc_cols_photo <- dbListFields(con, "Locations")
if (!"coordinate_source" %in% loc_cols_photo) {
  dbExecute(con, "ALTER TABLE Locations ADD COLUMN coordinate_source TEXT")
}
if (!"coordinate_uncertainty_m" %in% loc_cols_photo) {
  dbExecute(con, "ALTER TABLE Locations ADD COLUMN coordinate_uncertainty_m REAL")
}

# ------------------------------------------------------------
# Field_Observations: qualitative, timestamped field notes tied to a
# location and (optionally) a sample -- distinct from Field_Measurements,
# which requires a numeric value. Lets a field photo record *what was
# seen or done* there ("new seep, no sample taken"; "collected FA/FU
# splits"), not just *where* -- see ingest_image_locations.R's optional
# image_location_map.csv columns (observation_note,
# linked_external_sample_id).
# ------------------------------------------------------------
dbExecute(con, "
CREATE TABLE IF NOT EXISTS Field_Observations (
  observation_id INTEGER PRIMARY KEY,
  location_id INTEGER NOT NULL,
  sample_id INTEGER,
  observed_at TEXT,
  observer TEXT,
  note TEXT,
  source_photo_filename TEXT,
  FOREIGN KEY (location_id) REFERENCES Locations(location_id),
  FOREIGN KEY (sample_id) REFERENCES Samples(sample_id)
);
")
