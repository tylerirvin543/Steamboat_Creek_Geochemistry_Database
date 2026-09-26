Data Ingestion Workflow
================

## Philosophy

- Ingest scripts read raw files and write to the database
- No manual edits are made to raw data
- All joins use explicit identifiers (never names) where an identifier
  exists; where a source only has a name (e.g. NDWR owner names, NDEP
  station names), a human-maintained mapping CSV is required before
  promotion – no script guesses an identity match on its own
- Scripts are safe to re-run (idempotent where possible) – every adapter
  below either has a real dedup/anti-join step or documents why it
  doesn’t need one
- `register_*.R`/`promote_*.R` scripts are a distinct category from
  `ingest_*.R`: they apply a *human-confirmed* mapping (a CSV someone
  filled in) rather than auto-detecting an identity from raw data alone

## Overview

This folder contains every script that ingests raw data into the SQLite
database, plus the GIS-export and view-creation scripts that run right
after ingestion. Grouped below by what kind of source they read.

### Core field/lab/isotope chemistry

| Script | Reads | Notes |
|----|----|----|
| `ingest_field.R` | `data/raw/field/*.xlsx` | Field sampling metadata (locations, sampling events, samples, field measurements) – the largest/oldest ingest script. |
| `ingest_lab.R` | `data/raw/lab/*.csv` | Normalized long-format lab chemistry (major ions, trace elements, alkalinity). `normalize_lab_wide()` preserves original (pre-`make.names()`) header text so multi-word `lab_analyte_map.R` raw names still match. |
| `ingest_isotopes.R` | `data/raw/isotopes/*.csv` | Delta-18O/delta-D isotope analyses. |
| `ingest_flux.R` | `data/raw/discharge/stream_discharge.xlsx` | Transect-based stream discharge/flux measurements. |

### External agency sources

| Script | Reads | Notes |
|----|----|----|
| `ingest_ndep.R` | `data/raw/ndep/NormalizedData.csv` | NDEP production-well chemistry (public record request). Pulls pH/temperature from both `Lab_Analyses` and `Field_Measurements`; converts mixed-unit minor/trace analytes to mg/L before aggregation; `Alkalinity` stored on a consistent HCO3-mass basis via `conversion_factor`. |
| `ingest_ndep_prr.R` + `promote_staged_ndep.R` | `data/raw/ndep/PRR/*/*.pdf` | NDEP Public Records Request PDFs -\> `Staging_NDEP_WQ` (raw parse) -\> promoted into core tables only after `staged_ndep_location_map.csv` confirms a station’s identity/coordinate. |
| `ingest_ndwr.R` | `data/raw/ndwr/*_WellLogQuery_..._files/sheet001.htm` | NDWR well-log index (an HTML table inside a mislabeled `.xls` “Web Page, Filtered” export – parse with `rvest::html_table()`, not `readxl`). Converts elevation feet-\>meters at insert time for both `Wells` and `Locations`. |
| `ingest_ndwr_stream_flow.R` | `data/raw/ndwr/TM_Spring_Stream_Flowdata_*_files/*.xlsx` | Daily manual creek discharge (cfs) at gauged NDWR sites -\> `Stream_Flow_Observations`. |
| `ingest_ndom_wells.R` | `data/raw/ndom/*.xlsx` | Nevada Division of Minerals official well-permit records (UTM coordinates, API/permit numbers, well type/status) – cross-validates and gap-fills `Wells`, never overwrites an existing field. |
| `ingest_usgs.R` | USGS NWIS web service | Live discharge/water-level/temperature time series. |
| `ingest_usgsmeta.R` | USGS NWIS site metadata | Station metadata backing `ingest_usgs.R`. |
| `ingest_usgs_historic_chemistry.R` | `data/raw/usgs/fullphyschem_station_download/*.csv` | Historic USGS WQP grab-sample specific conductance, stored in the same tables as live discharge for a one-line join. |
| `ingest_noaa_weather.R` | `data/raw/noaa/*.csv` | NOAA daily weather, two auto-detected formats (NCEI order export / GHCN daily summary). |
| `ingest_barometric_pressure.R` | `data/raw/airpressure/*` | Hourly IEM ASOS barometric pressure for Reno Airport, reusing the existing `Weather_Observations`/`Weather_Stations` tables (`parameter='MSLP'`). Backs the real barometric-efficiency analysis in `barometric_efficiency.R`. |
| `ingest_earthquakes.R` | USGS FDSN Event Web Service (live query) | Regional earthquake catalog, pre-computes distance to the Steamboat field center. |

### Loggers and sensors

| Script | Reads | Notes |
|----|----|----|
| `ingest_temperature_loggers.R` | `data/raw/loggers/*` (Elitech exports) | Deployment metadata + time-series observations. |
| `ingest_conductivity.R` | `data/raw/conductivity/*` (HOBO/Onset exports) | Stream EC/temperature loggers backing the Cl-sampling-frequency workstream; computes specific conductance @ 25C. |

### Wells, well-log PDFs, and the flow network

| Script | Reads | Notes |
|----|----|----|
| `ingest_well_logs.R` | `data/raw/ndwr/Ormat_well_logs/*.pdf` | NDWR driller’s-report PDFs -\> OCR (tesseract, project-local cache) + NDWR-log-number cross-reference -\> `Well_Log_Documents`/`Well_Lithology`/`Well_Work_Events`. Also has `register_provisional_well_logs()` (visible-but-unconfirmed `Wells` rows) and `promote_well_log_documents()` (human-confirmed identity via `data/raw/ndwr/well_log_document_map.csv`). |
| `ingest_historical.R` / `ingest_historical_sorey1992.R` | `data/raw/historical/*.csv` | Historical (pre-1992 and general) chemistry/monitoring-site data mined from literature, registered as provisional/resolved `Wells`/`Locations` rows via human-maintained mapping CSVs. |
| `ingest_mariner_janik_1995.R` | literature-derived CSVs | Mariner & Janik (1995) gas/water chemistry, used for the D’Amore-Panichi gas-geothermometer validation. |
| `ingest_fault_traces.R` | `data/raw/arcgis/faults/*.shp` | Reads digitized fault/lineament traces into `Fault_Traces`/`Alteration_Zones`. Currently a safe no-op – no shapefile has been digitized yet (see `docs/action_items_for_user.md`). |
| `register_well_network.R` | `data/raw/wells/dhakal_well_network.csv`, `well_aliases.csv` | Human-confirmed production-well -\> port -\> injection-well links (from Dhakal et al. 2025 Figure 5) and well-name aliases. |
| `register_well_coordinates.R` | `data/raw/wells/dhakal_well_coordinates.csv`, `dhakal_wells_arcgis.csv` | Fills `Wells` coordinates from NBMG/ArcGIS-digitized sources, alias-aware, fill-only-if-NULL. |
| `register_facility_areas.R` | `data/raw/arcgis/dhakal .shp/*.shp` | Power-plant-pad polygons -\> `Facility_Areas`, also fills `Sampling_Ports` centroids. |
| `register_monitor_well_locations.R` | `data/raw/ndwr/klein2007_monitor_well_locations.csv` | Klein et al. (2007)-sourced monitor-well coordinates. |

### Photos and locations

| Script | Reads | Notes |
|----|----|----|
| `ingest_image_locations.R` (aka `ingest_photos.R`) | `data/raw/images/image_drop/*` (photos + video), `image_location_map.csv` | EXIF-GPS extraction -\> `Photo_Location_Candidates`; a human-maintained map CSV is the only thing that creates/touches a `Locations` row from a photo. |

### GIS / views (run after ingestion, not ingestion themselves)

| Script | What it does |
|----|----|
| `create_gis_views.R` | GIS-flavored SQL views (`geom_wkt` columns) layered on top of `create_analysis_views.R`’s core views. |
| `export_geopackage.R` | Exports every GIS-ready layer to a `.gpkg` file for ArcGIS. |

### Orchestration

| Script | What it does |
|----|----|
| `update_all_data.R` | Master orchestrator – runs the core ingest scripts in the correct order. For the *full* pipeline (all ~28 sources, analysis, QC, website), use `scripts/run_pipeline.R` at the repo root instead; see the root `README.md`’s “Setup and Running the Pipeline” section for exact console commands. |

## Pre-ingest utilities

### prepare_lab_data.R

Converts raw laboratory outputs (typically wide-format Excel files) into
standardized long-format CSVs suitable for database ingestion.

- Reads from: `data/raw/lab/`
- Writes to: `data/processed/lab_normalized/`
- Run manually as needed
- NOT called by `update_all_data.R`

The resulting CSVs are then ingested by `ingest_lab.R`.

## Run Order

``` r
source("scripts/ingest/ingest_ndep.R")
source("scripts/ingest/ingest_field.R")
source("scripts/ingest/ingest_lab.R")
source("scripts/ingest/ingest_temperature_loggers.R")
```

Or, for the small “core chemistry” subset above:

``` r
source("scripts/ingest/update_all_data.R")
```

Or, for everything (recommended – see the root README for the full
console-command reference):

``` r
source("scripts/run_pipeline.R")
```

## Validation & Errors

- Invalid parameter names halt ingestion for that source
- Missing sample codes halt ingestion for that source
- No database writes occur if validation fails
- Templates are not wiped on failure
- Since Session 19, a failure in one `run_pipeline.R`-orchestrated
  ingestion stage is caught, logged (`[ERROR] <name> failed: ...`), and
  the pipeline continues to the next stage rather than hard-stopping –
  check the end-of-run PIPELINE SUMMARY table for any stage marked
  FAILED

Error messages indicate: which file, which column, which row(s).

## Archiving

Raw Excel inputs (the original field/lab template workflow) are archived
to `data/processed/*_archive/YYYYMMDD_HHMM/`. Nothing is ever lost or
overwritten. Most newer sources (NDEP, NDOM, NDWR, NBMG, USGS, NOAA,
well-log PDFs, ArcGIS shapefiles) are read directly from `data/raw/`
without a separate archive step, since they arrive as complete,
already-dated files rather than a template that gets refilled.

### Template Lifecycle (field data-entry templates specifically)

- `locations.xlsx`: persistent reference, not wiped
- `sampling_events.xlsx`: archived and cleared after ingest
- `samples.xlsx`: archived and cleared after ingest
- `field_measurements.xlsx`: archived and cleared after ingest

Templates are cleared only after successful ingest.

## After Ingestion

After ingestion completes successfully (via `run_pipeline.R`):

- QC checks run automatically (`scripts/qc/`, see that folder’s README)
- Analysis views/derived products build automatically
- The website and GeoPackage export run if requested
