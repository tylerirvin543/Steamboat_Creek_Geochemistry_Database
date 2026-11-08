# scripts/leapfrog/

Exports this project's well data into Leapfrog Geo's plain-CSV input
format (collar / survey / interval tables), for building a 3D geologic
model of the Steamboat field. Entirely optional and read-only against
the database (no ingestion, no schema writes) -- see README.md's
"Planned: Leapfrog 3D geologic model export" section for the full
design rationale and open decisions.

| Script | What it does |
|---|---|
| `export_leapfrog.R` | `export_leapfrog(con, out_dir = ...)` -- writes `collar.csv` (UTM Zone 11N / EPSG:26911, matching this project's other UTM-based exports), `survey.csv` (a real deviation survey from `Well_Deviation_Surveys` when one exists, e.g. well 83C-6ST1; an assumed-vertical two-point trace otherwise -- flagged per-well, never silently assumed), `interval.csv` (completion/perforation interval, explicitly labeled as *not* lithology), and `lithology.csv` (only `well_id`-confirmed `Well_Lithology` rows -- candidate/pending rows are excluded, never guessed into the export). Wired into `run_pipeline.R` as `RUN_ANALYSIS$leapfrog_export` (default `FALSE`). |

Real fault traces and alteration zones are a separate, not-yet-built
extension -- see `database/schema/11_fault_traces_schema.R` and
`scripts/ingest/ingest_fault_traces.R` (structure-only, waiting on a
digitized shapefile) and `docs/action_items_for_user.md` for the
current status.

## Chemistry and water-level tables (2026-10-29)

`export_leapfrog_chemistry.R` -> `export_leapfrog_chemistry_intervals(con)` writes, to `output/leapfrog/`:

| File | Content |
|---|---|
| `chemistry_intervals_long.csv` | HoleID, From, To (m), Analyte (Cl, Na, SO4, B, Temperature), Value, Units, SampleDate, Source, IntervalBasis, InCollar |
| `chemistry_intervals_latest.csv` | most recent value per hole and analyte (easiest to colour logs) |
| `chemistry_unplaced.csv` | chemistry at wells with no screen interval and no total depth |
| `water_levels.csv` | Steamboat-area collar-ready wells; dense logger series reduced to monthly means |

`IntervalBasis` is `screen` (top/bottom perforation known) or `open_to_total_depth_assumed` (whole hole used, flagged because the sampled depth is not documented). Only holes with `InCollar = TRUE` also appear in `collar.csv`; many older wells lack an elevation and cannot be placed in 3D until one is added. Chemistry is linked through `Wells.location_id`; missing exact-name links are in `data/raw/wells/well_location_links.csv` (fill-only). Runs inside `RUN_ANALYSIS$leapfrog_export`.

## Coordinates, Z and the DEM (2026-11-07)

- **One CRS.** Every X/Y in `output/leapfrog/` is NAD83 / UTM zone 11N (EPSG:26911), metres. `CRS_README.txt` in that folder lists each file. The only geographic coordinates are in `collar_incomplete.csv` (reference only, not for import). The Skalbeck `UTM_E`/`UTM_N` were checked against their stored latitude/longitude and are NAD83 zone 11N to within 1e-8 m.
- **Z comes from the DEM.** `dem_helpers.R` samples the 1 m USGS 3DEP DEM (all tiles in `data/raw/dem/`, mosaicked) at each feature's current X, Y at export time: collars, faults, fissures, polygon vertices, location points, Skalbeck horizons and grid. Because Z is computed at export, a feature that moves gets a new Z on the next export with no extra step. `collar.csv` keeps `Z_Reported` (the stored elevation) and `Z_Source` ('DEM' or 'stored elevation (outside DEM)') beside Z.
- **Stored elevations.** `refresh_dem_elevations(con)` keeps `Wells.elevation_m` in step with the DEM when the value was itself derived from a DEM or 3DEP query (or is empty) and the coordinate now gives a value more than 0.5 m different; elevations from permits or literature are never overwritten, but any that differ from the DEM by more than 10 m are listed in `data/derived/dem_elevation_discrepancies.csv` (30 at present; the largest is 83B-6R, 505 m). It also fills empty `Locations.elevation_m`.
- **New files.** `export_leapfrog_structure.R` writes `fault_traces.csv`, `fissure_traces.csv`, `mapped_polygons.csv`, `locations_points.csv`, `topography_dem_5m.tif` and 3-D shapefiles in `gis/` (`faults_3d`, `fissures_3d`, `mapped_polygons_3d`, `locations_3d`, all with Z).
