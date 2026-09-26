# `data/raw/arcgis/` — User-Digitized ArcGIS Shapefiles

## What this is

Shapefiles the user digitizes directly in ArcGIS by overlaying satellite
imagery and/or a published figure (e.g. the Dhakal et al. 2025 flow
diagram, or Collar & Huntley 1990's fault map) — this project's first
genuinely spatial (non-tabular) raw-data source. The
`dhakal .shp/` folder name has a literal space in it (kept as the user
created it; don't "fix" it, ingest scripts reference the exact path).

## Current contents

- **`dhakal .shp/Steamboat_wells_dhakal.shp`** — 12+ well points
  digitized from the Dhakal et al. (2025) production/injection-well
  flow diagram, cross-validated against independently-sourced NBMG
  coordinates for two wells (44/40 m agreement) before being trusted
  for the rest. Ingested by `register_well_coordinates.R` via
  `data/raw/wells/dhakal_wells_arcgis.csv` (the point coordinates were
  extracted from the shapefile and written to that CSV in an earlier
  session — the shapefile itself is not re-read on every pipeline run).
- **`dhakal .shp/Steamboat_power_plant_locations.shp`** — 5 power-plant/
  pad footprint polygons (`Powerplant` attribute: `G1`/`G2`/`G3`/`SBHR`/
  `SB2/3`), source CRS EPSG:3857 (WGS84/Pseudo-Mercator). Ingested by
  `scripts/ingest/register_facility_areas.R` into `Facility_Areas`,
  reprojected to EPSG:4326; each polygon's centroid also fills the
  corresponding `Sampling_Ports` row's coordinate.

## Planned: `faults/` subfolder

`scripts/ingest/ingest_fault_traces.R` is built and wired into
`run_pipeline.R` (`RUN_INGEST$fault_traces`) but currently a no-op —
no fault/lineament shapefile has been digitized yet. When you digitize
fault traces in ArcGIS (Collar & Huntley 1990 Figure 1 is the current
best candidate source — a real fault-and-lineament map with several
already-coordinated wells visible on it for control, per
`notebooks/07_historical_context_sorey1992.qmd` Section 4.6), save the
resulting line shapefile under `data/raw/arcgis/faults/` and re-run the
pipeline (or call `ingest_fault_traces(con, source_citation = "Collar &
Huntley 1990, Figure 1")` directly) — see that script's own header
comment for the expected attribute columns (a name/label field and,
optionally, a fault-type field).

## Ingestion behavior

Both `register_well_coordinates()` and `register_facility_areas()`
(and, once used, `ingest_fault_traces()`) read the shapefile directly
with `sf::st_read()`, reproject to EPSG:4326 regardless of source CRS,
and are idempotent (matched on well/facility/fault name — an existing
row is never overwritten).

## Known limitations

- No fault traces exist yet — this is the single biggest blocker to
  any spatial confining-layer/structural analysis in this project
  (see `notebooks/07`'s Section 6/discussion).
- The `SB2/3` combined polygon can't be split into two independent
  centroids — both `SB2` and `SB3` `Sampling_Ports` rows get the exact
  same approximate coordinate, an explicit, documented approximation
  (`coordinate_uncertainty_m = 150`).
