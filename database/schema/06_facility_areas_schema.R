#06_facility_areas_schema
# ------------------------------------------------------------
# Additive schema extension for surface-facility footprints (power
# plant / pad polygons), digitized by the user in ArcGIS from
# satellite imagery overlaid on the Dhakal et al. (2025) figure
# (data/raw/arcgis/*.shp). Nothing in the schema before this stored
# polygon geometry -- Locations/Wells/Sampling_Ports are all point-only
# -- so this is a genuinely new geometry class for the project, not
# an extension of an existing table.
#
# Sourced immediately after 01-05 (both at initial connection and
# inside the DEMO reset block in run_pipeline.R).
#
# Design:
#   Facility_Areas       -> one row per digitized polygon, geometry
#                           stored as WKT text (same convention as
#                           Locations.geom / vw_*_gis views: TEXT, not
#                           a native SQLite geometry type), reprojected
#                           to EPSG:4326 on ingest regardless of the
#                           source shapefile's CRS.
#   Sampling_Ports.latitude/longitude/coordinate_source/
#     coordinate_uncertainty_m -> added here (migration) so a port can
#     carry an approximate location derived from its facility
#     polygon's centroid, mirroring the coordinate-provenance pattern
#     already used on Locations and Wells.
#
# Known limitation: the source shapefile's polygon named "SB2/3"
# covers a single combined pad for both the SB2 and SB3
# Sampling_Ports -- there is no way to derive two independent
# centroids from one polygon. register_facility_areas.R (below)
# applies that single centroid to *both* SB2 and SB3, which is a
# genuine approximation (documented in Sampling_Ports.notes at
# registration time), not a precise per-port fix.
# ------------------------------------------------------------

library(DBI)
library(RSQLite)

if (!exists("con")) {
  stop("Database connection `con` not found. Run via run_pipeline.R.")
}

dbExecute(con, "PRAGMA foreign_keys = ON;")

# -----------------------
# FACILITY AREAS (polygons)
# -----------------------
dbExecute(con, "
CREATE TABLE IF NOT EXISTS Facility_Areas (
  facility_area_id INTEGER PRIMARY KEY,
  facility_name TEXT NOT NULL,
  geom_wkt TEXT NOT NULL,        -- POLYGON/MULTIPOLYGON, EPSG:4326
  crs TEXT DEFAULT 'EPSG:4326',
  source TEXT,
  notes TEXT,
  UNIQUE (facility_name)
);
")

# -----------------------
# MIGRATION: Sampling_Ports coordinate provenance
# -----------------------
port_cols <- dbListFields(con, "Sampling_Ports")
if (!"latitude" %in% port_cols) {
  message("[MIGRATION] Sampling_Ports.latitude/longitude/coordinate_source/coordinate_uncertainty_m missing -- adding.")
  dbExecute(con, "ALTER TABLE Sampling_Ports ADD COLUMN latitude REAL")
  dbExecute(con, "ALTER TABLE Sampling_Ports ADD COLUMN longitude REAL")
  dbExecute(con, "ALTER TABLE Sampling_Ports ADD COLUMN coordinate_source TEXT")
  dbExecute(con, "ALTER TABLE Sampling_Ports ADD COLUMN coordinate_uncertainty_m REAL")
}

message("[SCHEMA] Facility areas schema ready (Facility_Areas, Sampling_Ports coordinate columns).")
