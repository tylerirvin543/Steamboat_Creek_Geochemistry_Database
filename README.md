Steamboat Hydrothermal Data Platform
================
Tyler Irvin

- [Overview](#overview)
- [Scientific Context and Purpose](#scientific-context-and-purpose)
- [System Architecture](#system-architecture)
  - [Repository Structure](#repository-structure)
- [ETL Pipeline
  (Extract–Transform–Load)](#etl-pipeline-extracttransformload)
  - [The system implements a structured ETL
    workflow:](#the-system-implements-a-structured-etl-workflow)
- [Raw Data Inputs and User
  Interaction](#raw-data-inputs-and-user-interaction)
  - [How Users Interact with Raw
    Data](#how-users-interact-with-raw-data)
- [Database and Data Model](#database-and-data-model)
- [Analysis Views](#analysis-views)
- [Hydraulic Gradient System](#hydraulic-gradient-system)
- [Script Architecture and Pipeline
  Execution](#script-architecture-and-pipeline-execution)
  - [Documentation by Folder](#documentation-by-folder)
  - [User Data Ingestion](#user-data-ingestion)
- [Database Structure](#database-structure)
  - [Core Tables](#core-tables)
  - [Analysis Layer (Views)](#analysis-layer-views)
  - [Hydrologic Views](#hydrologic-views)
  - [Spatial Views (GIS)](#spatial-views-gis)
- [Quality Control System](#quality-control-system)
  - [QA / QC Framework](#qa--qc-framework)
  - [Outputs](#outputs)
  - [Design Principle](#design-principle)
- [GIS Export and Spatial
  Integration](#gis-export-and-spatial-integration)
- [Future Development](#future-development)
- [Why This System Matters](#why-this-system-matters)
- [Hydraulic Gradient System](#hydraulic-gradient-system-1)
  - [Status: ✅ Implemented](#status-white_check_mark-implemented)
  - [Outputs](#outputs-1)
  - [Scientific Use](#scientific-use)
- [Geochemistry System](#geochemistry-system)
  - [Status: ✅ Implemented
    (initial)](#status-white_check_mark-implemented-initial)
  - [Capabilities](#capabilities-1)
- [Temperature System](#temperature-system)
  - [Status: ✅ Implemented](#status-white_check_mark-implemented-1)
  - [Use](#use)
- [PHREEQC Integration (Next Phase)](#phreeqc-integration-next-phase)
  - [Goal](#goal)
  - [Planned Outputs](#planned-outputs)
  - [Design](#design)
- [Isotope System (Next Phase)](#isotope-system-next-phase)
  - [Planned Integration](#planned-integration)
  - [Purpose](#purpose)
  - [Design Principle](#design-principle-1)
- [Flux System (Planned)](#flux-system-planned)
  - [Future Table](#future-table)
  - [Purpose](#purpose-1)
  - [Troubleshooting and Expected
    Errors](#troubleshooting-and-expected-errors)
  - [Debugging Individual Ingest
    Pipelines](#debugging-individual-ingest-pipelines)
  - [Why This Approach Matters](#why-this-approach-matters)
  - [Link to Github Pages Hosted Website for
    Index.html](#link-to-github-pages-hosted-website-for-indexhtml)
  - [Citation & Reuse](#citation--reuse)

# Overview

This repository implements a **fully reproducible hydrothermal data
platform** for Steamboat Springs, Nevada. It integrates hydrologic,
geochemical, thermal, and (future) isotopic datasets into a single
relational database, enabling consistent analysis of system behavior
through space and time. The system is designed for iterative field
campaigns, regulatory data integration, and research-grade
interpretation workflows, with outputs suitable for both GIS
environments and geochemical modeling platforms such as PHREEQC.

The underlying goal is to transform fragmented environmental
observations into a **coherent, queryable representation of the
hydrothermal system**, where hydraulic state, thermal behavior, and
chemical evolution can be analyzed together.

------------------------------------------------------------------------

# Scientific Context and Purpose

This project addresses a central hydrothermal question:

> **What is the hydraulic, thermal, and geochemical state of the system
> through time and space?**

To support this, the system combines:

- groundwater level data (hydraulic head and gradients)
- geochemical measurements (major ions, field chemistry)
- continuous temperature monitoring
- future isotope tracers and thermodynamic modeling

These datasets collectively enable interpretation of groundwater flow,
fluid mixing, recharge sources, and hydrothermal upflow zones. The
platform is not just a database, but an **analytical framework for
geothermal system characterization**.

------------------------------------------------------------------------

# System Architecture

The system follows a strict layered structure:

**Raw data → Normalized database → Analysis views → Computation →
Export**

Raw datasets are never modified directly. Instead, ingestion scripts
normalize external data into a consistent relational schema. Analysis
views then define reusable, standardized datasets that drive all
computation, modeling, and GIS outputs.

This separation ensures reproducibility and prevents contamination of
raw observations with downstream interpretation.

------------------------------------------------------------------------

## Repository Structure

├── **data/**\_\_\_\_\_\_\_\_\_\_\_# Raw, processed, and derived data  
├── **database/**\_\_\_\_\_\_\_# SQLite database and schema
documentation  
├── **docs/**\_\_\_\_\_\_\_\_\_\_\_# Documentation and Manuscript
storage  
├── **scripts/**\_\_\_\_\_\_\_\_\_# Ingestion, QC, modeling,
visualization  
├── **phreeqc/**\_\_\_\_\_\_\_\_# PHREEQC templates and runs (later
stage)  
├── **docs/**\_\_\_\_\_\_\_\_\_\_\_# Workflow diagrams and methodology  
├── **figures/**\_\_\_\_\_\_\_\_\_# Generated plots and maps  
├── .gitignore  
├── .RData  
├── .Rhistory  
├── index.html\_\_\_\_\_\_\_# Pre-rendered demonstration output  
├── index.Rmd\_\_\_\_\_\_\_# Reproducible demonstration document  
├── README.html\_\_\_\_\_# Pre-rendered Instructional output  
├── README.md\_\_\_\_\_\_\_# Reproducible Instructional document  
└── Steamboat_project.Rproj

------------------------------------------------------------------------

# ETL Pipeline (Extract–Transform–Load)

The platform implements a structured ETL pipeline that converts external
datasets into a unified system.

Extraction pulls data from regulatory sources (NDEP), hydrologic
databases (NDWR), field measurements, and temperature logger files.
Transformation standardizes identifiers, parses timestamps, handles
qualifiers (e.g., detection limits), aligns spatial references through a
shared `coord_key`, and maps analytes into a consistent internal schema.
Loading inserts data into relational tables with strict uniqueness
rules, ensuring idempotent ingest and full provenance tracking via the
`Ingest_Run_Log`.

A critical design decision is that **samples are uniquely identified by
`external_sample_id`**, preserving the integrity of laboratory and
isotope linkages across all datasets.

## The system implements a structured ETL workflow:

### Extract

- NDEP regulatory datasets  
- NDWR wells + water levels  
- field sampling data  
- temperature logger files  
- (future) isotope datasets

------------------------------------------------------------------------

### Transform

- normalization of identifiers (samples, events, stations)
- unit standardization
- parsing of timestamps and qualifiers
- spatial key alignment (`coord_key`)
- analyte mapping (NDEP → internal schema)

------------------------------------------------------------------------

### Load

- insertion into relational SQLite database
- idempotent ingest (no duplicates)
- full provenance tracking via `Ingest_Run_Log`

------------------------------------------------------------------------

# Raw Data Inputs and User Interaction

All external data enter the system through structured files located in:

data/raw/

- Each data source has its own expected format and ingestion pathway.

Data Types The system currently supports:

*NDEP regulatory exports* CSV files (NormalizedData, StationData)
contain chemistry, station metadata, sampling identifiers

*NDWR well and water level data* Excel files (site metadata + water
levels) define well construction and time-series hydrologic data

*Field sampling data* user-generated templates (Excel/CSV) define
samples, field parameters, and metadata

*Temperature logger files* CSV exports from sensors continuous
time-series data

*Laboratory data* (future expansion) structured analyte tables linked
via external_sample_id

*Flux measurements* (planned) discharge / flow measurements from springs
and streams

*USGS historic chemistry* (added 2026-09-05) WQP long-format exports;
stored alongside live USGS discharge in the same `USGS_Timeseries`
table, keyed by parameter code, so both are directly comparable

*NOAA weather* (added 2026-09-05) precipitation/temperature exports;
multiple source formats supported via format auto-detection, not
filename convention

*Field photos* (added 2026-09-05) EXIF GPS extraction via `exiftool`,
paired with a human-confirmed filename-to-site mapping before any
`Locations` row is created or compared

*NDEP Public Records Request documents* (added 2026-09-05, pilot)
PDF lab reports, parsed and staged for review -- distinct from the
open-data NDEP Water Quality Portal source above. Staged rows are
promoted into core chemistry tables only after a human confirms a
location for that station in
`data/raw/ndep/PRR/staged_ndep_location_map.csv`, via the separate
manual step `scripts/ingest/promote_staged_ndep.R` -- as of this
writing, 4 of 13 staged stations (Boyd Dom, Jeppson Dom, Rogers Well,
Soccer Field) have been promoted this way, matched by exact name
against NBMG's statewide "Geothermal_Wells" ArcGIS Open Data layer
rather than guessed or digitized-from-topo-map coordinates

## How Users Interact with Raw Data

Users do not manually insert data into the database. Instead, they:

Place files into the appropriate data/raw/ subdirectory Ensure column
formats match documented expectations Run run_pipeline.R with relevant
ingest flags enabled

### Key Design Principle

Raw data are:

- never modified after ingestion
- archived before processing
- transformed only through scripts

This ensures complete reproducibility and provenance tracking.

# Database and Data Model

The SQLite database is the single source of truth and contains
normalized tables for locations, wells, sampling events, samples,
measurements, and observations. Relationships are enforced through
foreign keys, and uniqueness constraints ensure data integrity without
artificial deduplication.

Hydrologic data are represented through wells and water level
observations, while geochemistry and field measurements link directly to
samples. Temperature data are managed as time-series associated with
deployed loggers. Each dataset connects spatially through the Locations
table and temporally through timestamps or sampling events.

------------------------------------------------------------------------

# Analysis Views

All analysis views are rebuilt on every pipeline run to ensure they
remain consistent with the evolving schema. These views define the
contract between raw data and analysis, and all downstream computation
depends on them.

Hydrologic views compute hydraulic head from depth-to-water measurements
and provide cleaned datasets for interpretation, including time-filtered
and quality-filtered subsets. Spatial views expose geometry and
consistent coordinates for GIS export, while maintaining alignment
through the shared `coord_key`.

Because views are deterministic and recreated each run, they eliminate
the risk of stale or inconsistent derived data.

------------------------------------------------------------------------

# Hydraulic Gradient System

Hydraulic gradients are computed as a derived dataset using spatial
pairing of wells with synchronized measurements. Coordinates are
projected to a metric system, distances are calculated, and head
differences are normalized to produce gradients. Direction and magnitude
are derived for each pair, enabling vector-based representations of
groundwater flow.

The resulting dataset is stored as a table and exported as spatial
vectors, allowing direct visualization in GIS and supporting
interpretation of flow paths, hydraulic structure, and potential upflow
zones.

------------------------------------------------------------------------

# Script Architecture and Pipeline Execution

Script Architecture and How Components Interact The system is
intentionally modular, but all components are coordinated through the
pipeline orchestrator.

Orchestrator `run_pipeline.R`

This script is the entry point and coordinates all stages:

- sets runtime configuration (mode + ingest flags)
- loads schema and helper functions
- runs ingestion scripts conditionally
- triggers analysis, QC, and export stages

It ensures reproducible execution and enforces the correct order of
operations.

------------------------------------------------------------------------

Ingestion Scripts (scripts/ingest/)

Each ingestion script corresponds to a specific data source:

- ingest_ndep.R → regulatory chemistry
- ingest_ndwr.R → wells + water levels
- ingest_field.R → field sampling
- ingest_temperature_loggers.R → sensor time-series

Each script performs:

- parsing of raw files
- normalization of identifiers
- validation of relationships
- insertion into database

Helper scripts support these processes by handling:

- datetime parsing
- spatial alignment (coord_key)
- sample reconstruction and lookup

------------------------------------------------------------------------

Analysis Scripts (scripts/analysis/) These scripts generate derived
datasets from core tables:

- create_analysis_views.R → defines reusable views
- calc_gradients.R → computes hydraulic gradients

Analysis always operates on views, not raw tables, ensuring consistency.

------------------------------------------------------------------------

QC Scripts (scripts/qc/) QC scripts evaluate data integrity across all
systems:

- completeness checks
- range validation
- structural consistency

Outputs include:

- QC summary table
- CSV reports for inspection

------------------------------------------------------------------------

Export Scripts

- create_gis_views.R → prepares spatial views
- export_geopackage.R → writes GIS-ready layers

These scripts convert relational data into formats usable in ArcGIS or
QGIS.

------------------------------------------------------------------------

Key Architectural Principle Each script performs one responsibility
only, but all are orchestrated into a unified pipeline.

All scripts are designed to be both **independently executable for
debugging** and fully integrated within the pipeline.

## Documentation by Folder

Detailed documentation is provided at the folder level to keep this
project-level README concise.

- `database/schema/README.md`  
  Describes the relational schema, table definitions, and design
  rationale.

- `scripts/ingest/README.md`  
  Documents each ingestion pipeline, expected inputs, idempotent
  behavior, and common failure modes.

- `data/raw/README.md`  
  Describes required input formats, column conventions, and validation
  rules for user-edited files.

- `docs/README.md`  
  Contains workflow diagrams, methodology notes, and manuscript drafts.

Users are encouraged to start here, then follow links into
subdirectories for implementation details.

## User Data Ingestion

Users interact with the pipeline primarily through two configuration
blocks defined at the top of `run_pipeline.R`

MODE \<- “DEMO” \# DEMO \| OPERATIONAL

### DEMO Mode (Teaching & Reproducibility)

- Database is rebuilt from scratch
- Regulatory (NDEP) data are ingested automatically
- Deterministic output suitable for instruction and documentation

### OPERATIONAL Mode (Research Use)

- Database persists across sessions

- Schema is created once

- Ingest pipelines are run explicitly

- Protects real field and laboratory data from accidental rebuild

- Activated in `run_pipeline.R` by setting:

  MODE \<- “OPERATIONAL”

### Selective Ingestion

RUN_INGEST \<- list( ndep = TRUE, field = TRUE, logger = TRUE, ndwr =
TRUE, lab = FALSE, flux = FALSE )

Each flag enables or disables a specific ingestion module. This allows
the user to:

run only specific datasets (e.g., just NDWR updates) avoid unnecessary
recomputation debug ingestion pipelines independently integrate new data
sources incrementally

------------------------------------------------------------------------

### Interactive Entry Point

When `run_pipeline.R` is sourced interactively (e.g. in RStudio) with
`MODE`/`RUN_INGEST`/`BUILD_WEBSITE` not already set, it prompts with
`utils::menu()` for the target database, ingestion profile, and whether
to rebuild the website, then proceeds unattended. Non-interactive runs
(`Rscript`, CI) default safely to `MODE = "DEMO"` with all working
sources enabled. Setting any of those three variables before sourcing
the script (as a plain assignment) bypasses the prompts -- this is how
scripted/automated runs should invoke it.

### Manual Confirmation / Promotion Steps

A recurring pattern in this project: automated ingestion **stages**
ambiguous data rather than guessing an identity, and a separate,
human-driven `register_*`/`promote_*` step (each backed by a small,
version-controlled mapping CSV) confirms it before it reaches a core
table. Examples: `promote_staged_ndep.R` (NDEP PRR station name ->
location), `register_monitor_well_locations.R` /
`register_well_coordinates.R` / `register_well_network.R` (well
identity/coordinate/role confirmation), `promote_well_log_documents.R`
(well-log -> named well). These are wired into `run_pipeline.R` as
their own flagged stages precisely so a completed round of manual
confirmation work is never silently lost on a future database rebuild
-- but the mapping CSVs themselves are only ever as complete as a human
has made them; an empty or partial mapping file means "nothing
confirmed yet," not "nothing to confirm."

### Version-Controlling New Raw-Data Files

`data/raw/` is gitignored by default (it can get large and often holds
sensitive/unpublished data), but the small, hand-maintained CSVs that
encode real provenance decisions (the mapping/deployment/coordinate
files referenced throughout this README) are exactly the kind of file
that *should* be tracked. Because git will not evaluate a
per-file `!`-negation inside an already-ignored directory, adding one
of these requires `git add -f <path>` explicitly -- a plain `git add`
or a `!data/raw/whatever.csv` gitignore rule will not pick it up.

# Database Structure

## Core Tables

- Locations  
- Wells  
- Water_Level_Observations  
- Sampling_Events  
- Samples  
- Field_Measurements  
- Lab_Analyses  
- Temperature_Observations  
- Temperature_Loggers  
- Data_Sources  
- Ingest_Run_Log

------------------------------------------------------------------------

## Analysis Layer (Views)

Analysis views are **rebuilt every pipeline run** and act as the
contract between raw data and analysis.

## Hydrologic Views

- `vw_hydraulic_head`
- `vw_hydraulic_head_clean`
- `vw_water_level_latest`
- `vw_water_level_daily_best`

------------------------------------------------------------------------

### Capabilities

- hydraulic head calculation  
- clean time-series extraction  
- well comparison across time

------------------------------------------------------------------------

## Spatial Views (GIS)

- `vw_wells_gis`
- `vw_locations_gis`
- `vw_temperature_timeseries`

These provide:

- consistent geometry (`geom_wkt`)
- spatial-key alignment (`coord_key`)
- GIS-ready attributes

------------------------------------------------------------------------

# Quality Control System

Quality control is implemented as a non-destructive validation layer
that inspects all data domains, including field measurements, laboratory
analyses, logger data, and hydrologic observations. QC checks identify
missing parameters, invalid values, structural inconsistencies, and
anomalies in time-series behavior.

Results are summarized in a database table and written to CSV reports
for inspection. QC does not alter the data; instead, it provides
transparency and ensures that downstream analyses are based on known
data quality.

## QA / QC Framework

QC checks include:

- missing field parameters  
- major ion completeness  
- logger anomalies  
- out-of-range temperatures  
- orphaned samples

------------------------------------------------------------------------

## Outputs

- QC_Summary table  
- CSV reports (`qc_reports/`)

------------------------------------------------------------------------

## Design Principle

QC does not modify data — it flags issues for interpretation.

------------------------------------------------------------------------

# GIS Export and Spatial Integration

The system produces a consolidated GeoPackage containing spatial layers
derived from analysis views. Each layer includes geometry, attributes,
and spatial keys, allowing seamless integration into GIS platforms.
These outputs support mapping, spatial analysis, and visualization of
hydrologic and geochemical relationships.

Gradients, temperature data, wells, and sampling locations can all be
explored spatially, enabling interpretation of the hydrothermal system
in a geographic context.

------------------------------------------------------------------------

------------------------------------------------------------------------

------------------------------------------------------------------------

# Future Development

The next stages focus on expanding analytical capability rather than
infrastructure.

Isotope data (δ18O, δD) will be integrated as a parallel measurement
system linked to samples, enabling mixing analysis and identification of
recharge sources. PHREEQC integration will convert chemical observations
into thermodynamic models, producing speciation and saturation indices.
Flux measurements will allow estimation of hydrothermal discharge and
heat flow, completing the system’s ability to quantify mass and energy
transport.

Ultimately, these components will feed into a higher-level analysis
layer focused on detecting hydrothermal upflow zones through the
integration of gradients, temperature anomalies, and geochemical
signatures.

------------------------------------------------------------------------

# Why This System Matters

This project demonstrates how environmental data can be transformed into
a reproducible scientific system through careful architecture. It
enforces provenance, preserves raw observations, separates
transformation from interpretation, and integrates multiple data domains
into a unified analytical platform.

The result is not just a database, but a **scalable hydrothermal
modeling workflow** that can be extended to other geothermal systems and
environmental datasets.

**Concretely, versus a spreadsheet-per-campaign approach:**

- Raw files are never mutated -- every ingest script reads from
  `data/raw/` and only ever *appends* new rows, so re-running an ingest
  after dropping in a new file is always safe (see "New data-drop
  locations" below for exactly where each source goes).
- Every source's provenance is queryable, not just remembered -- the
  `Data_Sources` table and `source_id` foreign keys mean any row in the
  database can be traced back to *which* source produced it (e.g. NDEP
  open-data portal vs. a Public Records Request PDF are two distinct,
  always-distinguishable sources, even though both ultimately populate
  chemistry tables).
- Every GIS/report output is regenerable from the database, not
  hand-maintained -- `output/geopackage/hydro_data.gpkg` and the
  pipeline report are produced fresh from current data every run, so
  they can never silently drift out of sync with what's actually in
  the database.
- Ingest is incremental and idempotent by design (deduplication keyed
  on natural identifiers -- `(logger_id, timestamp)`,
  `(station_id, date, parameter)`, file content hashes, etc.) --
  running the same ingest twice, or with old files still present,
  never double-counts or corrupts existing data.

## New data-drop locations

As of 2026-09-05, the raw-data folders below also accept these newer
source types (each with its own idempotent ingest script, wired into
`run_pipeline.R`'s `RUN_INGEST` flags):

| Source | Drop location | Ingest script |
|---|---|---|
| USGS historic grab-sample chemistry (WQP export) | `data/raw/usgs/fullphyschem_station_download/*.csv` | `ingest_usgs_historic_chemistry.R` |
| NOAA weather (precipitation/temperature) -- any of the formats seen so far | `data/raw/noaa/*.csv` | `ingest_noaa_weather.R` |
| Field photos (for EXIF GPS location extraction) | `data/raw/images/image_drop/*` (+ a human-maintained `data/raw/images/image_location_map.csv`) | `ingest_image_locations.R` |
| NDEP Public Records Request documents | `data/raw/ndep/PRR/PPR_<date>/*.pdf` (new request = new dated sibling folder, never overwrite) | `ingest_ndep_prr.R` (pilot; stages to `Staging_NDEP_WQ` for review, does not write directly to core tables) |
| Conductivity/EC loggers (HOBO/Onset) | `data/raw/conductivity/` (+ `conductivity_logger_deployments.csv`) | `ingest_conductivity.R` |
| NDWR "Well Driller's Report" PDFs (any future batch) | any directory of these PDFs, e.g. `data/raw/ndwr/Ormat_well_logs/` | `ingest_well_logs.R` (OCR + NDWR log-number cross-reference; see "Well & Facility Flow Network" below) |
| Human-curated well/port network assignments (from a flow diagram like Dhakal et al. 2025 Fig. 5) | `data/raw/wells/dhakal_well_network.csv`, `well_aliases.csv` | `register_well_network.R` |
| Well coordinates from an external source (NBMG, ArcGIS digitization, etc.) | `data/raw/wells/*_coordinates*.csv` | `register_well_coordinates.R` |
| ArcGIS-digitized point/polygon layers (satellite-overlay wells, facility footprints) | `data/raw/arcgis/*.shp` | `register_facility_areas.R` |
| Field photos **and now videos** (mp4/mov/m4v) for EXIF GPS extraction | `data/raw/images/image_drop/*` (+ `image_location_map.csv`) | `ingest_image_locations.R` (as of 2026-09-06; most videos checked so far carry no embedded GPS at all, so they still need a manual coordinate/station code in the mapping file, same as any un-geotagged photo) |
| Literature PDFs for citation (never re-hosted, never committed) | `docs/literature/*` (gitignored) | none -- read manually for citation details, see `website/references.Rmd` |

## Data Availability Reporting

`scripts/analysis/data_availability.R` answers "what data do we have, and
for what time period?" across every major dated table in one place --
previously only approximated indirectly (an ingest-log growth curve and a
temperature-observation histogram on the website). It handles each
table's own date-storage quirk (Excel serial numbers, Unix epoch
seconds, ISO strings, and -- as discovered while building this --
`Sampling_Events.date` mixing *both* Excel-serial and Unix-epoch-day
conventions within the same column for different rows; see the
Troubleshooting section below) and produces:

- `data/derived/data_availability/data_availability.csv` -- one row per
  source with `start_date`/`end_date`/`n_records`.
- `output/figures/data_availability_timeline.png` -- a horizontal
  bar/Gantt-style chart, one bar per source spanning its earliest to
  latest dated record, colored by data type (continuous logger vs.
  discrete/event vs. external time series).

![Data availability by source](output/figures/data_availability_timeline.png)

Runs automatically, unconditionally, in the pipeline's export stage
(`build_data_availability_outputs(con)` in `run_pipeline.R`) -- it's
read-only reporting, not gated by any `RUN_INGEST` flag.

# Well & Facility Flow Network

## Status: 🟡 Partially implemented (production→port routing real; injection-side and several well identities still open)

Represents Ormat's production well → commingling port (Galena 1/2/3,
SB2/3, SBHR) → injection well routing, transcribed from Dhakal et al.
(2025)'s Figure 5 flow diagram, plus the raw NDWR well-log PDFs that
back up individual well construction records.

**Schema:** `Wells.well_role` (production/injection/monitor/domestic/
unknown), `Well_Aliases` (a well may have several names -- diagram
labels, UIC permit IDs, historical GS-numbers), `Sampling_Ports`,
`Production_Port_Links`/`Port_Injection_Links` (both carry
`valid_from`/`valid_to`, since routing is an operational choice that can
change), and `Facility_Areas` (polygon footprints digitized from
satellite imagery). Two views, `vw_production_to_port` and
`vw_port_to_injection`, expose each leg independently so real partial
data renders without waiting on the harder-to-source leg.

**Well-log ingestion:** `ingest_well_logs.R` OCRs (via `tesseract`,
falling back through a labeled field → unlabeled scan → UTM-conversion
chain) and/or NDWR-log-number-cross-references NDWR "Well Driller's
Report" PDFs into a `Well_Log_Documents` staging table -- never assigned
a `well_id` without a human-confirmed match in
`data/raw/ndwr/well_log_document_map.csv`, following this project's
standing rule against guessing well identity from proximity or owner
name alone. Logs with real coordinates/construction data but no
confirmed identity are still registered as their own provisional `Wells`
rows (named `"Unidentified Well (NDWR Log <log_number>)"`,
`well_role = 'unknown'`) via `register_provisional_well_logs()`, so the
real data is visible/mappable rather than stranded in staging.

**Known gaps** (see `AGENTS.md` for full per-well provenance): several
Dhakal-diagram well identities (`PW-1/2/3`, `13-5R`, `21B-5R`, `83B-6R`,
`23-33RD`) still lack a coordinate; well `2-1`'s role is unconfirmed;
and matching individual well logs to named wells has so far only
produced leads, not confirmed identities (a lat/lon-only match can be
misleadingly close -- e.g. one log initially looked like an 18 m match
to a known production well, but its completion date was 8 years off).



# Hydraulic Gradient System

## Status: ✅ Implemented

Hydraulic gradients are computed between wells using:

- spatial pairing (projected coordinates)
- time-matched observations
- distance-based filtering

------------------------------------------------------------------------

## Outputs

- `Hydraulic_Gradients` table
- vector geometries (flow direction)
- GIS export layer

------------------------------------------------------------------------

## Scientific Use

- groundwater flow direction mapping  
- identification of hydraulic highs/lows  
- detection of hydrothermal upflow zones


## Known limitation (as of 2026-09-05)

The current implementation only connects **pairs of wells sampled at
the same timestamp** with a straight line and `Δhead / distance` -- it
does not do any spatial interpolation. With 3+ wells this produces a
tangle of pairwise vectors anchored to whichever wells happened to be
sampled together, not to a spatially consistent surface -- which is
why past ArcGIS exports of this layer alone were hard to interpret as
a coherent flow field. Treat this layer as a quick per-pair sanity
check, not a substitute for a potentiometric surface (below).

Separately, a schema-drift bug (`Locations.coord_key` missing from
some already-created operational databases even though it's in the
schema definition) was silently breaking several *other* GIS layers
(`locations`, `vw_temperature_timeseries`, `vw_major_ions`,
`vw_isotopes_gis`) -- `export_geopackage.R`'s per-layer `tryCatch`
meant this failed quietly rather than crashing the export, so those
layers may have been silently missing from earlier GeoPackage exports
too. This has been fixed with an additive migration in
`01_define_schema.R` (backfills `coord_key` from lat/lon on any
database missing it); re-export the GeoPackage to pick up the
previously-missing layers.

## Planned: potentiometric surfaces

A real potentiometric surface needs spatial interpolation over a grid,
not pairwise lines. Planned design (not yet implemented):

- **Inputs:** well hydraulic head time series (`vw_hydraulic_head_clean`,
  already available), a boundary condition from creek elevation
  (not yet in the database -- needs a DEM extract or surveyed points),
  and ideally a DEM for context/masking (also not yet present).
- **Method:** grid-based interpolation (IDW via `gstat`, or a
  thin-plate spline) over a regular point grid, computed per sampling
  timestamp rather than one static surface, since head *change* over
  time is part of the scientific question.
- **Storage:** a new `Potentiometric_Surface_Grid` table (x, y,
  timestamp, interpolated_head, method, uncertainty) rather than a
  raster file, so it stays queryable/versioned like everything else in
  this database; exported to the GeoPackage as an additional layer
  alongside (not replacing) `hydraulic_gradients`.
- **Contaminant-transport link:** once a head surface exists, the same
  interpolation machinery can produce a chloride surface to support
  qualitative transport-direction mapping -- a distinct follow-up step,
  not attempted alongside the head surface itself.

------------------------------------------------------------------------

# Geochemistry System

## Status: ✅ Implemented (initial)

- NDEP chemistry integrated
- analytes standardized across sources
- lab + field data unified

------------------------------------------------------------------------

## Capabilities

- major ion analysis  
- charge balance (future)  
- geochemical trend analysis

------------------------------------------------------------------------

# Temperature System

## Status: ✅ Implemented

- continuous logger ingest
- time-series stored and indexed
- spatial linkage through Locations

------------------------------------------------------------------------

## Use

- thermal anomaly detection  
- temporal variability analysis  
- hydrothermal signal identification

------------------------------------------------------------------------

# PHREEQC Integration (Next Phase)

## Status (2026-09-05)

A starter script, `scripts/phreeqc/09_build_phreeqc_tables.R`, exists but
is **not yet wired into `run_pipeline.R`** and has not been audited or
re-verified this session -- everything below is the design intent, not
a confirmed current state. This is the next major integration priority
for this project once the well/facility network and sampling-frequency
workstreams above stabilize. `phreeqc/templates/` and `phreeqc/runs/`
hold model templates and prior run I/O respectively.


## Goal

Convert observations into thermodynamic models.

------------------------------------------------------------------------

## Planned Outputs

- speciation  
- saturation indices  
- geothermometers  
- inverse models

------------------------------------------------------------------------

## Design

PHREEQC will:

consume views → produce model tables → feed analysis

------------------------------------------------------------------------

# Isotope System (Next Phase)

## Planned Integration

- δ18O  
- δD  
- additional tracers

------------------------------------------------------------------------

## Purpose

- mixing analysis  
- recharge source identification  
- hydrothermal vs meteoric discrimination

------------------------------------------------------------------------

## Design Principle

Isotopes:

- attach to Samples  
- do NOT require full chemistry dataset  
- integrate via analysis views

------------------------------------------------------------------------

# Flux System (Planned)

## Future Table

Flux_Measurements:

- location_id  
- timestamp  
- flux_value

------------------------------------------------------------------------

## Purpose

- quantify discharge  
- estimate heat flux  
- constrain system mass balance

------------------------------------------------------------------------

## Troubleshooting and Expected Errors

- This system is designed to fail loudly and informatively when
  assumptions are violated.
- Common errors are expected and usually indicate data or workflow
  issues

### Common Expected Errors

    no such table: Locations

**Cause**: Schema has not been created yet in OPERATIONAL mode Fix: Run
schema creation once before ingesting data

    invalid or closed connection

**Cause**: Database connection was closed before a script attempted to
use it Fix: Ensure that only the orchestrator (index.Rmd) manages
dbConnect() / dbDisconnect()

    Empty plots or suppressed figures

**Cause**: No data have been ingested yet in OPERATIONAL mode Fix: This
is expected behavior; ingest scripts must be run explicitly

    Ingest scripts insert zero rows

**Cause**: No new data or duplicate external identifiers Fix: Confirm
that new external IDs are present in input files

    A CRLF text file (.Rmd/.R/.yml/.css/.gitignore) has doubled \r\r\n
    line endings, or an edited file suddenly renders with visible
    literal "title:"/"output:" text instead of being parsed as YAML

**Cause**: on Windows R, `writeLines(x, con, sep = "\r\n")` opens a
text-mode connection that itself auto-translates every `\n` to `\r\n`;
the explicit `"\r\n"` separator's own trailing `\n` then gets
translated a second time, doubling the carriage return (`\r` +
auto-translated `\n` becomes `\r` + `\r\n` = `\r\r\n`). This broke
`website/timeline.Rmd`'s YAML front matter outright (pandoc silently
fell back to treating it as plain text) and had also quietly corrupted
several other website `.Rmd` files, `_site.yml`, `styles.css`, and
`run_pipeline.R` itself without visibly breaking their rendering, until
a project-wide search for doubled carriage returns caught it. **Fix**:
never pass an explicit CRLF separator to `writeLines()` on this
platform; use the default (a plain newline) and let Windows perform
the single translation itself. To repair an already-corrupted file,
strip all stray carriage-return characters first, then write back with
a plain newline separator.

------------------------------------------------------------------------

## Debugging Individual Ingest Pipelines

*Each ingestion pipeline is designed to be run independently for
debugging*

------------------------------------------------------------------------

## Why This Approach Matters

*This project demonstrates reproducible science practices that scale
beyond a single dataset:*

- Clear separation between *data*, *infrastructure*, and *analysis*
- Explicit provenance and audibility
- Safe handling of real research data
- Transparency in how raw observations become scientific observations

This architecture is transferable to other environmental, geochemical,
ecological, and geothermal studies.

------------------------------------------------------------------------

## Link to Github Pages Hosted Website for Index.html

<https://tylerirvin543.github.io/Steamboat_Creek_Geochemistry_Database/>

As of 2026-09-06 the site (source in `website/`, rendered to `docs/` via
`rmarkdown::render_site()`) has eight pages: Overview, Scientific
Context, **Timeline**, Pipeline, Data System, Results, References, and
About. Timeline is a photo/video-driven account of the 2025 Lower
Sinter Terrace eruption and response, dated from each asset's own EXIF
capture timestamp rather than guessed; Results includes a real,
poster-stage chloride mass-balance finding (Irvin and Lindsey, 2026,
GRC poster); a QR code linking back to this live site (generated with
the `qrcode` R package, in `website/assets/qr/`) appears on that poster
and on the About page. **Never edit `docs/` directly**: it is fully
regenerated by `build_website()` in `run_pipeline.R`, which also backs
up and restores `docs/literature/` around every render (that folder has
no counterpart in `website/`'s own input tree, so `render_site()`'s
normal cleanup would otherwise delete it; this happened once, see
`AGENTS.md`'s session notes, before the guard was added).

## Citation & Reuse

**This repository is designed for instructional and research use. Please
cite or aknowledge appropriately if reused or adapted.**
