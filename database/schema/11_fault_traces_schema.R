#11_fault_traces_schema
# ------------------------------------------------------------
# Additive schema extension for digitized fault traces and (eventually)
# alteration zones -- the structural inputs a future Leapfrog 3D
# geologic model needs alongside the well collar/survey/completion-
# interval data (scripts/leapfrog/export_leapfrog.R). Scoped in
# README.md ("Planned: Leapfrog 3D geologic model export", 2026-09-12)
# and built out (structure-only, no real digitized data yet) this
# session.
#
# Design mirrors 06_facility_areas_schema.R's polygon pattern exactly,
# just for line (fault) and, later, polygon (alteration) geometry:
#   Fault_Traces      -> one row per digitized fault/lineament,
#                        geometry as WKT LINESTRING/MULTILINESTRING
#                        text (same convention as Facility_Areas.geom_wkt
#                        and every vw_*_gis view), reprojected to
#                        EPSG:4326 on ingest regardless of source CRS.
#                        fault_type distinguishes a mapped fault from an
#                        air-photo lineament of "probable structural
#                        origin" -- Collar & Huntley (1990) Figure 1
#                        (the current best candidate source, see
#                        notebooks/07_historical_context_sorey1992.qmd
#                        Section 4.6) draws this same distinction and it
#                        should not be collapsed away.
#   Alteration_Zones  -> one row per digitized alteration polygon.
#                        No source has been identified for this yet
#                        (README flags White et al. 1964, PP 458-B, as
#                        an unchecked candidate) -- table exists so the
#                        capability is ready the moment one is found,
#                        consistent with this project's standing "build
#                        the capability, wait for real data" pattern
#                        (already used for PHREEQC mixing/inverse).
#
# NOT populated by this migration -- ingest_fault_traces.R (planned,
# not yet built) would read a user-digitized shapefile/GeoJSON the same
# way register_facility_areas.R reads Facility_Areas' source shapefile.
# ------------------------------------------------------------

library(DBI)
library(RSQLite)

if (!exists("con")) {
  stop("Database connection `con` not found. Run via run_pipeline.R.")
}

dbExecute(con, "PRAGMA foreign_keys = ON;")

# -----------------------
# FAULT TRACES (lines)
# -----------------------
dbExecute(con, "
CREATE TABLE IF NOT EXISTS Fault_Traces (
  fault_id INTEGER PRIMARY KEY,
  fault_name TEXT,
  fault_type TEXT CHECK (
    fault_type IN ('mapped_fault_inferred', 'mapped_fault_concealed', 'air_photo_lineament', 'unknown')
  ) DEFAULT 'unknown',
  geom_wkt TEXT NOT NULL,        -- LINESTRING/MULTILINESTRING, EPSG:4326
  crs TEXT DEFAULT 'EPSG:4326',
  digitizing_uncertainty_m REAL, -- e.g. 800 m for a PLSS-scale source, or a
                                  -- stated accuracy like of00-037's own
                                  -- '0.8 km' precedent -- never left implicit
  source TEXT,
  notes TEXT
);
")

# -----------------------
# ALTERATION ZONES (polygons) -- structure only, no source identified yet
# -----------------------
dbExecute(con, "
CREATE TABLE IF NOT EXISTS Alteration_Zones (
  alteration_zone_id INTEGER PRIMARY KEY,
  zone_name TEXT,
  alteration_type TEXT,          -- e.g. 'argillic', 'silicification' -- free text
                                  -- until a real source dictates a fixed vocabulary
  geom_wkt TEXT NOT NULL,        -- POLYGON/MULTIPOLYGON, EPSG:4326
  crs TEXT DEFAULT 'EPSG:4326',
  digitizing_uncertainty_m REAL,
  source TEXT,
  notes TEXT
);
")

message("[SCHEMA] Fault traces / alteration zones schema ready (Fault_Traces, Alteration_Zones -- both structure-only, no real digitized data yet).")
