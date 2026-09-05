# Steamboat Geochemistry Database — Project Memory

## Project Overview

UNR thesis project on geothermal outflow changes at Steamboat Hills, Nevada,
following the previous year's Lower Sinter Terrace eruption. The work involves:

- **Remapping springs** at the Lower Sinter Terrace that Ormat reports as inactive
- **Spring and well chemistry** (including isotopes) sampled at Lower Sinter wells and springs
- **Chloride discharge analysis** — comparing Michael Sorey's previous Cl discharge work to the current system
- **Environmental plume monitoring** — mapping Cl and conductivity (as a proxy for Cl) in the subsurface from well chemistry
- **Conductivity time series** — PVCC pipe sensor in Steamboat Creek acts as a Cl discharge proxy; a second conductivity/temperature sensor is further downstream; a USGS gauge station for discharge is further downstream still
- **Temperature time series** at springs and wells
- **Hydrologic condition mapping** in the subsurface using well chemistry data
- End goal: export consolidated data to ArcGIS for interpolation, spatial statistical modelling, and mapping

## Data Sources

| Source | Description |
|--------|-------------|
| **Field sampling** | Chemistry (ions, isotopes), temperature at Lower Sinter wells and springs |
| **NDEP** | Chemistry from Steamboat production wells (public record request) |
| **USGS** | Water level, discharge, temperature time series |
| **NDWR** | Well and water rights data |
| **Temperature loggers** | Time series at springs and wells |
| **Conductivity sensors** | Two locations in Steamboat Creek (upper PVCC pipe, lower downstream) |
| **Lab results** | Ion chemistry and isotope analyses |

## Database Architecture

SQLite-based, three database files in `database/`:

| Database | Size | Purpose |
|----------|------|---------|
| `geochem_demo.sqlite` | ~146 MB | Demonstration / full dataset |
| `geochem_operational.sqlite` | ~20 MB | Operational database |
| `geochem_sampling.sqlite` | ~9 MB | Sampling tracking |

Schema defined in `database/schema/01_define_schema.R`.

## Project Structure

```
├── scripts/
│   ├── ingest/          # ETL: source-specific importers (USGS, NDEP, NDWR, field, lab, loggers, isotopes)
│   │   └── helpers/     # Utility functions (datetime parsing, unit conversion, interpolation, etc.)
│   ├── analysis/        # Analysis products (gradients, isotope pairs, views)
│   ├── qc/              # Data validation and quality control
│   ├── templates/       # Database and temp diagrams, flux templates
│   ├── documentation/   # Schema documentation generator
│   └── phreeqc/         # PHREEQC geochemical modelling integration
│   └── run_pipeline.R   # Main pipeline execution
├── data/
│   ├── raw/             # Source data (field/, lab/, loggers/, ndep/, ndwr/, usgs/, isotopes/, historical/, discharge/)
│   ├── processed/       # Archived and normalized data
│   └── derived/         # Analysis outputs (clustering, inverse models, PHREEQC I/O)
├── database/            # SQLite databases + schema definitions
├── output/              # Pipeline reports, GeoPackage exports, QC output, figures
├── docs/                # Rendered HTML documentation site
├── website/             # RMarkdown source for documentation site (_site.yml)
├── Figures/             # Analysis figures (e.g. d18O_dD.jpeg)
├── qc_reports/          # QC CSV reports (missing data, impossible values)
├── phreeqc/             # PHREEQC model runs and templates
└── Photo_Archive/       # (empty, reserved)
```

## Key Scripts

- **`scripts/run_pipeline.R`** — orchestrates the full ETL + analysis pipeline
- **`scripts/ingest/ingest_field.R`** — field measurement ingestion (largest ingest script)
- **`scripts/ingest/ingest_ndep.R`** — NDEP production well chemistry
- **`scripts/ingest/ingest_usgs.R`** — USGS discharge/water level/temperature
- **`scripts/ingest/ingest_isotopes.R`** — isotope data
- **`scripts/ingest/ingest_temperature_loggers.R`** — Elitech temperature logger time series
- **`scripts/ingest/ingest_conductivity.R`** — HOBO/Onset stream conductivity logger time series (see below)
- **`scripts/ingest/export_geopackage.R`** — GIS export for ArcGIS
- **`scripts/qc/qc_data_integrity_checks.R`** — comprehensive data validation
- **`scripts/qc/qc_conductivity_checks.R`** — conductivity-specific QC (gaps, spikes, field-visit disturbance)

## Conductivity Logger Data & Cl Sampling-Frequency Workflow

Two HOBO/Onset "Full Range" EC loggers were deployed mid-July 2026 to
support a thesis question: **what is the minimum chemistry (chloride)
sampling frequency needed to accurately estimate Cl flux from continuous
conductivity?** This extends (does not replace) the existing SQLite schema.

**Locations / loggers (corrected 2026-09-05):**
- `SBRR` (existing location, `location_id` per DB; longitude typo
  `-199.7437` fixed to `-119.7437` directly in `geochem_operational.sqlite`)
  -- serial `22575724`, role `upstream_control`, co-located with the USGS
  gauge near Rhodes Road. Mean EC ~= 333 uS/cm.
- `SBGG` (new location, seeded in `database/schema/02_conductivity_schema.R`,
  `39.40584, -119.74213`) -- serial `22575725`, role `downstream`. Mean EC
  ~= 1069 uS/cm. No chemistry there yet.
- **The two loggers' location/role assignment was originally swapped**
  (guessed from coordinate proximity) and has since been corrected: the
  originally-`SBRR`-assigned logger's EC (~850-1300 uS/cm) was far too high
  for an upstream control and matched the expected downstream/near-outflow
  signature, so serials were swapped between `SBRR`/`SBGG` in
  `data/raw/conductivity/conductivity_logger_deployments.csv` and
  re-ingested (metadata-only upsert -- the 21,901 already-ingested
  `Conductivity_Observations` rows didn't need to change, since they're
  keyed by `logger_id`, not location). SBRR now correctly reads lower than
  SBGG.
- Logger<->location<->role mapping lives in
  `data/raw/conductivity/conductivity_logger_deployments.csv` (mirrors
  `data/raw/loggers/temperature_logger_deployments.csv`'s format).

**Schema additions** (`database/schema/02_conductivity_schema.R`, sourced
right after `01_define_schema.R`): `Conductivity_Loggers` and
`Conductivity_Observations` (raw EC, temperature, derived `sc_25c`
specific conductance @ 25C via
`scripts/ingest/helpers/compute_specific_conductance.R`, `logger_event`,
`qc_flag`). Mirrors the `Temperature_Loggers`/`Temperature_Observations`
pattern.

**Chemistry pairing status (checked directly in the DB, updated 2026-09-05):**
real lab chemistry (Cl and other major ions) and isotopes for `SBRR`/`SBBV`
have now been ingested from `data/raw/lab/` and `data/raw/isotopes/` (one
FIELD sample each, 2026-05-01). `SBGG` still has no chemistry. However,
these samples **predate the conductivity logger deployment (2026-07-15) by
~2.5 months**, so `get_chloride_conductance_pairs()` in
`03_chloride_models.R` still returns 0 real pairs -- real Cl values now
exist, but don't temporally overlap the logger record yet. The
sampling-frequency statistical workflow (below) is built and self-tested
against synthetic data; it will produce real results once chloride samples
are collected during (or after) the active logger deployment window.

**Statistical workflow** (`scripts/analysis/sampling_frequency/`, plus
`notebooks/` for Quarto write-ups, `models/` for versioned `.rds` artifacts
+ `models/MODEL_REGISTRY.csv`):
1. `notebooks/01_conductivity_temporal_structure.qmd` — diurnal cycle, ACF/
   spectral analysis, STL decomposition. Runs today on conductivity alone.
2. `02_specific_conductance.R` — recalibrates the EC→SC temperature
   compensation coefficient against field checks, once available.
3. `03_chloride_models.R` — lm / GAM (`mgcv`) / Random Forest (`ranger`)
   with hand-rolled rolling-origin (blocked, time-aware) CV — **not**
   `tidymodels`, which is not installed in this environment.
   `demo_chloride_models()` self-tests on synthetic data.
4. `04_monte_carlo_subsampling.R` — Monte Carlo subsampling at candidate
   chemistry intervals (1/2/3/7/14/30 days), comparing reconstructed vs.
   reference Cl and mass-flux error. `demo_monte_carlo()` self-tests on
   synthetic data.
5. `05_recommendation_report.R` — identifies the coarsest interval meeting
   an **explicit, user-supplied** error threshold (never a hard-coded
   default) and writes `data/derived/sampling_frequency/` CSVs +
   `output/figures/sampling_frequency/` plots.
6. `run_sampling_frequency.R` — single idempotent entry point sequencing
   steps 1-4 above (mirrors `run_pipeline.R`'s style); call
   `run_sampling_frequency_pipeline(con, ...)`. Read-only/status-reporting
   unless `refit_models = TRUE` **and** enough real paired data exist; never
   auto-fits on synthetic data or produces a recommendation without an
   explicit threshold argument.

The Quarto notebook (`notebooks/01_conductivity_temporal_structure.qmd`,
rendered to `output/reports/notebooks/01_conductivity_temporal_structure.html`)
is the **overarching reference document** for this whole workstream --
scientific motivation (chloride discharge as a geothermal-outflow tracer,
per Sorey), instrumentation/role provenance, the SC temperature-compensation
formula, all downstream model/Monte-Carlo/recommendation math -- each paired
with the R code that implements it. Update it, not just the scripts, when
the modeling approach changes.

**Packages installed for this work** (were missing from the R library):
`lubridate`, `here`, `zoo`, `ranger`.

## New Data Sources & Fixes (2026-09-05 session)

Substantial multi-workstream update. Key additions/fixes, each idempotent
and wired into `run_pipeline.R`'s `RUN_INGEST` flags:

- **`ingest_usgs_historic_chemistry.R`** -- historic USGS WQP grab-sample
  chemistry (currently just Specific Conductance, param `00095`) from
  `data/raw/usgs/fullphyschem_station_download/*.csv`, stored in the
  *same* `USGS_Timeseries`/`USGS_Stations` tables `ingest_usgs.R` uses for
  live discharge (param `60`) -- deliberate, so SC and discharge are a
  one-line join away. `RUN_INGEST$usgs_historic_chem` (default `FALSE`).
- **`ingest_noaa_weather.R`** + `database/schema/03_weather_schema.R` --
  NOAA weather from `data/raw/noaa/*.csv`, any filename. Two formats
  auto-detected from file content (not filename): "search_tool" (NCEI
  order export, metric units, per-value quality flags) and
  "ghcn_daily_summary" (quoted station-name header line, °F/inches).
  Long-format `Weather_Observations` (station_id, date, parameter, value,
  unit) so a 3rd format is a new parser function, not a schema change.
  `vw_weather_metric` (in `create_analysis_views.R`) does unit
  normalization. `RUN_INGEST$noaa_weather` (default `TRUE`).
- **`ingest_image_locations.R`** + `database/schema/04_photo_location_schema.R`
  -- EXIF-GPS-from-photos pipeline using `data/raw/images/exiftool/exiftool.exe`.
  Two-step, deliberately not fully automatic: (1) GPS auto-extracted from
  `data/raw/images/image_drop/*` into `Photo_Location_Candidates`
  (append-only, keyed by filename); (2) a human-maintained
  `data/raw/images/image_location_map.csv` (columns: filename,
  external_station_code, site_type, name, notes) is the *only* thing that
  creates/touches a `Locations` row -- new codes get registered from
  photo GPS, existing codes get a distance comparison logged to
  `Photo_Location_QC` rather than being overwritten. `RUN_INGEST$image_locations`
  (default `TRUE`).
- **`ingest_ndep_prr.R`** + `scripts/ingest/helpers/parse_ndep_prr_pdf.R` --
  pilot ingestion of NDEP Public Records Request PDFs from
  `data/raw/ndep/PRR/PPR_<date>/*.pdf` (new request = new dated sibling
  folder). Only "Steamboat 2024 Semi-annual Digital Submittal
  (UNEV2007204).pdf" has a usable text layer / SGS lab-report format
  among the 10 documents checked -- the rest (including the originally-
  planned pilot, `NDEP_compiled_U230_Steamboat_reports.pdf`) are fully
  scanned with **no extractable text**; OCR (`tesseract` R package) would
  be needed but its setup is blocked by this environment's sandbox
  (tries to write outside the project on first load) -- unresolved,
  revisit in a normal (non-agent-sandboxed) R session if OCR is wanted.
  Parsed rows are staged in `Staging_NDEP_WQ` (never written directly to
  core tables) with idempotency via a `Documents_Processed` filename+hash
  table, so a *revised* PDF re-parses but an unchanged one doesn't.
  `RUN_INGEST$ndep_prr` (default `FALSE` -- pilot).
- **Fixed:** `Locations.coord_key` schema-drift bug -- defined in
  `01_define_schema.R`'s `CREATE TABLE` but missing from this operational
  database (created before the column was added; `CREATE TABLE IF NOT
  EXISTS` never migrates existing tables). This silently broke
  `vw_locations_gis`, `vw_logger_locations`, `vw_temperature_timeseries`
  (when built in the wrong order), `vw_major_ions`, and `vw_isotopes_gis`
  -- `export_geopackage.R`'s per-layer `tryCatch` meant this failed
  quietly rather than crashing, so those GIS layers may have been
  missing from past exports. Fixed with an additive migration in
  `01_define_schema.R` (adds the column + backfills from lat/lon if
  missing; no-op otherwise). Also fixed `export_geopackage.R` crashing
  outright when `Hydraulic_Gradients` doesn't exist yet (now skips with
  a message).
- **Note:** `vw_temperature_timeseries` is defined *twice* -- once in
  `create_analysis_views.R` (4 plain columns, no geometry) and once in
  `create_gis_views.R` (full columns + `geom_wkt`). It currently "works"
  only because `run_pipeline.R` calls `create_gis_views()` after
  `create_analysis_views()`, so the GIS version wins by running last.
  This is order-dependent and fragile -- not renamed/fixed this session,
  flagging for awareness.
- **Fixed:** `ingest_temperature_loggers.R` hard-stopped the *entire*
  ingest run on any single unresolved `external_station_code` or
  unparseable `.xls`-that's-really-`.xlsx` file (an Elitech export
  quirk). Both now warn-and-skip just the affected logger/file instead.
- New notebooks: `notebooks/02_sc_discharge_weather.qmd` (SC vs. USGS
  discharge vs. weather, real SC/weather data, discharge not yet
  populated) and `notebooks/03_temperature_sc_correlation.qmd`
  (exploratory pairwise lagged cross-correlation, temperature-logger
  sites vs. conductivity-logger sites -- flags the multiple-comparisons
  risk explicitly; `SBRR` has both logger types co-located).
- README expanded: architecture-benefits comparison, new data-drop
  locations table, gradient-system known-limitations + planned
  potentiometric-surface design (interpolation-based, not yet built).

## Session 3 updates (2026-09-05, continued): NDEP promotion, NBMG well lookup, photo-pipeline hardening

- **NDEP PRR chemistry is now promoted, not just staged.** New
  `scripts/ingest/promote_staged_ndep.R` (manual step, deliberately NOT
  wired into `RUN_INGEST` automatically) reads
  `data/raw/ndep/PRR/staged_ndep_location_map.csv` (human-maintained:
  station_name -> external_station_code/site_type/lat/lon/
  coordinate_source/coordinate_uncertainty_m/notes), registers any new
  `Locations` rows, and promotes matching `Staging_NDEP_WQ` rows into
  `Sampling_Events`/`Samples`/`Lab_Analyses` (idempotent via a
  `promoted_at` column added to `Staging_NDEP_WQ`). Critically, it maps
  SGS lab-report parameter names ("Chloride", "Calcium", ...) to this
  project's standard short analyte codes ("Cl", "Ca", ...) via
  `sgs_analyte_map` -- without this, promoted rows would silently never
  match `vw_major_ions`' `WHERE analyte IN ('Ca','Mg','Na','K','Cl',
  'SO4','HCO3')` filter and would be invisible in the GIS/GeoPackage
  export (confirmed and fixed this session: caught it by checking
  `vw_major_ions` after a first promotion attempt, saw 0 matching rows,
  traced it to the naming mismatch).
- **4 of the 13 originally-unlocated NDEP PRR station names are now
  resolved and promoted with real chemistry (incl. Cl) in the GeoPackage:**
  `Boyd Dom` -> Boyd Domestic Well (39.37371, -119.7453), `Jeppson Dom`
  -> Jeppson Geothermal Well (39.35931, -119.7685), `Rogers Well` ->
  Rogers Domestic Well (39.36248, -119.7646), `Soccer Field` -> Soccer
  Field Monitoring Well (39.40187, -119.7594) -- all matched by **exact
  wellname** in NBMG's statewide "Geothermal_Wells" dataset (ArcGIS
  Open Data: `data-nbmg.opendata.arcgis.com/datasets/72341ba987e34c12a575c83f1d7c5367_0`,
  direct CSV export works at `.../<id>.csv`; filter to `county ==
  "Washoe"` for the Steamboat area). This is a much better source than
  NBMG's single-PDF-per-site "Direct Use" facility reports
  (`data.nbmg.unr.edu/public/geothermal/data/otherdata/DirectUse_data/`)
  tried first -- that one only has one record per named facility and no
  bulk/browsable index (directory listing is 403'd; only a guessed exact
  filename worked). No `location_uncertainty_statement` was provided by
  NBMG for these 4, so `coordinate_uncertainty_m = 100` was used as a
  documented default (see `coordinate_source`/`coordinate_uncertainty_m`
  columns added to `Locations` earlier this session).
- **Still unresolved** in `staged_ndep_location_map.csv` (chemistry
  stays staged, not promoted, until filled in):
  - `Herz Deep` -- NBMG has **four** ambiguous candidates ("Harold Herz
    1", "Harold Herz 2", "Harold Herz Geothermal Well 1", "Harold Herz
    Geothermal Well 2", plus separately "Herz Domestic Well 1" and
    "Herz Domestic Well 2") spanning ~1.3 km, none confirmed as
    specifically "Herz Deep." The NBMG Direct-Use PDF's coordinate for
    "Harold Herz Geothermal Well 2" (39.39131, -119.75332) doesn't match
    *any* of the ArcGIS layer's coordinates for that same name either --
    the two NBMG sources disagree with each other.
  - `NDOT`, `Galena 1/2/3 Outlet`, `SBHR Outlet` -- no match in either
    NDWR well logs or the NBMG Geothermal_Wells layer; likely Ormat's
    own creek/outlet monitoring points rather than registered water
    wells, so a well database is the wrong place to look for these.
- **NDWR well-log index** (`data/raw/ndwr/*_WellLogQuery_all_*.xls`) is
  actually an Excel "Web Page, Filtered" export -- despite the `.xls`
  extension, the file itself is a tiny HTML frameset and the real data
  table lives in a companion `<filename>_files/sheet001.htm`. Parse
  that file with `rvest::read_html()` + `html_table()`, not
  `readxl::read_excel()`. Used this to find real (if PLSS-only, not
  lat/lon) matches for Herz/Jeppson/Rogers/Boyd/NDOT by owner name
  before the better NBMG ArcGIS source was found -- superseded, but the
  parsing trick is worth remembering if NDWR data needs revisiting.
- **Photo-location pipeline hardened** (`ingest_image_locations.R`):
  now also extracts EXIF `GPSHPositioningError` (device-reported
  horizontal accuracy) into `Photo_Location_Candidates.gps_h_accuracy_m`;
  new `Locations.coordinate_source`/`coordinate_uncertainty_m` columns
  (additive migration in `04_photo_location_schema.R`) record positional
  provenance for *any* location, not just photo-derived ones; new
  `Field_Observations` table (+ optional `observation_note`/
  `linked_external_sample_id` columns in `image_location_map.csv`) lets
  a photo record a qualitative field note (and optionally tie it to a
  specific sample), not just a bare coordinate. Documented in new
  `notebooks/04_photo_location_workflow.qmd` (workflow diagram,
  assumptions, the SBF_0001/IMG_4571 worked example, explicit note that
  uncertainty is recorded but not yet mathematically propagated into any
  statistic).
- **Not done this session** (scoped but not built, given time -- still
  on the list for next time): the horizontal data-coverage bar chart/
  report (Phase 1 of the 2026-09-05-1009 plan), the PRR
  folder-per-document-type routing convention (`lab_reports/`/
  `tft_compliance/`/`uic_forms/`/`other/` subfolders), a
  position-aware (`pdftools::pdf_data()`-based) parser for the TFT
  compliance reports' "Appendix D" injection-well geochemistry (real
  data confirmed present this session, just not yet parseable with the
  simple pilot approach), transport-number/charge-balance-QC additions,
  and citing the three attached McCleskey/Newman papers in
  README/website with a `docs/literature/` folder (open question:
  whether to commit the PDFs into git at all).

## Key Figures

- `isotope_mixing_plot.png` — isotope mixing diagram
- `Figures/d18O_dD.jpeg` — δ18O vs δD plot (likely the isotope figure for poster improvement)
- `thermal_upflow_outflow_grc.png` — thermal upflow/outflow diagram (GRC)
- `steamboat_database_architecture_diagram.png` / `steamboat_poster_database_diagram.png` — database architecture diagrams

## Scientific Context

- **Study area:** Steamboat Hills geothermal system, south of Reno, NV
- **Operator:** Ormat Technologies (geothermal power production)
- **Key reference:** Michael Sorey's chloride discharge studies
- **Analytical focus:** Cl discharge as a tracer for geothermal outflow; conductivity as a real-time proxy for Cl
- **Poster in progress** — isotope figure improvement is an immediate priority

## Technical Notes

- R-based pipeline (tidyverse, RSQLite, sf for spatial)
- GeoPackage export for ArcGIS integration
- PHREEQC for geochemical modelling
- RMarkdown documentation website
- Use base R pipe `|>`
