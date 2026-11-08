#27_digitized_features_schema
# ------------------------------------------------------------
# User-digitized surface features from ArcGIS that are not faults:
#   Fissure_Traces   : fissure lines on the Lower Sinter Terrace (LINESTRING, EPSG:4326)
#   Mapped_Polygons  : sinter mounds, sinter ridges, the sinter terrace outline and the
#                      study-area rectangle (POLYGON/MULTIPOLYGON, EPSG:4326)
# Geometry is stored 2-D; Z is taken from the DEM at export time, so it follows the
# geometry if a feature is moved (see scripts/leapfrog/dem_helpers.R).
# source_layer is the layer in the ArcGIS project; the ingest treats each source layer as
# authoritative and replaces its rows when the layer's features change.
# ------------------------------------------------------------
library(DBI)
if (!exists("con")) stop("Database connection `con` not found. Run via run_pipeline.R.")

dbExecute(con, "
CREATE TABLE IF NOT EXISTS Fissure_Traces (
  fissure_id INTEGER PRIMARY KEY,
  fissure_name TEXT,
  orig_name TEXT,
  status_label TEXT,            -- as labelled in the source layer name ('closed'); meaning to be confirmed
  geom_wkt TEXT NOT NULL,       -- LINESTRING/MULTILINESTRING, EPSG:4326
  length_m REAL,
  digitizing_uncertainty_m REAL,
  source_layer TEXT,
  feature_key TEXT UNIQUE,
  source TEXT,
  notes TEXT
)")
dbExecute(con, "
CREATE TABLE IF NOT EXISTS Mapped_Polygons (
  polygon_id INTEGER PRIMARY KEY,
  feature_type TEXT NOT NULL,   -- sinter_mound, sinter_ridge, sinter_terrace_outline, study_area
  polygon_name TEXT,
  orig_name TEXT,
  geom_wkt TEXT NOT NULL,       -- POLYGON/MULTIPOLYGON, EPSG:4326
  area_m2 REAL,
  digitizing_uncertainty_m REAL,
  source_layer TEXT,
  feature_key TEXT UNIQUE,
  source TEXT,
  notes TEXT
)")
