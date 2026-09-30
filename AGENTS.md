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

## Session 4 updates (2026-09-05, continued): well-network matching, literature review, critical pipeline bugs fixed

### Well/location matching (Dhakal diagram, Klein 2007 monitor-well network, NDEP permit table)

- **New literature added to `docs/literature/`** (not yet committed to
  git -- see "open decisions" below): Dhakal et al. (2025, Stanford
  GRC) "Forty Years of Production from the Steamboat Geothermal Field"
  (numerical model update, well groupings/flow diagram); Klein et al.
  (2007, GRC) "Resource Exploitation at Steamboat, Nevada" (the single
  most useful reference for the groundwater monitor-well network --
  its Figure 1 is a labeled map of every production/injection/monitor
  well); Sorey & Spielman (2008 and 2017, GRC) on Cl-flux
  thermal-water discharge (2008 paper independently confirms
  `SBRR`="Rhodes Road" and `SBGG`="Geiger Grade", matching this
  project's conductivity-logger naming and upstream/downstream roles
  exactly); Cohen & Loeltz (1964, USGS WSP 1779-S); White, Thompson &
  Sandberg (1964, USGS PP 458-B) and White (1968, PP 458-C) plus their
  plates (PP 458-C Plate 1 is a geologic map with historical pre-Ormat
  "Nevada Thermal Power 1-6" plant locations and GS-numbered
  exploration wells -- different well-numbering scheme, useful
  historical context, not yet used for current matching); a 1964 TMWA
  hydrogeology/chemistry paper (possible well+chemistry data, location
  presence unconfirmed, not yet reviewed); a Mariner & Janik
  geochemistry paper (not yet reviewed); a "Steamboat Hot Springs 4"
  single-page permitted-well index map (traced to being a native
  NDWR/State Engineer product, not from any of the USGS papers, by
  comparing its permit-number range to the "Permit" column values
  NDWR's own WellLogQuery tool returns).
- **NBMG's statewide `GEOTHERM06102019.csv` well-log compilation**
  (2238 wells; user-saved to `data/raw/nbmg/GEOTHERM06102019.csv`, not
  yet committed to git) combined with the NBMG ArcGIS Geothermal_Wells
  layer and manual NDWR WellLogQuery searches (via user-provided
  screenshots) resolved coordinates for most of the Dhakal-diagram
  production/injection wells (`78-29`, `23-5`, `34-32`, `44-32`,
  `14A-33`, `44A-32`, `24-5`, `43-33`, `21-32`, `64A-32`, `21-5R`,
  `13-5R`, `21B-5R`, `83B-6R`, `23-33RD`, `MTH 12-33`) -- these
  matches exist only in conversation/session notes so far, **not**
  written to the database (the Wells/Locations schema-vs-diagram
  linkage -- a Sampling_Ports/flow-network table representing
  production well -> port (Galena 1/2/3, SB2/3, SBHR) -> injection
  well -- remains undesigned and unbuilt). `PW-1/2/3`, `PW2-*`,
  `PW3-*`, `IW-1/4/5/6`, `HA-4`, `41-5`, `42A-32`, `83C-6ST1` are
  still unmatched to any coordinate.
- **Resolved and written to the database** (via
  `data/raw/ndwr/klein2007_monitor_well_locations.csv` +
  `scripts/ingest/register_monitor_well_locations.R`, and via
  `promote_staged_ndep.R` for Eich): Herz Domestic
  (39.405472,-119.753255, NDWR, distinct from the separate "Harold
  Herz" geothermal wells and from NDEP's still-unresolved "Herz
  (Deep) (2007)"), DeMonte (39.412694,-119.744366, exact "DEMONTE,
  LOUI" NDWR match, confirms Klein's "DiMonte" is a spelling variant),
  Zolezzi Well (39.416306,-119.762423, near but distinct from Klein's
  "Zolezzi Spr" and from the existing "West Zolezzi Lane" creek
  station), Curti Dom/Curti Barn (39.394361,-119.7396, two adjacent
  Gary Curti wells at 595/505 Geiger Grade -- 95ft domestic vs. 260ft
  explicitly-geothermal, inferred to match Klein's two separately-
  named "Curti Dom"/"Curti Barn" points), and Eich Well
  (39.409083,-119.744088, exact "EICH, PAUL" NDWR match, chosen over
  several similar surnames -- Heidenreich/Eichelberger/Eichmann/
  Reichman/Reichlin -- by exact-name match and spatial coherence with
  the rest of the cluster; **this one has real promoted NDEP
  chemistry**, Cl 530-590 mg/L).
- **Still unresolved**: NDOT (24-result NDWR owner-name search found
  nothing within ~6km of the expected cluster; likely logged under a
  different owner name, e.g. the actual facility name or "State of
  Nevada" -- a spatial/GIS NDWR search is the recommended next step,
  not more owner-name guessing), Steinhardt (zero NDWR hits),
  TransSierra, PTR#1, Flame, Brown School, Mackay Geoth/Dom,
  Johnson/Woods, Peigh Pool/Dom, STMGID #3/#4, Cox I-1, IW-2, IW-3.
  Boyd Domestic Well has an unresolved ~1.16km coordinate discrepancy
  between the currently-stored NBMG-sourced point and a more precise
  NDWR-sourced one (39.38325,-119.73992) -- **resolved 2026-09-05
  (session 5)**: switched to the NDWR point in the database. Re-parsed
  the NDWR TM-basin well-log table properly with
  `rvest::html_table()` (the flagged discrepancy had been
  mis-triangulated with manual `grep`/`sed` on the raw HTML, off by
  one row, which briefly looked like it belonged to a different
  owner -- it doesn't). The NDWR point is Log #8188, owner
  "BOYD, VERNON D", Sec 33/T18N/R20E Washoe Co., completed 3/1/1962,
  Proposed Use = "H" (domestic) -- a verifiable identity match
  (surname + domestic-use code), stronger than the superseded NBMG
  *Geothermal_Wells* exact-name-string match, which had no
  corroborating detail. `Locations.location_id = 151` now has
  `coordinate_source = 'ndwr_well_log'`, `coordinate_uncertainty_m =
  200` (PLSS quarter-section resolution for a 1962 log, not a true
  survey fix, hence not tighter).
  13-5R was determined (per user) to be the *later* of two same-named
  historical wells (permit 0340, Production), not yet written anywhere.
- **Drafted and sent (2026-09-05)**: an email to an NDEP contact requesting
  daily water-level/pressure data for wells 43-33-1/21-32-1/21-32-2,
  fumarole inspection logs, OW-1/2/3 and Strat Well water levels,
  chemistry for the standing NDOT/Herz/Boyd/Soccer Field/Eich/Jeppson/
  Rogers monitoring network, and more precise surveyed well locations
  -- referencing NDEP's own Temporary UIC Permit UNEV2007204T2025-1
  REVISED (June 2025, attached by user), which also confirmed several
  injection-well aliases (IW-1=45-28, IW-4=35-28, IW-5=46-28) and
  production-well groupings (Table C's surface basins).

### Critical pipeline/database-integrity bugs found and fixed

A user-requested full ingestion test ("run the ingestion for all
available data and test the database") surfaced a serious
**pre-existing** data-integrity problem, not introduced this session
but made worse by two initial test runs before it was caught:

- **`ingest_ndep.R`'s `Lab_Analyses` insert had zero deduplication**
  (a stray `"Lab_Analyses_MARKER"` table-name typo also meant it was
  at some point silently targeting a nonexistent table). Every
  pipeline run re-appended the *entire* NDEP chemistry export with no
  check against what was already there -- confirmed via distinct-
  combination counts that real records were duplicated **~13x** in
  the operational database, predating this session. Fixed: added the
  same `anti_join(sample_id, analyte, source_id)` dedup pattern
  already used correctly in `ingest_lab.R` / `ingest_isotopes.R`.
- **`ingest_field.R`'s `Locations` idempotency was keyed on the
  derived `coord_key` rather than `external_station_code`.** Since
  SBRR's longitude typo was hand-corrected directly in the database in
  an earlier session (confirmed the *source spreadsheet*,
  `data/raw/field/locations.xlsx`, already has the correct
  `-119.7437` value, so this fix survives a database rebuild), its
  `coord_key` no longer matched the source file's, so re-ingestion
  tried to insert a "new" duplicate and hit the `Locations.
  external_station_code` UNIQUE constraint. Fixed to match on
  `external_station_code`, with an added within-batch
  `distinct(external_station_code)` guard for good measure.
- **`Data_Sources` had no UNIQUE index on `name`**, so every
  `INSERT OR IGNORE` used across every ingest script (a pattern that
  only works if SQLite has a conflict target to ignore against) never
  actually ignored anything -- 14 duplicate rows for one source alone.
  A migration was already present in `01_define_schema.R` (additive,
  collapses existing duplicates to the lowest `source_id` before
  adding the index) but apparently had never had a chance to run
  cleanly; confirmed working correctly on the rebuilt database (every
  source now exactly 1 row).
- **`export_geopackage.R`'s `sample_flow`/`temp_flow` layers** errored
  outright (referencing `sample_flux`/`temp_flow` tables only created
  by a later pipeline stage, `build_sample_flux()`/`build_temp_flow()`)
  instead of skipping cleanly like the `Hydraulic_Gradients` layer
  already did. Fixed with the same existence-check pattern.
- **`run_pipeline.R`'s report-generation paths used a stray `".."`**
  that escaped the project root entirely (got blocked by the sandbox)
  when the script is run from the project root rather than from
  inside `scripts/` -- inconsistent with every other path in the
  script, which is root-relative. Fixed (also fixed a separate
  `rmarkdown::render()` quirk where passing a full path in
  `output_file` intermittently claims the directory doesn't exist;
  now passes `output_dir` + a bare filename instead).
- **`scripts/pipeline_report.Rmd`** ignored the `db_path`/`mode`
  params passed to it entirely and always hardcoded a connection to
  `geochem_demo.sqlite`. Fixed: added a `params:` YAML block (required
  for the `params` object to exist during knitting) and made it use
  `params$db_path`.
- **`qc_conductivity_checks.R`'s `parse_event_date()`** assumed one
  date format could be applied to a whole vector at once (`as.Date()`
  on a character vector requires one format for every element), which
  broke the moment NDEP-PRR-promoted events introduced
  `"MM/DD/YYYY H:MM"` timestamps alongside pre-existing ISO dates and
  Excel serial dates in `Sampling_Events.date`. Fixed: parses each
  value individually, trying serial/ISO/US-datetime formats in turn.
- **Resolved (2026-09-05, session 5)**: `data/raw/discharge/stream_discharge.xlsx` had
  two columns both literally named `transect_id` per sheet (a
  source-spreadsheet defect -- readxl renamed them
  `transect_id...3`/`transect_id...11` on read -- which used to break
  `ingest_flux.R`'s required-column check outright. Inspecting the raw
  sheets showed the first occurrence (`...3`, right after `datetime`,
  before `point_id`) is the real per-point transect identifier,
  matching the expected schema position; the second (`...11`, right
  before `notes`) is a spreadsheet-authoring artifact that just
  repeats the sheet name as a constant on every row (e.g.
  `"transect_A"`) -- already redundant with the `sheet_name` column
  `ingest_flux.R` adds itself. Fixed in `ingest_flux.R`: keeps the
  first occurrence as `transect_id`, drops any later ones. Also
  discovered while testing: every data row in all three transect
  sheets (`transect_A/B/C`) is currently blank -- the file is a
  header-only template awaiting field data entry, not populated data
  with an ambiguous column. Added a guard that drops fully-blank rows
  and exits cleanly (0 rows) instead of failing on downstream
  datetime/numeric validation, so the ingest runs today and starts
  processing rows automatically once real transect measurements are
  entered -- no further code change needed then. `flux` is now `TRUE`
  in `run_pipeline.R`'s chemistry-bearing profiles (1 and 2; profile 3
  skips all ingestion by design). Verified against a scratch copy of
  `geochem_operational.sqlite`, not the real database.
  **Note for future editors**: `ingest_flux.R` and `run_pipeline.R`
  both have CRLF line endings, unlike most other scripts in this repo
  -- multi-line exact-string edits against them silently fail to
  match their `\r\n` line endings; edit one physical line at a time,
  or rewrite the whole file.



### Database rebuild, verification, and new permanent pipeline stages

- The corrupted operational database was backed up to
  `database/archive/geochem_operational_corrupted_<timestamp>.sqlite`
  (not destroyed) and rebuilt from scratch. Full pipeline re-run and
  verified: `Data_Sources` and `Lab_Analyses` fully deduplicated (e.g.
  10,449 total Lab_Analyses rows vs. 10,439 distinct combinations --
  a small residual gap, plausibly legitimate repeat analyses, not
  chased further), `Wells` populated with real depths **for the first
  time** (73 wells, 71 with `total_depth`) via `ingest_ndwr.R` (this
  had apparently never been run against the operational database
  before), `hydraulic_head`/`water_level_latest` populated for the
  first time, `Locations` at 160 rows.
- Two previously ad-hoc, manual-only scripts are now wired into
  `run_pipeline.R` as permanent, flagged ingestion stages --
  `RUN_INGEST$promote_ndep_staged` (`promote_staged_ndep.R`) and
  `RUN_INGEST$monitor_well_locations` (`register_monitor_well_
  locations.R`) -- specifically so the Session 4 well-matching work
  above can't be silently lost again on a future database rebuild the
  way it was mid-session this time (caught and fixed immediately, but
  worth remembering why these two are pipeline stages now, not just
  scripts someone has to remember to re-run).
- **`run_pipeline.R` now has a clear interactive entry point**: when
  sourced in an interactive session (e.g. RStudio console) with
  `MODE`/`RUN_INGEST`/`BUILD_WEBSITE` not already set, it asks three
  `utils::menu()` questions (target database DEMO vs. OPERATIONAL,
  ingestion profile [all sources / core chemistry only / skip
  ingestion], website rebuild) and proceeds unattended. Non-
  interactive runs (Rscript/CI) default safely to `MODE="DEMO"`, all
  working sources. Any of the three variables can still be set as
  plain assignments *before* sourcing the script to bypass the
  prompts entirely (this is how automated/scripted runs, including
  this session's own verification runs, should invoke it).
- **DEMO mode was not itself re-run end-to-end this session** to
  prove out the fixes -- it shares 100% of the same ingestion code
  paths already exercised repeatedly against OPERATIONAL, so this is
  a reasoned inference, not a directly-verified fact. Worth an actual
  DEMO run next time there's time for a ~150MB throwaway rebuild.
- **git**: discovered `data/raw/` (including several small, hand-
  maintained provenance CSVs that encode real decisions --
  `staged_ndep_location_map.csv`, `klein2007_monitor_well_locations.
  csv`, the two logger-deployment maps) had *never* been tracked in
  git at all despite the blanket `data/raw/` gitignore rule, because
  git-negating a file inside an already-ignored directory doesn't
  work (git won't descend into an ignored directory to evaluate
  per-file exceptions). Worked around by `git add -f`-ing those four
  specific files rather than fighting the gitignore pattern -- **any
  new file matching this description needs the same manual
  `git add -f` treatment**, it will not be picked up automatically.
  All pipeline-code fixes plus these four files committed and pushed
  to `origin/main` (commit `6d4166c`,
  `tylerirvin543/Steamboat_Creek_Geochemistry_Database`).
  `docs/literature/` and `data/raw/nbmg/GEOTHERM06102019.csv` remain
  uncommitted/untracked, consistent with the still-open "commit PDFs
  to git?" decision noted in Session 3.

## Session 5 updates (2026-09-05, continued): well/port flow-network schema

Built the previously undesigned/unbuilt schema representing Dhakal et
al. (2025)'s production well -> port -> injection well flow diagram
(production wells commingle at named ports -- Galena 1/2/3, SB2/3,
SBHR -- before routing on to injection wells), flagged repeatedly in
earlier sessions as conversation-only well/coordinate matches with no
database structure to actually hold them.

- **New additive schema file**: `database/schema/05_well_network_schema.R`
  (sourced right after 01-04, both at initial connection and in the
  DEMO reset block). Adds: `Wells.well_role` (migration, TEXT CHECK
  IN ('production','injection','monitor','domestic','unknown'),
  default 'unknown' -- added via `ALTER TABLE ADD COLUMN` with an
  inline CHECK, confirmed this works in this project's SQLite version
  as long as the CHECK only references the new column itself);
  `Well_Aliases` (a well may be known by more than one name --
  Dhakal diagram labels, UIC permit IDs, historical GS-numbers, NDWR
  permit owners -- `UNIQUE(well_id, alias)`); `Sampling_Ports` (the
  named commingling points themselves, `location_id` nullable since
  no port has known coordinates yet); `Production_Port_Links` (many
  production wells -> one port) and `Port_Injection_Links` (one port
  -> many injection wells), both carrying `valid_from`/`valid_to`
  since Ormat's actual routing is an operational choice that can be
  reconfigured over time -- the Dhakal (2025) diagram is a snapshot,
  not necessarily permanent wiring. A `vw_well_flow_network` view
  chains production well -> port -> injection well via both link
  tables (a deliberate cross-join through the port: fluid commingles
  there, so every production well fed into a port is presumed to
  reach every injection well that port feeds, given current --
  incomplete -- data). **Not enforced**: well_role is not
  cross-table-CHECK'd against which link table a well_id appears in
  (SQLite CHECK constraints can't reference other tables); this is a
  convention documented in comments only, worth a QC script check if
  the network grows past a handful of manually-curated rows.
- **Seeded directly by the schema file** (safe, idempotent, high-
  confidence only): the 6 named ports from the Dhakal diagram (no
  coordinates yet); 3 confirmed injection-well aliases from NDEP's own
  Temporary UIC Permit UNEV2007204T2025-1 REVISED (June 2025) --
  IW-1=45-28, IW-4=35-28, IW-5=46-28 -- with canonical `Wells` rows
  created (`well_role='injection'`, no coordinates).
- **New registration script**: `scripts/ingest/register_well_network.R`
  (mirrors `register_monitor_well_locations.R`'s idempotency
  philosophy -- only adds new rows, never updates existing ones, so a
  manual in-database correction is never clobbered by a re-run). Reads
  two human-maintained CSVs: `data/raw/wells/dhakal_well_network.csv`
  (well_name, well_role, port_name, valid_from, valid_to, source,
  notes -- upserts Wells, and if both well_role and port_name are
  filled in, creates the appropriate Production_Port_Links or
  Port_Injection_Links row) and `data/raw/wells/well_aliases.csv`
  (well_name, alias, alias_type, source, notes -- well_name must
  already exist in Wells or the row is skipped with a warning, not
  silently dropped). Wired into `run_pipeline.R` as
  `RUN_INGEST$well_network` (`TRUE` in profiles 1/2, `FALSE` in 3).
- **Deliberately did NOT fabricate port assignments or well roles**
  for the ~29 Dhakal-diagram well names collected in prior sessions'
  conversation notes (`78-29`, `23-5`, `34-32`, `44-32`, `14A-33`,
  `44A-32`, `24-5`, `43-33`, `21-32`, `64A-32`, `21-5R`, `13-5R`,
  `21B-5R`, `83B-6R`, `23-33RD`, `MTH 12-33`, `IW-2/3/6`, `PW-1/2/3`,
  `HA-4`, `41-5`, `42A-32`, `83C-6ST1`) -- `dhakal_well_network.csv`
  registers all of them as `Wells` rows (`well_role` blank ->
  `'unknown'`) so the structure exists, but leaves `well_role` and
  `port_name` blank with a note to re-check against the actual source
  figure rather than guessing from name prefixes or the coordinate
  matches those earlier sessions found but never wrote to the
  database. **Next step for this thread**: re-open the Dhakal et al.
  (2025) diagram (`docs/literature/`) and fill in `well_role` +
  `port_name` (and coordinates, separately, in Wells/Locations) for
  these 29 wells, which will make `vw_well_flow_network` return real
  rows for the first time.
- Verified end-to-end (migration + seed + `register_well_network()`
  run + `vw_well_flow_network` query) against a scratch copy of
  `geochem_operational.sqlite`, not the real database; scratch copy
  deleted after testing.
- **Reminder** (applies here too): `run_pipeline.R` has CRLF line
  endings; the new schema/registration files were written fresh with
  LF and parse/run fine, but any further multi-line edits to
  `run_pipeline.R` itself still need the one-physical-line-at-a-time
  workaround noted earlier this session.

## Session 6 updates (2026-09-05, continued): NBMG well-coordinate matching, GeoPackage line export

User filled in `well_role`/`port_name` for most production wells in
`data/raw/wells/dhakal_well_network.csv` directly from the Dhakal
figure, and supplied NBMG's statewide "Geothermal_Wells" ArcGIS Open
Data layer as a full CSV (`data/raw/nbmg/Geothermal_Wells.csv`, 2854
rows statewide -- **not** the same file as the earlier-saved
`GEOTHERM06102019.csv`; both now present). Source, for citation
wherever this data is used: **https://data-nbmg.opendata.arcgis.com/datasets/72341ba987e34c12a575c83f1d7c5367_0**
(ArcGIS Open Data "Geothermal_Wells" layer).

- **Resolved real NBMG coordinates for 16 Dhakal-network wells**,
  written to `data/raw/wells/dhakal_well_coordinates.csv` (well_name,
  latitude, longitude, apino, coordinate_source, coordinate_uncertainty_m,
  notes -- every row's `notes` documents the exact NBMG record matched,
  its apino permit id, and any rejected competing candidates):
  `23-5`, `34-32`, `44-32`, `14A-33`, `44A-32`, `24-5`, `43-33`, `41-5`,
  `42A-32`, `21-32`, `64A-32`, `MTH 12-33`, `45-28` (=IW-1), `35-28`
  (=IW-4), `78-29`, `HA-4`. Filtered the statewide NBMG file to Washoe
  County + a Steamboat-area bounding box first, then matched by
  normalized well name.
- **Flagged as lower-confidence, not silently merged**: `23-33` (NBMG
  has no coordinate for a well spelled `23-33RD` -- the plain `23-33`
  NBMG record was used, but this is a guess, not a confirmed identity;
  a second same-named NBMG record ~9.7 km south was rejected as a
  different well/data error); `46-28-2` (NBMG has no exact `46-28` in
  Washoe County -- two `46-28`s exist but are in Pershing County, a
  different field entirely, and were rejected; `46-28-2` is the closest
  plausible match for the IW-5 alias but sits notably farther from
  45-28/35-28 than they sit from each other); `78-29` (two same-named
  NBMG records ~150 m apart under different operators/eras -- the
  current-operator "In Use" one was used); `HA-4` (its NBMG coordinate
  is suspiciously *identical* to a previously-noted coordinate for the
  unrelated "Harold Herz Geothermal Well 2" -- NBMG appears to reuse a
  generic estimated coordinate for some wells; flagged as
  low-confidence, `coordinate_uncertainty_m = 500`).
- **Still completely unresolved, not in NBMG or any NDEP PRR
  document checked**: `COX-1`, `PW-1/2/3`, `IW-2/3/6`, `83C-6ST1`,
  `21-5R`, `13-5R`, `21B-5R`, `83B-6R`. Note: the NBMG file *does*
  contain wells literally named `PW-1` through `PW-5`, but they belong
  to `Enel Salt Wells, LLC` in the **Salt Wells field near Fallon**
  (Churchill County, ~40 mi away) -- a naming coincidence, not a match
  for Steamboat's Dhakal-diagram `PW-1/2/3`. Do not reuse those
  coordinates.
- **User's core question -- individual production well identities
  feeding the `SB2`/`SB3` ports (e.g. "PW3-2") -- remains unanswered.**
  Checked exhaustively this session: not in the NBMG Geothermal_Wells
  layer (no well name containing "SB2"/"SB3"/"PW3" found statewide),
  not in any NDEP PRR document (the two TFT Compliance Reports are
  both specifically about well 24-5, not SB2/SB3; the Semi-Annual
  Digital Submittal has only aggregate "SB2 Outlet"/"SB3 Outlet"
  *chemistry*, not individual well identities -- see below). This will
  need to come directly from the Dhakal figure or another source the
  user has.
- **New schema migration** (`database/schema/05_well_network_schema.R`):
  added `Wells.coordinate_source`/`coordinate_uncertainty_m`/`notes`
  (mirrors the columns already on `Locations`), so well coordinates
  carry the same kind of provenance trail as location coordinates do.
- **New script**: `scripts/ingest/register_well_coordinates.R` /
  `register_well_coordinates(con, coords_csv = "data/raw/wells/dhakal_well_coordinates.csv")`
  -- applies coordinates to existing `Wells` rows, matched by
  `well_name`. Idempotent in the same spirit as the other
  `register_*` scripts: only fills a well's coordinate when its
  `latitude` is currently `NULL`, never overwrites; rows referencing
  an unknown `well_name` warn and are skipped rather than silently
  dropped. Wired into `run_pipeline.R` right after
  `register_well_network(con)`, under the same `RUN_INGEST$well_network`
  flag.
- **Verified end-to-end on a scratch copy of `geochem_operational.sqlite`**:
  schema migration -> `register_well_network()` (17 Production_Port_Links
  now populate from the user's filled-in CSV; 0 Port_Injection_Links,
  since no injection well has a `port_name` yet) -> `register_well_coordinates()`
  (16 wells got coordinates, 2 skipped with the name-mismatch warnings
  described above) -> `export_geopackage()`. Scratch copy deleted after
  testing.
- **New GeoPackage layer**: `well_flow_network` in
  `scripts/ingest/export_geopackage.R`, mirroring the existing
  `hydraulic_gradients` linestring-building pattern but reading from
  `vw_well_flow_network` and joining `Wells` coordinates on both the
  production and injection side. Deliberately placed *before* the
  `Hydraulic_Gradients` section's early `return()`s so it still runs
  even on a database without gradients calculated yet. **Currently
  exports 0 rows** -- real coordinates and production-side port
  routing now exist, but zero injection wells have a `port_name` in
  `dhakal_well_network.csv` yet, so `Port_Injection_Links` (and thus
  the view) is empty. Wired in now so lines appear automatically the
  moment injection-side port assignments are added -- **this is the
  single remaining blocker to getting any lines in the GeoPackage at
  all**, more fundamental than the SB2/SB3 well-identity gap above.
- **Bug found and fixed while testing this** (pre-existing, exposed
  only once `Wells` rows with `NULL` coordinates existed for the first
  time): `vw_wells_gis` (`scripts/analysis/create_analysis_views.R`)
  had no `WHERE latitude IS NOT NULL` filter, so a `NULL`-coordinate
  well produced a `NULL` `geom_wkt`, which crashed
  `export_geopackage()`'s `wells` layer entirely with an opaque
  "missing value where TRUE/FALSE needed" error (from `st_is_valid()`
  returning `NA` on the resulting empty geometry). Fixed by adding the
  missing `WHERE` clause.
  **Note for future editors**: `create_analysis_views.R` also has CRLF
  line endings; a multi-line `edit` on it silently failed here too, and
  was ultimately fixed with a targeted `readLines()`/`writeLines(sep="\r\n")`
  round-trip in R rather than the `edit` tool, when even single-line
  `edit` calls kept mismatching (worth trying that approach directly
  next time a CRLF file resists the usual one-line-at-a-time
  workaround).

## Session 7 updates (2026-09-05, continued): ArcGIS-digitized wells + power-plant polygons

User digitized two new layers in ArcGIS by overlaying satellite imagery
and the Dhakal figure (saved to `data/raw/arcgis/dhakal .shp/` --
note the literal space in the folder name):
`Steamboat_power_plant_locations.shp` (5 polygons, attribute
`Powerplant` = `G1`/`G2`/`G3`/`SBHR`/`SB2/3`, source CRS
WGS84/Pseudo-Mercator EPSG:3857) and `Steamboat_wells_dhakal.shp` (12
new well points: `PW 2-3`, `PW 2-5`, `PW 3-1/2/3/4`, `IW-1`, `IW-4`,
`IW-5`, `IW-6`, `OW-2`, `2-1`). This is the first genuinely spatial
(non-tabular) source ingested into the project, and it directly answers
the previously-unresolved "which production wells feed SB2/SB3"
question from earlier this session.

- **Cross-validated the digitization method itself** before trusting
  it for new wells: `IW-1`/`IW-4`'s digitized points landed 44 m / 40 m
  from the independently-NBMG-sourced coordinates for their canonical
  names (`45-28`/`35-28`) -- good agreement, used as the basis for
  trusting the new, otherwise-unverifiable points (`IW-5`/`IW-6`,
  `PW 2-x`, `PW 3-x`, `OW-2`, `2-1`).
- **New coordinates file**: `data/raw/wells/dhakal_wells_arcgis.csv`
  (well_name, latitude, longitude, coordinate_source=
  `arcgis_satellite_overlay`, coordinate_uncertainty_m, notes). Applied
  via a second call to `register_well_coordinates(con, coords_csv = ...)`
  in `run_pipeline.R`, run *after* the NBMG pass so NBMG's
  higher-confidence coordinates for `45-28`/`35-28` are never
  overwritten (confirmed in testing: those two were correctly skipped
  as "already had a coordinate").
- **`register_well_coordinates.R` extended with alias fallback**: if a
  coordinate row's `well_name` isn't a literal `Wells.well_name`, it
  now also checks `Well_Aliases` (e.g. so a CSV row for `IW-5` resolves
  to canonical `46-28`'s `well_id`) -- this is what let `46-28` finally
  get a real coordinate (the earlier NBMG `46-28-2` guess never
  actually applied, since it didn't match any `Wells.well_name`).
- **Real duplicate-well bug found and fixed while testing this**: three
  rows left in `dhakal_well_network.csv` purely as documentation
  (`IW-1`/`IW-4`/`IW-5`, each noting "canonical name is X, alias
  already seeded") had no `port_name` and thus nothing to link -- but
  `register_well_network.R` didn't check `Well_Aliases` before
  deciding a `well_name` was new, so it silently created *duplicate*
  `Wells` rows named `IW-1`/`IW-4`/`IW-5` alongside the real canonical
  `45-28`/`35-28`/`46-28` rows the schema-seed step had already
  created. Fixed by (a) deleting those three now-redundant documentation
  rows from the CSV -- the alias relationship is already fully captured
  by `Well_Aliases` and the canonical `Wells` rows, nothing was lost --
  and (b) making `register_well_network.R` alias-aware the same way
  `register_well_coordinates.R` now is, so this can't recur from any
  future alias-named CSV row. Re-verified with a from-scratch scratch
  database after both fixes: no duplicate `well_name` values, `46-28`
  correctly received `IW-5`'s coordinate.
- **New well/port assignments in `dhakal_well_network.csv`**: `PW 2-3`,
  `PW 2-5` -> production / port `SB2`; `PW 3-1/2/3/4` -> production /
  port `SB3` (assigned by direct name correspondence with the
  `Sampling_Ports` names, not a guess); `OW-2` -> `monitor` (from the
  "Observation Well" prefix, not independently confirmed); `2-1` -> role
  left blank (no PW/IW/OW prefix, genuinely ambiguous -- **flagged for
  user confirmation**, not guessed); `IW-6` gets a coordinate but still
  no `port_name` (this data doesn't reveal which port feeds it -- tried
  spatial containment and nearest-polygon heuristics, both inconclusive/
  too weak to use, see below).
- **Flagged for user review, NOT auto-corrected**: the earlier
  `PW-1`/`PW-2`/`PW-3` rows (role=production, port=`Galena 1`, filled
  in by the user in session 6) use a different naming pattern (`PW-1`
  vs. `PW 2-1`) than these newly-confirmed real `PW 2-x`/`PW 3-x`
  wells tied to `SB2`/`SB3` -- they may be mislabeled/superseded
  now that the real SB2/SB3-side naming scheme is known, but were left
  as-is rather than silently deleted or merged.
- **Tried and rejected as a port-assignment method**: checked whether
  any well point falls spatially `st_within` a plant polygon (0 did --
  the polygons are plant/pad footprints, not well-cluster boundaries)
  and nearest-polygon-by-distance (too confounded to trust: even known
  injection wells with no real SB2/SB3 tie were "nearest" to the
  `SB2/3` polygon simply because it's centrally located in the well
  field). Neither used for `well_role`/`port_name` decisions.
- **New schema file**: `database/schema/06_facility_areas_schema.R` --
  `Facility_Areas` (facility_area_id, facility_name UNIQUE, geom_wkt
  TEXT [POLYGON/MULTIPOLYGON, reprojected to EPSG:4326 on ingest],
  crs, source, notes) -- the project's first polygon-geometry table;
  everything before this (`Locations`/`Wells`/`Sampling_Ports`) was
  point-only. Also migrates `Sampling_Ports.latitude`/`longitude`/
  `coordinate_source`/`coordinate_uncertainty_m` onto the existing
  table (ports previously had no coordinate at all).
- **New script**: `scripts/ingest/register_facility_areas.R` --
  reads the shapefile directly with `sf::st_read()` (not a CSV, since
  the payload is real polygon geometry), reprojects to EPSG:4326,
  inserts into `Facility_Areas` (idempotent on `facility_name`), and
  fills each corresponding `Sampling_Ports` row's coordinate from that
  polygon's centroid (idempotent: only if `latitude` is currently
  `NULL`). Mapping: `G1`/`G2`/`G3`/`SBHR` -> the identically-purposed
  Sampling_Ports (`Galena 1`/`Galena 2`/`Galena 3`/`SBHR`); `SB2/3` (one
  combined polygon) -> **both** `SB2` and `SB3` get the same centroid,
  an explicit, documented approximation (`coordinate_uncertainty_m =
  150`, vs. 75 for the four single-port polygons) since the source
  polygon can't be split into two independent fixes.
- **New GeoPackage layer**: `facility_areas` (polygon) in
  `export_geopackage.R`, alongside the existing point/line layers.
  Verified exporting all 5 polygons correctly.
- **`well_flow_network` still exports 0 rows** -- this session added
  real coordinates for 10 more wells and 6 ports, and 6 new
  Production_Port_Links (the `PW 2-x`/`PW 3-x` wells), but *zero*
  injection wells have a `port_name` yet, so `Port_Injection_Links` is
  still empty and the view has nothing to chain through. This remains
  the single blocker to any lines appearing in the GeoPackage --
  unchanged from last session, just worth re-stating since so much
  else got resolved around it this session.
- Verified end-to-end (schema x2, `register_well_network()`,
  `register_well_coordinates()` x2, `register_facility_areas()`,
  `create_analysis_views()`, `create_gis_views()`, `export_geopackage()`)
  against a from-scratch scratch copy of `geochem_operational.sqlite`;
  scratch copy deleted after testing. `Wells` count in the GeoPackage
  `wells` layer went from 73 -> 99 (26 more coordinate-having wells:
  16 NBMG-matched last session + 10 ArcGIS-digitized this session).
- **Not yet done**: the shapefiles and new CSVs live under `data/raw/`,
  which is gitignored by default -- per the established pattern (see
  Session 4 notes), any of these that should be version-controlled need
  the same manual `git add -f` treatment, not done automatically here.

## Session 8 updates (2026-09-05, continued): real production->port->injection network from Dhakal Figure 5

User corrected two wrong assumptions from session 7 and supplied the
actual Dhakal et al. (2025) Figure 5 image ("Steamboat geothermal
complex configuration with average flow rates and temperatures in
2024"), which is the authoritative source for the whole network --
superseding all earlier name-pattern guesses.

- **`vw_well_flow_network` redesigned into two segment views**
  (`vw_production_to_port`, `vw_port_to_injection`) in
  `database/schema/05_well_network_schema.R`, because the single
  chained view could only return rows where BOTH a
  `Production_Port_Links` row AND a `Port_Injection_Links` row existed
  for the same port -- with zero injection links (before this
  session), it was structurally guaranteed to return 0 rows forever.
  The two segment views let real, partial data (production->port)
  render immediately without waiting on the harder-to-source
  injection-side assignment. `vw_well_flow_network` (full chain) is
  kept for when both legs are confirmed for the same rows.
- **`SB2`/`SB3` merged into one `SB2/3` port**, correcting the
  session-6 guess that split them by well-naming pattern alone. Both
  Figure 5 and the user's own digitized power-plant polygon
  (`Steamboat_power_plant_locations.shp`) show ONE combined port/pad.
  `register_well_network.R` now has a one-time, idempotent migration
  step that merges any pre-existing separate `SB2`/`SB3`
  `Sampling_Ports` rows (and repoints their links) into `SB2/3` on
  every run -- safe to re-run, no-ops once merged.
- **Full production->port->injection network transcribed from Figure
  5** into `data/raw/wells/dhakal_well_network.csv` (superseding all
  earlier partial/guessed port assignments):
  - Lower Steamboat: `{78-29, HA-4, PW-1, PW-2, PW-3}` -> `Galena 1`;
    `{PW 2-1, PW 2-3, PW 2-5, PW 3-1, PW 3-2, PW 3-3, PW 3-4}` ->
    `SB2/3`. Combined Galena 1 + SB2/3 (615 + 941 = 1556 kg/s, exact
    mass-balance match) -> `{IW-1, IW-4, IW-5, IW-6}` (via their
    canonical names `45-28`/`35-28`/`46-28`/`IW-6`) -- **each
    injection well gets two separate link rows (one per port), not a
    merged single flow**, per the user's explicit clarification that
    Lower Steamboat's two ports stay distinguishable/separate from
    each other even though they feed the same injection wells.
  - Middle Steamboat: `{14A-33, 34-32, 44-32, 44A-32}` -> `Galena 3` ->
    `{23-33RD, 43-33}` (454 kg/s) **and also** `{42A-32, 21-32}` --
    confirmed by the user that Middle (Galena 3) and Upper (SBHR)
    genuinely share this second injection pair (the vertical connector
    in the figure is real, not a rendering artifact); this is
    different from Lower Steamboat, which the user confirmed stays
    separate between its own two ports.
  - Upper Steamboat: `{13-5R, 21-5R, 21B-5R, 23-5, 83B-6R, 83C-6ST1}`
    -> `SBHR` -> `{42A-32, 21-32}` (794 kg/s, shared with Galena 3
    above); `{24-5, 41-5}` -> `Galena 2` -> `64A-32` (136 kg/s, a
    separate arrow from Galena 2's other output).
  - `IW-2`/`IW-3` deliberately left with no port: **not** in Figure 5's
    2024 flow diagram at all, consistent with the TFT Compliance
    Reports showing them Idle / Plugged & Abandoned respectively --
    absence here reflects real inactive status, not missing data.
  - New well identified from Table 1 text alone (not previously in the
    ArcGIS wells layer): `PW 2-1` (Lower Steamboat / SB2/3) -- role and
    port known from literature, but still no coordinate.
  - Minor well-name spelling differences noted between Figure 5 and
    the paper's own Table 1 (its production well groupings by thermal
    zone: Upper/Middle/Lower Steamboat) and NOT merged/reconciled
    automatically: `13-5R` (Table 1: `13-5RD`), `83B-6R` (`83B-6RD`),
    `83C-6ST1` (`83C-6`), `23-33RD` (Table 1 doesn't list it at all;
    NBMG's own coordinate match was for a plain `23-33` -- still
    flagged, not resolved, in `dhakal_well_coordinates.csv`).
- **Confirmed distinct, not superseded** (per explicit user
  correction): `PW-1`/`PW-2`/`PW-3` (Galena 1) and
  `PW 2-x`/`PW 3-x` (SB2/3) are genuinely different, separately-located
  wells despite the similar naming -- earlier sessions' "may be
  mislabeled/superseded" flag on `PW-1/2/3` was wrong and has been
  removed from the CSV notes.
- **`export_geopackage.R` rewritten**: `well_flow_network`'s single
  layer replaced with `production_to_port` and `port_to_injection`
  (line layers built the same way as `hydraulic_gradients`, joining
  each view's endpoints to `Wells`/`Sampling_Ports` coordinates). Also
  added `source_arcgis_power_plant_locations` and
  `source_arcgis_wells_dhakal` layers that repackage the user's
  original shapefiles as-is (full original attributes, e.g.
  `Shape_Leng`/`Shape_Area`/`Powerplant`), reprojected to EPSG:4326,
  distinct from the derived `Facility_Areas`/`Wells` tables built from
  them -- so the exact source data handed off is always retrievable,
  not just its processed form.
- **Verified end-to-end on a from-scratch scratch copy**: schema x2,
  `register_well_network()` (24 production links, 15 injection links,
  no duplicate `Wells.well_name` values), `register_well_coordinates()`
  x2, `register_facility_areas()` (all 5 ports now have a centroid
  coordinate, including the merged `SB2/3`), `export_geopackage()` --
  `production_to_port` exports 15 real lines (9 of 24 links still lack
  a well coordinate on one end: `PW-1/2/3`, `PW 2-1`, `13-5R`,
  `21B-5R`, `83B-6R`), `port_to_injection` exports 14 real lines (the
  15th, `Galena 3 -> 23-33RD`, is missing only because `23-33RD` itself
  still has no coordinate -- the flagged NBMG name-mismatch above).
  Scratch copies deleted after testing; **not yet run against the real
  `geochem_operational.sqlite`**.

## Session 9 updates (2026-09-05, continued): well-log schema, parser, and staging pipeline

Built the well-log ingestion path requested for future 3-D subsurface
modeling (depth, water level, slotted interval, elevation, geologic
formation), designed as a reusable function/pipeline stage for any
future batch of well logs, not just the 12 on hand.

- **`data/raw/ndwr/Ormat_well_logs/` (12 NDWR "WELL DRILLER'S REPORT"
  PDFs) checked for extractable text**: only 1 of 12 (`146403.pdf`)
  has a text layer at all, and it is OCR'd with visible recognition
  noise; the other 11 are pure scanned images (0 extractable
  characters) -- OCR would be needed and remains blocked in this
  sandbox (same constraint flagged for the NDEP PRR scans in earlier
  sessions). **`146403.pdf` is not even a Steamboat well** (it's
  "NVGD-MW1" near Gerlach, NV, a different Ormat project) -- kept only
  as a validated parser test fixture, not ingested as Steamboat data.
- **Deliberately reuses existing Wells columns** rather than
  duplicating them: location (`latitude`/`longitude`), elevation
  (`elevation_m`), total depth (`total_depth`), and slotted/screened
  interval (`top_perforation`/`bottom_perforation`) all already
  existed on `Wells` -- the new pipeline only *fills* those (when
  `NULL`), never adds parallel columns. "Static water level" (a
  one-time driller's-report reading, not a time series) is written
  into the existing `Water_Level_Observations` table with
  `method = 'driller_report'`, for the same reason.
- **New schema** (`database/schema/07_well_logs_schema.R`):
  `Well_Log_Documents` (one row per source PDF -- file hash for
  idempotency, whatever lat/lon/depth/slot-interval/static-water-level
  a parse or cross-reference found, `match_method`, verbatim OCR text
  for human review, caveat `flags`) and `Well_Lithology` (structured
  depth-interval formation data, `well_id`/`depth_from_ft`/
  `depth_to_ft`/`description` -- schema exists but is deliberately left
  EMPTY by automation for now; see lithology note below).
- **New reusable parser**: `scripts/ingest/helpers/parse_well_log_pdf.R`
  / `parse_well_log_pdf(path)` -- label-anchored regex extraction
  (well name, county, lat/lon, depth drilled, cased depth, static
  water level, perforation/slot interval, completion date) tolerant of
  the specific OCR noise patterns observed (e.g. digit/letter `0`/`O`
  confusion, corrected with a flagged substitution rather than
  silently). Sanity-checks lat/lon against a Nevada bounding box and
  flags (does not silently "fix") anything outside it -- caught a real
  OCR error this way (`146403.pdf`'s longitude misread as `-719.4...`
  instead of `-119.4...`). **Deliberately does NOT parse the
  lithology/formation table** -- its multi-column layout gets
  word-wrapped and interleaved by OCR (columns bleed across rows),
  a real table-structure-recovery problem needing a
  `pdftools::pdf_data()`-based positional parser, not attempted here
  (same class of gap flagged for the NDEP TFT Appendix D tables
  earlier). The raw OCR text is returned/stored verbatim instead, for
  a human to read directly.
- **New ingestion script**: `scripts/ingest/ingest_well_logs.R` --
  `ingest_well_logs(con, log_dir = ...)` processes any directory of
  these PDFs (not hardcoded to today's 12), tries the parser, and
  *regardless* of text-layer status also cross-references the
  filename (assumed to be the NDWR log number) against the
  already-ingested NDWR WellLogQuery basin tables (TM/PV htm exports)
  for owner/PLSS-location/coordinates/completion date -- this is how
  7 of the 11 scanned files still got real coordinates despite zero
  OCR. Idempotent on `(file_path, file_hash)`.
- **Identity is NOT guessed**: an NDWR cross-reference only ever
  supplies a bare owner name (e.g. "ORMAT", "ORMAT NEVADA") plus PLSS
  location -- never a specific well name like "78-29" -- so
  `Well_Log_Documents.well_id` stays `NULL` for all 12 documents.
  `promote_well_log_documents(con, map_csv = "data/raw/ndwr/
  well_log_document_map.csv")` is a separate, human-driven promotion
  step (mirrors `promote_staged_ndep.R`'s philosophy exactly) that
  only fills `Wells`/`Water_Level_Observations` once a person supplies
  a `log_number -> well_name` mapping; the CSV currently exists but is
  empty (header only) since no confident matches exist yet.
- **Verified end-to-end** on a scratch copy: `ingest_well_logs()`
  (12 processed, 1 text-layer, 7 cross-referenced, re-run correctly
  skips all 12), and the promotion mechanism (tested with a temporary
  synthetic well/mapping, confirmed it fills `top_perforation`/
  `bottom_perforation` and inserts a `Water_Level_Observations` row
  correctly, then removed). Scratch copy deleted after testing.
- **Applied to the real `geochem_operational.sqlite`** (already backed
  up earlier this session): schema created, all 12 documents staged
  (0 promoted, as expected with an empty mapping file).
- Wired into `run_pipeline.R` as `RUN_INGEST$well_logs` (`TRUE` in
  profiles 1/2, `FALSE` in 3), sourcing `07_well_logs_schema.R`
  alongside 01-06 and calling `ingest_well_logs()` +
  `promote_well_log_documents()` in its own stage.
- **Next step for this thread**: to get anything beyond bare
  owner/location out of these logs, either (a) get OCR working in a
  non-sandboxed session, or (b) a human reads the scanned PDF images
  directly and fills in `well_log_document_map.csv` with confirmed
  `log_number -> well_name` pairs -- at which point
  `promote_well_log_documents()` already knows what to do with them.

## Session 10 updates (2026-09-05, continued): OCR unblocked, well-log parser hardened

User asked to revisit OCR "in a non-sandboxed R session" -- turned out
the *tool* sandbox restriction (not the R session identity) was the
actual blocker, and it was fixable rather than a hard wall as prior
sessions assumed.

- **Root cause found and fixed**: `tesseract`'s `.onLoad` calls
  `rappdirs::user_data_dir()` to find/create a cache directory for
  trained-language data, which on this machine resolves to
  `C:\Users\<user>\AppData\Local\...` -- outside the project, so the
  sandbox blocks the `dir.create()`. `rappdirs::user_data_dir()`
  checks the `R_USER_DATA_DIR` environment variable *first*, before
  falling back to the OS path. Setting
  `Sys.setenv(R_USER_DATA_DIR = "<path inside project>/.tesseract_cache")`
  **before** `library(tesseract)` redirects the cache into the
  project and the package loads cleanly. Wrapped as
  `.ensure_tesseract()` in `parse_well_log_pdf.R` so this happens
  automatically and only once per session.
- **`parse_well_log_pdf.R` substantially rewritten** with real OCR
  support (`.ocr_pdf()`: renders each page via `pdftools::pdf_convert()`
  at 400 dpi, then `tesseract::ocr()`) and, critically, **ground-truthed
  against the user's own scanned images** for logs 125850, 123802, and
  103616 (the user attached photos of the actual forms) -- this is
  what separates real fixes from guesses in what follows:
  - **Lat/lon now has three fallback levels**, tried in order,
    because different forms carry it differently: (1) a labeled
    `Latitude:`/`Longitude:` field (most forms); (2) an unlabeled,
    often handwritten-looking annotation elsewhere on the page for
    forms where the label doesn't survive OCR near the value at all
    (`.scan_any_latlon()` -- validated on 125850, landing within
    ~100-150 m of the true 39.38951/-119.76694); (3) UTM Easting/
    Northing conversion (`.extract_utm_latlon()`, NAD83 UTM Zone 11N
    -> WGS84 via `sf::st_transform()`) for forms that leave the
    decimal lat/lon blank entirely and only fill in UTM -- confirmed
    on 123802's real form (Latitude/Longitude fields genuinely blank;
    UTM E=263623 converts to -119.7445, matching the expected
    Steamboat-cluster location exactly). `latlon_method` on the
    output records which level actually supplied the value.
  - Longitude auto-corrected (with a flag, not silently) when found
    positive in the 113-121 magnitude range -- confirmed necessary:
    103616's real form prints "119.75474" with no minus sign at all.
  - **Confirmed, NOT fixable**: OCR sometimes misreads individual
    digits even when the right field is correctly located -- e.g.
    103616's true Depth Drilled/Cased is 552/552 ft (from the scanned
    image), but came back as 582/852 at 300 dpi. Bumping render
    resolution to 400 dpi fixed this specific case (552/552 came back
    correctly at 400 dpi) but this is not guaranteed in general;
    depth/water-level/perforation numbers from OCR should be
    spot-checked for anything depth-critical, not trusted blindly.
  - Lithology table extraction remains a best-effort, explicitly
    UNVALIDATED heuristic (`lithology_intervals` attribute) -- the
    real multi-column tables still don't reconstruct reliably from
    OCR text alone; raw OCR text is always kept for human review.
- **`ingest_well_logs.R`**: added a `force_reprocess` parameter
  (deletes existing `Well_Log_Documents` rows for the directory before
  re-parsing) since the PDFs' file hash doesn't change when only the
  *extraction logic* improves -- needed to actually pick up the new
  OCR path for files already staged (without it) in session 9.
- **Re-ran against both a scratch copy and the real
  `geochem_operational.sqlite`** with `force_reprocess = TRUE`: all 12
  documents now have `has_text_layer = 1` (OCR succeeded on all of
  them) and all 12 now have coordinates (previously only 7, via the
  NDWR log-number cross-reference; OCR/UTM conversion supplied the
  other 5). Confirmed 5 of the 12 (`146238`-`146241`, `146403`) are
  genuinely NVGD-prefixed Gerlach-area wells (lat ~40.28-40.34),
  **not** Steamboat -- consistent with session 9's finding for
  `146403` alone, now confirmed for the other 4 too via their own
  OCR'd well names/coordinates.
- **Still unresolved / not attempted**: no well_id promotion happened
  (`well_log_document_map.csv` is still empty -- OCR gives location
  and rough construction numbers, not a confident specific-well
  identity like "78-29"); reliable structured lithology-interval
  extraction; and generalizing `.extract_utm_latlon()`'s hardcoded
  UTM Zone 11N assumption if this parser is ever pointed at well logs
  outside northwestern Nevada.

## Session 10 continued: spatial matching attempt for the 7 Steamboat well logs

With coordinates now in hand for all 12 well logs (see above), tried
nearest-neighbor matching against (a) this project's own `Wells`
table (99 coordinate-having rows) and (b) the much larger statewide
NBMG `Geothermal_Wells.csv` (262 rows in the Steamboat bounding box)
to see if any of the 7 real Steamboat-area logs (excluding the 5
confirmed-Gerlach ones) could be confidently identified. Confirmed:
all 7 genuinely fall within the Steamboat field (lat 39.38-39.41,
lon -119.74 to -119.77).

- **One strong candidate**: log `123802` sits only **18 m** from
  NBMG's "Industrial Production Well 43-33" (Ormat) -- by far the
  tightest match found. Caveat worth resolving before promoting it:
  the log's own OCR'd "PROPOSED USE" checkbox says "Monitor," while
  NBMG lists 43-33's function as "Production" -- possibly the same
  well being permitted for a secondary monitoring use, or a
  dedicated small monitor well drilled immediately adjacent to 43-33.
  Not written to `well_log_document_map.csv` -- flagged for the user
  to confirm first (18 m is well within plausible GPS/digitization
  noise for either explanation, so it isn't dispositive on its own).
- **Everything else is "in the neighborhood," not confidently
  identified** -- distances of 54-1450 m to a named well/point,
  which is too far to claim identity in a densely-drilled field
  (real distinct wells routinely sit 100-500 m apart here). Nearest
  named features for reference (user asked to have these "pointed
  to" rather than guessed):
  - `102799` (39.38797, -119.7477): nearest USGS "Auger Hole" test
    holes (~120-150 m, unlikely candidates -- 1960s-era shallow
    holes) and Ormat's "Well No. 21-33" thermal gradient well (196 m).
  - `103616` (39.40739, -119.7547): nearest is "Herz Domestic Well
    1/2" (54-70 m) -- almost certainly coincidental proximity, not
    identity: this log's owner is "Ormat Nevada," not the Herz family,
    and its OCR'd address is 1565 Wedge Pkwy. Likely a distinct,
    not-yet-cataloged Ormat monitor well built near the Herz
    property.
  - `125850` (39.38952, -119.767): nearest is Ormat's "Injection Well
    21-32" (147 m).
  - `125851` (39.38822, -119.7675): nearest is Ormat's "Well No.
    64-32" (83 m, P&A).
  - `27731` (39.39797, -119.7538): nearest are several 1986-era
    SBGeo, Inc. wells -- "Injection Well No. 3" (133 m, P&A),
    "Observation Well No. 3/4" (165-177 m, In Use). Consistent with
    this log's own completion date (8/15/1986, per the earlier NDWR
    cross-reference) and SBGeo being the original 1986-era Steamboat
    operator (per Dhakal et al. 2025's development history) -- this
    is very likely one of SBGeo's original observation/injection
    wells from that era, just not confidently which specific one.
  - `27732` (39.39436, -119.7538): nearest are SBGeo's "Production
    Well No. 2" (98 m, In Use) and "Observation Well No. 1" (137 m,
    In Use).
- **Not done**: writing any of these into `well_log_document_map.csv`
  -- even the 18 m match is presented as a strong lead for the user
  to confirm, not silently promoted, consistent with this project's
  standing rule to never guess a specific-well identity from
  proximity/owner-name evidence alone.

## Session 11 updates (2026-09-05, continued): well-log/NBMG date cross-check, data-availability chart, well-log promotion, README/website/notebook refresh

Large multi-part follow-up session covering well-log identity
resolution, a new "data availability through time" reporting layer, two
real bugs found/fixed along the way, and a documentation/website pass.

- **Well log 123802 vs. 43-33: confirmed NOT a match.** Cross-checking
  `data/raw/nbmg/Geothermal_Wells.csv` by BOTH location and completion
  date (previously only location had been checked) shows 123802 was
  completed 9/24/2015 (NDWR log-number cross-reference, permit
  WL150094) while 43-33 -- its closest NBMG neighbor at just 19.5 m --
  was drilled in 2007, an 8-year gap. Applying the same location+date
  check to the other 6 real Steamboat logs found exactly one comparably
  tight lead: log 27731 (completed 8/15/1986) sits 133 m from NBMG's
  "Injection Well No. 3" (SBGeo, completed 8/8/1986, one week apart).
  Per the user's judgment, 1986-era Steamboat drilling moved fast enough
  that this is more likely a genuinely distinct well than the same well
  misdated -- **not** written to `well_log_document_map.csv`.
- **All 7 real (non-Gerlach) Steamboat well logs now registered as
  provisional `Wells` rows** via new `register_provisional_well_logs()`
  in `scripts/ingest/ingest_well_logs.R` (wired into `run_pipeline.R`
  right after `promote_well_log_documents()`), named
  `"Unidentified Well (NDWR Log <log_number>)"`, `well_role='unknown'`,
  `coordinate_source` recording OCR-vs-NDWR-crossref provenance. This
  makes the real coordinate/depth/perforation/static-water-level data
  visible/mappable instead of stranded in `Well_Log_Documents` staging,
  without claiming any confirmed identity. Applied to the real
  `geochem_operational.sqlite` (backed up first to
  `database/archive/geochem_operational_pre_provisional_wells_<ts>.sqlite`).
- **Two real bugs found and fixed while building this:**
  1. **`promote_well_log_documents()` and the new
     `register_provisional_well_logs()` both stored an unparseable OCR
     completion-date string (e.g. `"OF en"`) or a `Sys.time()`
     ("today") fallback directly as a `Water_Level_Observations`
     timestamp** -- caught by inspecting the new data-availability
     chart, which showed an implausible "most recent water level
     observation: today." Fixed with a new `.safe_completion_date()`
     helper (tries several date formats, then a bare-4-digit-year
     fallback, else `NA` -- skips the observation row entirely rather
     than inventing a date) in both functions. Two already-inserted bad
     rows deleted from the operational database.
  2. **`Sampling_Events.date` mixes two different numeric epoch
     conventions within the same column**: recent rows use Excel-serial
     (days since 1899-12-30), but ~723 of 759 rows are actually
     Unix-epoch-days (days since 1970-01-01) -- e.g. raw value 6502
     parses to a nonsensical 1917-10-19 under the Excel assumption, but
     is exactly correct for 1987-10-21 under the Unix-epoch-day
     assumption, which matches that row's own `external_event_id`
     (`"SB10_1987-10-21"`). Root cause (which ingest script wrote the
     bad rows) is **not yet identified** -- flagged for follow-up, not
     fixed at the source. Worked around read-only in the new
     `.parse_mixed_event_date()` (in `scripts/analysis/
     data_availability.R`), which trusts a `YYYY-MM-DD` suffix on
     `external_event_id` over the ambiguous numeric column whenever one
     is present (749 of 759 rows have one).
- **New "data availability through time" reporting layer**
  (`scripts/analysis/data_availability.R`,
  `compute_data_availability()`/`plot_data_availability()`/
  `build_data_availability_outputs()`) -- a sideways (horizontal)
  bar/Gantt-style chart, one bar per source spanning its earliest to
  latest dated record, colored by data type (continuous logger /
  discrete event / external time series). Covers chemistry sampling
  events, water level observations, temperature/conductivity logger
  observations, live USGS discharge, historic USGS specific
  conductance, NOAA weather, and photo-linked field observations.
  Deliberately excludes well-log completion dates (too irregular/OCR-
  noisy to trust as a real range). Wired into `run_pipeline.R`'s export
  stage unconditionally (read-only reporting, no `RUN_INGEST` flag) --
  writes `data/derived/data_availability/data_availability.csv` and
  `output/figures/data_availability_timeline.png`.
- **New notebook**: `notebooks/05_data_inventory_and_well_network.qmd`
  -- the living reference for the data-availability chart and the
  well/facility flow network + well-log identity-matching work (which
  didn't have a natural home in `01`, which is specifically about the
  conductivity/Cl workstream). Rendered successfully end-to-end against
  the real operational database. Note for future editors: this
  project's notebooks execute with the *notebook's own directory*
  (`notebooks/`) as the working directory when rendered via `quarto
  render` (Quarto project `execute-dir` default), not the repo root --
  `05`'s setup chunk uses a `file.exists()`-based fallback between
  `"database/..."` and `"../database/..."` to work either way; consider
  applying the same pattern to `01`-`04` if they're ever rendered from
  a different starting directory than whatever made them work
  originally.
- **Leaflet maps on the website (`website/data.Rmd`, `website/results.Rmd`)
  reworked**: previously showed only `Wells` with a bare `"Well: <id>"`
  popup. Now show `well_name` (falling back to `"Well <id>"` only when
  genuinely unnamed) colored by `well_role`, **plus a new layer for
  springs/seeps/other `Locations`** (previously absent entirely) with
  their own popups and a toggleable layer control. Backing CSV export
  in `run_pipeline.R` extended (`well_sample.csv` now includes
  `well_name`/`well_role`, filtered to non-null coordinates; new
  `locations_sample.csv` added for the springs/seeps layer). Both CSVs
  regenerated directly against the real operational database this
  session (not just the next full pipeline run).
- **`scripts/pipeline_report.Rmd` extended**: table-counts list expanded
  to include `Conductivity_Observations`, `Sampling_Events`,
  `Lab_Analyses`, `Isotope_Analyses`, `Well_Log_Documents`,
  `Sampling_Ports`, `Production_Port_Links`, `Port_Injection_Links`,
  `Facility_Areas` (previously only 5 core tables); new "Data
  Availability" section embedding the chart above; new "Well & Facility
  Flow Network Summary" section (wells by role, production wells per
  port). Test-rendered successfully against the real operational
  database.
- **README.md substantially expanded**: new "Data Availability
  Reporting" and "Well & Facility Flow Network" top-level sections; new
  rows in the "New data-drop locations" table (conductivity loggers,
  well-log PDFs, well-network CSVs, well-coordinate CSVs, ArcGIS
  shapefiles); a "Status (2026-09-05)" note added to "PHREEQC
  Integration" flagging that `scripts/phreeqc/09_build_phreeqc_tables.R`
  exists but is **not wired into `run_pipeline.R`** and was not audited
  this session -- next major integration priority once the well-network
  and sampling-frequency threads stabilize; new "Interactive Entry
  Point" / "Manual Confirmation / Promotion Steps" / "Version-
  Controlling New Raw-Data Files" subsections under "User Data
  Ingestion," consolidating patterns that were previously only
  documented ad hoc in AGENTS.md session notes (the `register_*`/
  `promote_*` staging philosophy, and the `git add -f` requirement for
  tracking hand-maintained CSVs inside the gitignored `data/raw/`).
- **`2-1` confirmed and merged into `PW 2-1`** (user: "2-1 is PW 2-1,
  just another name; PW-1 is its own name but with other aliases").
  Found the DB already had two separate `Wells` rows for this (well_id
  82 = `PW 2-1`, no coordinate; well_id 111 = `2-1`, with a real
  ArcGIS-digitized coordinate) -- confirmed well_id 111 had zero
  dependent rows in any link/observation table, then: added a
  `Well_Aliases` row (`PW 2-1` -> `2-1`, `alias_type='other'`, the
  schema's `CHECK` only allows `dhakal_diagram`/`uic_permit`/
  `historical_gs_number`/`ndwr_permit`/`other`) to
  `data/raw/wells/well_aliases.csv`; deleted the redundant `Wells` row
  for well_id 111; removed the now-superseded standalone `2-1` row from
  `data/raw/wells/dhakal_well_network.csv`; re-ran
  `register_well_network()`/`register_well_coordinates()`, which
  resolved `2-1`'s coordinate onto canonical `PW 2-1` (well_id 82) via
  the alias-fallback mechanism built in session 7. `PW-1/2/3` remain
  confirmed distinct from `PW 2-x`/`PW 3-x` (no change needed -- already
  correctly noted as distinct in `dhakal_well_network.csv` since session
  8). `docs/data/well_sample.csv` re-exported to reflect the merge.
- **Not done this session** (deferred, not forgotten): the docs/
  literature/ PDFs commit-to-git question is still open; root-causing
  the `Sampling_Events.date` dual-epoch
  bug; auditing/wiring up `scripts/phreeqc/09_build_phreeqc_tables.R`;
  none of this session's file changes have been committed/pushed to git
  yet (several touch CRLF files -- `scripts/run_pipeline.R`,
  `scripts/ingest/ingest_well_logs.R`, `scripts/pipeline_report.Rmd`,
  `README.md`, `website/results.Rmd` -- all edited via a
  `readLines()`/`writeLines(sep="\r\n")` round-trip this session since
  the `edit` tool's exact-string matching intermittently failed against
  them for reasons not fully diagnosed, consistent with -- but somewhat
  worse than -- prior sessions' CRLF caveats for `run_pipeline.R`
  specifically).

## Session 12 updates (2026-09-06): full website overhaul, references page, critical render_site() data-loss bug fixed

User requested a full website redesign (more technical/narrative tone,
fewer small bulleted sections, live-data-driven paragraphs, a dedicated
References page, and explicit "what's next" framing for PHREEQC/Cl-SC
calibration/potentiometric-transport modeling), plus a git commit/push
excluding literature PDFs.

- **All 6 website pages rewritten** (`website/index.Rmd`,
  `project.Rmd`, `pipeline.Rmd`, `data.Rmd`, `results.Rmd`,
  `about.Rmd`) plus a **new `references.Rmd`** (added to the navbar):
  consolidated dozens of small emoji-bulleted sections into longer
  flowing paragraphs; added a hero banner and live-computed "stat card"
  summary (`index.Rmd`, pulling real counts from `docs/data/*.csv` at
  render time -- wells/springs mapped, temperature/conductivity/water-
  level reading counts, lab analyses); embedded the session-11 data-
  availability chart on the homepage; added an explicit three-objective
  framing (outflow characterization, Cl-conductivity calibration,
  potentiometric/transport mapping) matching this project's actual
  thesis scope; added three `.callout-box.future` sections on
  `results.Rmd` stating exactly where PHREEQC, Cl-SC calibration, and
  ArcGIS potentiometric/transport interpolation each stand today (none
  presented as done -- PHREEQC is an unwired starter script, Cl-SC
  calibration is built/self-tested but waiting on real overlapping
  chloride samples, and the ArcGIS interpolation step hasn't been built
  at all yet).
- **New theme**: `website/styles.css` rewritten with a geothermal-
  themed palette (deep blue-green + rust/amber accents) layered on the
  existing "flatly" Bootstrap theme, serif headings, a hero-banner
  class, stat-card grid, and styled callout boxes; `_site.yml` updated
  with the References nav entry and a GitHub icon link.
- **New `references.Rmd`**: full bibliographic citations (not re-hosted
  PDFs) for Dhakal et al. (2025, verified via web search: *Forty Years
  of Production from the Steamboat Geothermal Field: Numerical Model
  Update*, 50th Stanford Geothermal Workshop, SGP-TR-228), Klein,
  Johnson & Spielman (2007, verified: *Exploitation at Steamboat,
  Nevada...*, GRC Transactions Vol. 31 -- corrected from this file's
  earlier paraphrased title), Sorey & Spielman (Cl-flux GRC papers,
  cited with an honest caveat that the exact 2008/2017 bibliographic
  details are from project working notes and not independently
  re-verified this session), White et al. (1964, USGS PP 458-B), White
  (1968, USGS PP 458-C), Cohen & Loeltz (1964, USGS WSP 1779-S), Mariner
  & Janik (flagged explicitly as "citation under review" rather than
  guessed), plus the public agency/software sources (NDEP, NDWR, NBMG
  ArcGIS Geothermal_Wells dataset with its real URL, USGS, NOAA,
  PHREEQC, R ecosystem). Per the user's explicit instruction, no
  literature PDFs were added to the repo -- sources are cited, not
  re-hosted.
- **Critical, previously-undiscovered bug found and fixed**:
  `rmarkdown::render_site("website")` actively deletes any file under
  `docs/` (the site's `output_dir`) that has no corresponding source in
  `website/`'s own input tree -- this is standard site-generator
  cleanup behavior, but it collided catastrophically with this
  project's pattern of having `run_pipeline.R` write chart-backing CSVs
  directly into `docs/data/` for the Rmd chunks to read at render time.
  Compounding this: `website/data/`, `website/database/`, and
  `website/scripts/` turned out to be stale (dated June 9, i.e.
  3-months-old), accidentally-committed duplicate copies of this
  project's real `data/`, `database/`, and `scripts/` directories,
  sitting *inside* the website source folder -- every site rebuild was
  silently overwriting freshly-exported `docs/data/*.csv` files with
  these ancient duplicates (explaining several stale numbers this
  session, like a "Wells: 73" count that had already grown to 117).
  Deleted all three stale directories (confirmed zero unique content
  first -- they were exact, longstanding duplicates). But removing them
  fully exposed the deeper problem: with no `website/data/` left to
  partially mask it, `render_site()` deleted `docs/data/` **in its
  entirety**, since nothing in `website/`'s input tree referenced it at
  all. **Root-cause fix**: `scripts/run_pipeline.R`'s CSV-export block
  was refactored into a new `export_website_data_files(con)` function,
  now called *twice* -- once immediately before `build_website()` (so
  the Rmd charts render against real data) and once immediately after
  (so the CSVs still exist afterward, surviving `render_site()`'s
  cleanup, for direct download or the next pipeline stage). Verified
  end-to-end: ran the export -> render -> export sequence directly and
  confirmed all 9 `docs/data/*.csv` files survive with correct row
  counts after the full sequence completes.
- Also fixed a smaller bug of this session's own making: `project.Rmd`
  referenced `temp_path <- "docs/data/temp_sample.csv"` (missing the
  `../` prefix every other page's chunks use) -- silently fell back to
  its "data will appear after export" placeholder text instead of
  erroring, which is how it went unnoticed until a deliberate check.
- **`results.Rmd`'s interactive `ggplotly()` temperature chart** was
  embedding the *entire* ~200k-row temperature record inline in the
  page (20 MB rendered HTML) -- thinned to every 15th point per logger
  (`group_by(logger_id) %>% slice(seq(1, n(), by = 15))`), cutting
  `results.html` to ~1.4 MB with no visible change to the plotted
  pattern.
- `docs/database/`, `docs/scripts/` (the corresponding stale copies
  that had been committed into the *published site output* itself, not
  just the website source) are now correctly gone from git's tracked
  tree as well, following the same deletion.
- **Second related bug, same root cause**: the data-availability figure
  embedded on the new homepage was referenced from `output/figures/`,
  which is entirely gitignored (rebuildable scratch space) -- meaning
  it would 404 on the live GitHub Pages site even though it rendered
  fine locally. Fixed by having `export_website_data_files()` also copy
  it to `docs/figures/data_availability_timeline.png` (creating that
  directory every call, since `render_site()`'s cleanup deletes it too)
  and pointing `index.Rmd` at that copy instead.
- Not done this session: `docs/data/qc_summary.csv` (written by
  `scripts/qc/qc_data_integrity_checks.R`, not currently read by any
  website page) was not added to the new `export_website_data_files()`
  double-call pattern -- low priority since nothing displays it, but
  worth folding in if a future page starts using it, for the same
  reason the other nine files needed it.

## Session 13 updates (2026-09-06, continued): Timeline page, GRC poster/QR integration, logger maps, a real data-loss incident, and a systemic CRLF bug

Large follow-up to Session 12's website overhaul, covering a real photo/
video-driven Timeline page, integrating the user's own GRC poster
(co-authored with Cary Lindsey), two independent critical bugs found and
fixed (one causing real, unrecoverable data loss), and a project-wide
line-ending audit the user explicitly requested.

- **New Timeline page** (`website/timeline.Rmd`, added to the navbar):
  dated entirely from each asset's own embedded EXIF capture timestamp
  (and GPS, where present) rather than a remembered date -- covers 2022
  steaming-ground onset through the 2026-02 Lindsey et al. publication.
  Real photos viewed directly (via resized thumbnails under the `read`
  tool's 5 MB limit) to write accurate captions rather than guessing
  from filenames alone; corrected mid-session per user feedback that the
  well was capped *shortly after* the June 2025 eruption, not in
  January 2026 (confirmed against Lindsey et al.'s text: "the eruption
  briefly generated a geyser-like column... before the pipe was capped
  ... discharge did not cease but instead shifted laterally"). A second
  video (a January 2026 "walkaround" of the steaming fissure) was
  later removed per user request, folded into the existing photo
  caption as prose instead of its own embed.
- **`ingest_image_locations.R` extended to scan video files** (mp4/mov/
  m4v) for embedded GPS via exiftool, alongside the still-image formats
  it already handled. Tested against all 7 real 2025-2026 event assets
  on a scratch DB copy: correctly extracted the one real GPS fix
  present (a Dec-2025 photo) and cleanly skipped the six files with no
  location tag (most drone/phone video checked so far carries no
  embedded GPS at all) rather than erroring -- confirms the pipeline
  is ready for future geotagged video, though these particular clips
  still need a manual coordinate/station code in
  `image_location_map.csv` like any un-geotagged photo would.
- **Critical bug #1 -- real, unrecoverable data loss.** Calling
  `rmarkdown::render_site("website")` directly (bypassing
  `run_pipeline.R`'s wrapper) deleted ~26 of the ~29 files then in
  `docs/literature/` -- a user-maintained, entirely untracked folder of
  reference PDFs with no git history to recover from -- because
  `render_site()`'s standard cleanup deletes anything under its
  `output_dir` with no counterpart in the site's own input tree, the
  same bug class already fixed for `docs/data/`/`docs/figures/` in
  Session 12 but never extended to literature. Not recoverable from the
  Recycle Bin either (R's file deletion bypasses it). Disclosed to the
  user immediately and in full (exact file list, root cause, no
  minimizing); the user re-attached the files from their own Downloads
  folder. **Fixed at the root**: `build_website()` in `run_pipeline.R`
  now backs up `docs/literature/` to a temp directory before calling
  `render_site()` and restores it verbatim afterward, living inside the
  function itself (not just a gated caller) so the protection applies
  regardless of how/where `build_website()` is invoked. Verified twice
  against the real, now-32-file `docs/literature/` (the user also added
  a few more references while re-attaching) across multiple real
  renders this session. `docs/literature/` is also now explicitly
  gitignored (previously just untracked by omission) -- consistent
  with `references.Rmd`'s own stated citation-not-rehosting policy, and
  necessary anyway since it's genuinely huge (~431 MB, mostly full-
  resolution 1960s USGS plate scans).
- **Critical bug #2 -- `results_files/` gitignore collision.** A bare
  `results_files/` rule (intended for some other, no-longer-existent
  folder) was matching `docs/results_files/` too, since gitignore
  patterns with no leading slash match at any depth -- this is the
  knitr figure-output folder `results.Rmd`'s plots render into, so the
  Results page's second chart (temperature-by-logger boxplot) was
  silently never committed and appeared broken on the live GitHub Pages
  site, exactly matching the user's bug report. Fixed by removing the
  rule (confirmed via `find` that no other `results_files` directory
  exists anywhere in the repo) and committing `docs/results_files/` for
  the first time.
- **Critical bug #3 -- systemic CRLF doubling, found via a project-wide
  audit the user explicitly requested ("do a brief crlf check").** Root
  cause: on this Windows R installation, `writeLines(x, con, sep =
  "\r\n")` opens a text-mode connection that itself auto-translates
  every `\n` to `\r\n`; passing an explicit `"\r\n"` separator gets its
  own trailing `\n` translated a second time, silently doubling the
  carriage return to `\r\r\n`. This is exactly what broke
  `website/timeline.Rmd`'s YAML front matter earlier this session
  (pandoc fell back to rendering the literal `title:`/`output:` text
  instead of parsing it, and the page's `<title>` fell back to the
  knit filename) -- and a full-repo scan (`grep -U $'\r\r'`) found the
  same corruption, silently tolerated by pandoc so it never visibly
  broke rendering, in `website/{about,data,index,pipeline,project,
  results}.Rmd`, `_site.yml`, `styles.css`, and `run_pipeline.R`
  itself. **Also briefly corrupted `.gitignore` mid-session** while
  fixing the `results_files/` bug above, which silently stopped it
  from ignoring anything at all (including `data/raw/` and the
  `.sqlite` databases) until caught by `git status` unexpectedly
  showing files that should have been invisible. Fixed everywhere by
  stripping all stray/doubled CR then rewriting with a plain `"\n"`
  separator (letting Windows perform the single, correct translation
  itself) instead of an explicit CRLF separator -- **this is now the
  standing rule for any future CRLF round-trip on this project**,
  documented permanently in README.md's Troubleshooting section, not
  just here. Verified clean via a repeated full-repo scan and a real
  re-render (all page titles correct, `docs/literature/` still intact,
  zero remaining corruption).
- **Aggressive `&mdash;` reduction, especially on the Pipeline page per
  explicit request.** Went from dozens of instances across all six
  original pages down to zero anywhere on the site, converting each to
  a colon, semicolon, comma, or parenthetical depending on context.
- **GRC poster integration.** Read the user's actual poster PDF
  (`docs/literature/GRC_2026_Steamboat.pdf`, co-authored with Cary
  Lindsey) directly for its real content rather than guessing: title,
  authors, the chloride mass-balance formula, the ~27 L/s current
  thermal-inflow estimate (vs. the 60 L/s / 45-90 L/s range Sorey &
  Spielman 2017 reported for 2008-2016), the r = -0.68 paired-logger
  correlation, and the conduit-reactivation-not-new-source conclusion.
  Added as a full citation in `references.Rmd`, a substantive (clearly
  poster-stage, not pipeline-verified) finding on `results.Rmd`, and a
  tie-in sentence in `project.Rmd`.
- **QR code**: generated three versions with the `qrcode` R package in
  `website/assets/qr/` (themed, print-safe black-on-white, and a
  captioned poster-ready PNG with the URL beneath), all pointing at the
  live GitHub Pages URL -- confirmed live and reachable via `webfetch`
  before generating. New "Scan to Follow This Work" section on
  `about.Rmd` explains the poster connection.
- **Logger layers on both leaflet maps** (`data.Rmd`, `results.Rmd`):
  temperature loggers (amber dots) and conductivity loggers (hollow
  rust rings), each its own toggleable group, backed by new
  `temp_logger_locations.csv`/`cond_logger_locations.csv` exports in
  `export_website_data_files()`. Confirmed real co-location at SBRR
  (both logger types share the identical coordinate) directly from the
  database rather than assuming it.
- **USGS live-gauge link**: added the user-supplied direct URL for
  station 10349300's live monitoring-location page (continuous gage
  height, co-located with the SBRR conductivity logger) to
  `references.Rmd`, `data.Rmd`, and the Overview page.
- **Sorey citations split and verified**: the previous vague, unverified
  "2008 and 2017 papers referenced in project working notes" placeholder
  is now two full, independently-read citations -- Sorey & Spielman
  (2008, GRC Transactions, Vol. 32, "Thermal-Water Discharge from
  Steamboat Hills Geothermal System") and Sorey & Spielman (2017,
  Geothermics 69, "Rates of Thermal Water Discharge from the Hot Water
  Geothermal System Beneath the Steamboat Hills in Western Nevada,
  USA") -- both read directly from the PDFs the user placed in
  `docs/literature/`.
- **Visual polish**: photo-based hero banner (real eruption photo with
  a readable gradient overlay), a "live/growing" badge, a featured-
  finding callout on the homepage tied to the poster result, and subtle
  hover states on stat cards/callouts/timeline media.
- **Video compression**: the two raw event videos (originally ~125 MB
  combined) re-encoded with the `av` R package (854 px width, 15 fps,
  libx264) to ~14.7 MB total for `website/assets/video_compressed/`,
  installed after confirming no system `ffmpeg` binary exists anywhere
  on this machine (the `av` package bundles its own). Original full-
  resolution photos and videos relocated from `website/assets/` into
  `data/raw/images/image_drop/` (gitignored, the pipeline's proper raw-
  media home) rather than committed at full size.
- **Not done this session**: `notebooks/01`-`05` were reviewed for
  relevance but not edited -- none reference website structure directly
  enough to need updating; the photo-location workflow notebook
  (`04_photo_location_workflow.qmd`) is the closest candidate for a
  future video-support addendum but was left as-is pending a real
  geotagged-video example to document. All work this session verified
  against the real `geochem_operational.sqlite` and the real
  `docs/literature/`, not scratch copies, given the website-focused
  (not schema-migration-focused) nature of the work.

## Session 14 updates (2026-09-06): PHREEQC geochemical modeling wired in

Built the full PHREEQC integration planned this session (plan file
`2026-09-06-1307-plan.md`), porting the pattern from the user's IGNIS
project (`utils_phreeqc.R`/`07_run_phreeqc.R`) into this project's
per-stage-function/`run_pipeline.R` conventions, replacing the old
never-wired `scripts/phreeqc/09_build_phreeqc_tables.R` (wrong database
file, own `dbConnect()`, hardcoded 8-analyte charge balance,
`overwrite = TRUE` data loss), and extending it with mixing, inverse
modeling, and gas-phase equilibria that IGNIS's own scripts don't have.

- **New files**: `scripts/phreeqc/utils_phreeqc.R` (SOLUTION-block
  generation, `system2()` execution, SELECTED_OUTPUT parsing, the
  6-database registry with temp/TDS-based auto-recommendation, fluid-
  type classification, automated interpretation text -- schema/table
  names adapted throughout, e.g. `l.site_type` in place of IGNIS's
  `l.prospect`, since this project batches PHREEQC runs by
  `Locations.site_type` per this session's confirmed decision, not a
  prospect concept it doesn't have); `08_build_phreeqc_tables.R`
  (`build_phreeqc_solutions(con)`, `get_phreeqc_eligible(con)`, real
  charge balance via `lab_analyte_map.R`'s charge/molar_mass, idempotent
  upsert); `09_run_phreeqc.R` (`run_phreeqc_pipeline()` with
  per-sample fallback-database retry + `PHREEQC_Run_Failures` logging,
  `run_phreeqc_multi()`, `view_phreeqc_results()`, temperature-sweep
  geothermometry, activity-based Na/K geothermometers);
  `10_run_phreeqc_mixing.R` (pure-R two-end-member conservative Cl
  mixing fractions + PHREEQC MIX-block predicted-vs-observed
  comparison, `demo_mixing_model()`); `11_run_phreeqc_inverse.R`
  (PHREEQC `INVERSE_MODELING` mixing + mineral mass-transfer,
  `demo_inverse_model()`); `12_run_phreeqc_gas_phase.R` (CO2/H2S
  `GAS_PHASE` degassing equilibria, `demo_gas_phase()`);
  `run_phreeqc_analysis.R` (single entry point,
  `run_phreeqc_analysis_pipeline(con, mode = ...)`,
  `demo_phreeqc_analysis()` runs all three synthetic self-tests).
- **New schema**: `database/schema/08_phreeqc_schema.R` --
  `PHREEQC_Solutions`, `PHREEQC_Results`, `PHREEQC_Temp_Sweep`,
  `PHREEQC_Run_Failures`, `PHREEQC_Mixing_Runs`/
  `PHREEQC_Mixing_Fractions`/`PHREEQC_Mixing_Results`,
  `PHREEQC_Inverse_Models`/`PHREEQC_Inverse_End_Members`/
  `PHREEQC_Inverse_Results`, `PHREEQC_Gas_Phase_Runs`/
  `PHREEQC_Gas_Phase_Results`. Also enables the previously-disabled
  `Chemistry_Parameters` stub in `01_define_schema.R` (left that file
  untouched; the table is instead created fresh here) and populates it
  from `lab_analyte_map.R`. **Real bug hit and fixed while building
  this**: SQLite treats a bare `As` column name as the `AS` keyword --
  `PHREEQC_Solutions.As` (arsenic) needed `[As]` bracket-quoting in the
  `CREATE TABLE` DDL to avoid a silent "near As: syntax error".
- **Wired into `run_pipeline.R`**: new `RUN_ANALYSIS` flag list
  (deliberately separate from `RUN_INGEST`, since this isn't data
  ingestion), `RUN_ANALYSIS$phreeqc` (default `FALSE` -- calls a slow
  external executable per sample, opt-in only). When `TRUE`, runs
  `build_phreeqc_solutions(con)` + `run_phreeqc_pipeline(con)`
  (speciation/SI only) right after `create_analysis_views(con)`.
  Mixing/inverse/gas-phase stay manual-invocation-only always (never
  auto-run), consistent with `promote_staged_ndep.R`'s philosophy of
  never guessing which real samples are meaningful end-members.
  `qc_data_integrity_checks.R` extended with a new check reading
  `PHREEQC_Run_Failures` (feeds a `phreeqc_run_failures` count into the
  QC summary) alongside its existing (now-actually-firing)
  `PHREEQC_Solutions` completeness/charge-balance check.
- **Real, substantive bug found and fixed via real-data testing (not
  just the synthetic self-tests)**: `database/schema/
  lab_analyte_map.R`'s `phreeqc_name` for `SO4` and `Si` were the
  PHREEQC *species/gfw* names ("SO4", "SiO2") rather than the actual
  PHREEQC *element* names ("S", "Si") that `SOLUTION` blocks require --
  confirmed by running the real pipeline against a scratch copy of
  `geochem_operational.sqlite` and seeing `WARNING: Could not find
  element in database, SO4`/`SiO2` in the raw `.pqo` output, which
  silently dropped sulfate and silica from *every* PHREEQC run (all
  databases, not just LLNL) until fixed. `format_solution_block()`'s
  `as_unit_lookup` extended with `SO4 = "SO4"` to emit the correct
  `S  <value>  as SO4` directive (mirrors the existing `Si  <value>  as
  SiO2` pattern). This class of "does the generated PHREEQC input even
  use real element names" bug would never have been caught by the
  synthetic self-tests alone (which happened to only exercise
  `phreeqc.dat`, not `llnl.dat`, before this) -- worth remembering that
  self-tests validate syntax/plumbing, not necessarily every database's
  naming quirks.
- **Also investigated and resolved as NOT a bug**: `Calcite`/
  `Aragonite`/`Dolomite` SI came back as PHREEQC's `-999.999` "undefined"
  placeholder for all 8 real eligible samples -- traced this to a
  genuine data gap (none of the 8 currently-eligible samples have a
  lab-measured `Alkalinity` value at all, so no carbonate/HCO3 input
  ever reaches the `SOLUTION` block), not a llnl.dat-specific quirk as
  initially suspected. Will start populating automatically once
  alkalinity titrations are added to the lab dataset for these samples
  -- no code change needed.
- **Applied to the real `geochem_operational.sqlite`** (backed up first
  to `database/archive/geochem_operational_pre_phreeqc_<timestamp>.sqlite`):
  schema migration applied, `PHREEQC_Solutions` built (820 rows, 8
  complete/812 incomplete -- incomplete rows are logged with a specific
  missing-field reason via `get_phreeqc_eligible()`, not silently
  dropped), and the real speciation/SI pipeline run end-to-end against
  the 8 eligible real samples (fumarole/seep/spring/transect/well site
  types) using the auto-selected LLNL database (Steamboat's real
  reservoir temperatures exceed 100C) -- 208 real `PHREEQC_Results`
  rows now exist, e.g. quartz/chalcedony SI near equilibrium for 7 of 8
  samples (`interpret_phreeqc_results(con)` surfaces this automatically
  as supporting the quartz geothermometer). QC re-run cleanly afterward
  (`phreeqc_run_failures = 0`, no convergence failures).
- **Mixing/inverse/gas-phase self-tested against synthetic end-members**
  (per this session's confirmed decision, since real Cl chemistry still
  doesn't overlap the conductivity logger deployment closely enough to
  name confident real thermal/meteoric end-members -- see the
  Conductivity Logger section above): all three
  (`demo_mixing_model()`/`demo_inverse_model()`/`demo_gas_phase()`, or
  together via `demo_phreeqc_analysis()`) run PHREEQC to completion
  without error. Getting there required real debugging, not just
  writing the self-tests: (a) the initial synthetic "meteoric"
  end-member was charge-imbalanced by ~26% (an arithmetic error --
  divided instead of multiplied by equivalent weight -- in this
  session's own hand-picked test values, unrelated to any pipeline
  code), fixed by rebalancing its `Alkalinity`; (b) PHREEQC's
  `INVERSE_MODELING` needs an explicit `-balances` sub-block for any
  conservative tracer (Na/Cl/K/Mg here) not already tied to a `-phases`
  entry, or it fails outright with "Not possible to balance solution N
  with input uncertainties" even when every solution's own charge
  balance is well within tolerance -- `format_phreeqc_inverse_input()`
  now defaults to `balance_elements = c("Na","Cl","K","Mg")`; (c) even
  with that fix, the synthetic inverse-model scenario still finds 0
  feasible solutions due to a genuine, documented PHREEQC quirk (a
  ~1e-9 numerical residual on the unused methane/C(-4) redox couple,
  "ERROR: equality not satisfied for C(-4)") -- `demo_inverse_model()`
  now explicitly reports this as a known execution-plumbing pass with 0
  models found, not a false "it works" or a hidden failure; (d) the gas-
  phase self-test's first attempt used `total_pressure_atm = 1.0` (pure
  CO2 at 1 atm), which is *far* above the synthetic solution's own CO2
  fugacity, so a `fixed_pressure` `GAS_PHASE` starting from zero gas
  moles correctly never exchanges any gas (not a bug -- a `fixed_pressure`
  gas phase only exsolves/dissolves gas once the solution's own fugacity
  reaches the target) -- fixed by using an atmospheric CO2 partial
  pressure (`10^-3.5` atm) instead, which now visibly degasses the
  synthetic solution and raises its pH from 6.0 to ~9.
- **Known limitations, honestly documented in code comments** (not
  hidden): `parse_phreeqc_inverse_output()` is a best-effort, line-
  anchored regex parser of PHREEQC's free-text inverse-modeling output
  (PHREEQC does not punch inverse-model solutions to `SELECTED_OUTPUT`)
  -- always cross-check the raw `.pqo` file for anything
  decision-critical; `parse_phreeqc_gas_output()`'s moles/pressure
  columns are gas-phase *totals* from `-gas true`, exactly correct only
  for a single-gas-component phase (fine for the CO2-only default here,
  not rigorously per-component for a genuinely multi-gas mixture).
- **Not done this session** (deferred): no new Quarto notebook for this
  workstream (would mirror notebook `01`'s role for the sampling-
  frequency work) -- README's new "PHREEQC Geochemical Modeling"
  section and `results.Rmd`'s updated callout serve as the written
  record for now; `docs/data/qc_summary.csv`'s still-separate-from-
  `export_website_data_files()` gap (flagged since Session 12) remains
  unaddressed; DEMO database was not rebuilt/exercised with the new
  PHREEQC stage (verified instead via a scratch copy of the real
  operational DB plus the real DB itself, consistent with how schema-
  migration work has been verified in prior sessions); this session's
  file changes are **not yet committed/pushed to git** (touches several
  CRLF files -- `README.md`, `website/results.Rmd`,
  `scripts/run_pipeline.R`, `scripts/qc/qc_data_integrity_checks.R`,
  `database/schema/lab_analyte_map.R`, and the new
  `scripts/phreeqc/11_run_phreeqc_inverse.R` -- all edited via the
  established `readLines()`/`writeLines()` [default `"\n"` separator,
  letting Windows do the single correct `\r\n` translation itself, per
  the Session 13 CRLF rule] round-trip since the `edit` tool's
  exact-string matching intermittently failed against them, same
  caveat as every prior CRLF-file session).

## Session 15 updates (2026-09-06, continued): NDEP+field PHREEQC run -- real alkalinity/unit bugs found and fixed

User asked to run PHREEQC speciation, charge-balance QC, and geothermometry
on existing NDEP data plus field spring/well chemistry. Investigating why
only 8 samples were eligible (see Session 14) surfaced three real,
substantive bugs in the NDEP ingest path, not just a PHREEQC-layer gap.

- **Bug 1 (fixed): NDEP's pH/temperature live in `Lab_Analyses`, not
  `Field_Measurements`.** `ndep_analyte_map.R` correctly maps "pH
  Field/Lab"/"Temp Field/Lab" to analytes `pH`/`temperature`, but
  `ingest_ndep.R` writes everything -- field parameters included -- into
  `Lab_Analyses`. `build_phreeqc_solutions()` (Session 14) only checked
  `Field_Measurements` for these, so every NDEP sample looked like it had
  zero pH/temperature data. Fixed by pulling pH/temperature from both
  tables (preferring `Field_Measurements` when both exist). This alone
  raised PHREEQC-eligible samples from 8 to 233.
- **Bug 2 (fixed): NDEP's minor/trace analytes are stored in mixed units**
  (the same analyte, e.g. `SiO2`/`As`/`B`/`Fe`/`Li`/`Mn`, appears with
  both `ug/L` and `mg/L` rows) because `ingest_ndep.R`'s comment
  "Convert units (if needed)" was never actually implemented.
  `build_phreeqc_solutions()` was naively averaging raw values across
  units -- a ~1000x risk for whichever rows were "wrong" relative to
  others in the average. Fixed by converting every row to mg/L (per its
  own `units` column) before any aggregation.
- **Bug 3 (fixed, the big one): NDEP's authoritative alkalinity parameter,
  "Total Alkalinity as CaCO3", was never ingested at all.** Traced this by
  reading the raw source file directly
  (`data/raw/ndep/NormalizedData.csv`, which still has the original
  `CHARACTERISTICNAME`): `ndep_analyte_map.R` instead mapped BOTH
  "HCO3 as CaCO3 (mg/L)" and "HCO3 as HCO3 (mg/L)" to a single clean
  `HCO3` analyte code. Verified these are the exact same 647 measurement
  events reported in two unit conventions (ratio consistently ~0.82,
  matching the true CaCO3/HCO3 equivalent-weight ratio 50.05/61.02) --
  not independent values -- and that the *actually*-ingested `HCO3`
  values (for the main NDEP source_id) kept whichever raw name happened
  to be encountered first (in practice, the CaCO3-based number, silently
  mislabeled as if it were true HCO3 mg/L). CO3 as CaCO3/CO3 as CO3 show
  the identical duplicate pattern (also unresolved, but CO3 is
  negligible at these near-neutral pHs and isn't fed to PHREEQC anyway).
  **Fix**: added a `conversion_factor` column to `ndep_analyte_map.R`
  (default 1 for every existing row) and a new row mapping "Total
  Alkalinity as CaCO3 (mg/L)" -> clean analyte `Alkalinity`, with
  `conversion_factor = 1.2189` (61.017/50.05) to convert CaCO3-basis mg/L
  to HCO3-basis mg/L, keeping the `Alkalinity` code internally consistent
  with `format_solution_block()`'s fixed `as HCO3` clause everywhere
  else in the project. `parse_ndep_chemistry.R` now multiplies both
  `value` and `detection_limit` by this factor. Re-running `ingest_ndep.R`
  against the real (backed-up) operational database inserted 736 new
  `Alkalinity` rows (range 20-361 mg/L, plausible) -- a previously
  entirely-missing parameter, not a duplicate-cleanup.
- **Bug 4 (fixed, found because Bug 3's fix didn't move the needle at
  first): `lab_analyte_map.R`'s `Alkalinity` row had `charge = 0,
  molar_mass = NA`**, which silently excluded it from every charge-balance
  calculation in `build_phreeqc_solutions()` even after real Alkalinity
  data existed (charge-balance math filters `charge != 0`). Since
  Alkalinity is now stored project-wide as HCO3-mass-equivalent mg/L, the
  correct row is `charge = -1, molar_mass = 61.017` (HCO3's own molar
  mass) -- fixed. This is what actually made the charge-balance numbers
  improve: median imbalance for NDEP's 225 now-complete samples dropped
  from ~60% (an artifact of missing alkalinity, not real chemistry) to
  **0.7%**, with 164 of 225 now passing the standard <=5% QC threshold.
  FIELD's own spring/well samples still have no lab-measured Alkalinity
  at all (a genuine, separate field-sampling gap, not a bug) and
  correctly still flag.
- **Real results now in the database** (after backing up to
  `database/archive/geochem_operational_pre_ndep_alkalinity_<ts>.sqlite`):
  233 samples processed through `run_phreeqc_pipeline(con)` (225 NDEP
  "background" wells/creeks, plus the 8 real thermal FIELD samples from
  Session 14), 6,283 total `PHREEQC_Results` rows, 0 convergence
  failures. The 225-sample NDEP batch didn't converge with the
  auto-recommended LLNL database (tuned for high-T geothermal, not a
  large dilute-water batch) but succeeded cleanly on the SIT fallback --
  exactly the scenario the fallback-database logic was built for.
  `interpret_phreeqc_results(con)` now reports real, substantive
  findings: 96 of 233 samples near calcite equilibrium, 16
  calcite-supersaturated (scaling-relevant), 113 undersaturated
  (dilute/meteoric), and 8 samples (the real thermal ones) near quartz
  equilibrium. **Na/K activity-based geothermometry is only physically
  meaningful for the 8 genuinely thermal samples** (measured field
  temperature 59-162C) -- there it gives sensible, textbook-correct
  reservoir-temperature estimates of 154-256C (Giggenbach) / 154-243C
  (Fournier), systematically *above* measured discharge temperature as
  expected for a cooling/diluting outflow path. Applying the same
  geothermometer to the 225 dilute, cold (median 11C) NDEP background
  creek samples gives nonsensical 300-390C estimates -- the method's
  water-rock-equilibrium assumption doesn't hold for shallow, dilute
  surface water, and these numbers were explicitly flagged as not
  physically meaningful rather than reported at face value.
- **Not resolved / flagged for later**: the duplicate `HCO3`/`CO3` rows
  described in Bug 3 still exist in `Lab_Analyses` as-is (harmless for
  PHREEQC today since neither code is consumed by
  `build_phreeqc_solutions()`, but a real underlying data-quality issue
  for any future use of those columns, e.g. `vw_major_ions`); FIELD's own
  historical "Alkalinity Total" raw values (from `lab_analyte_map.R`,
  independent of this session's NDEP fix) have not been independently
  verified to use the same as-HCO3 convention now enforced project-wide
  -- worth a spot-check before trusting FIELD-sourced Alkalinity numbers
  as tightly as the newly-fixed NDEP ones; `run_phreeqc_pipeline()`'s
  final "Result rows stored" summary count is approximate (not an exact
  DB count) specifically for batches that succeed via a fallback
  database rather than the first-choice one -- a minor, cosmetic
  under/over-count in the printed summary only, not in what's actually
  stored (confirmed the real per-batch "Stored N rows" messages and the
  final DB row count are both correct).
- Verified end-to-end against the real `geochem_operational.sqlite`
  (backed up first); not yet re-verified against a scratch copy before
  applying, unlike most other schema-migration sessions -- justified
  here since the changes are ingest-logic/mapping-table fixes rather
  than schema DDL, and the backup provides the same safety net.

## Session 16 updates (2026-09-06, continued): HCO3/CO3 duplicate cleanup, FIELD alkalinity ingestion bug, temperature-sweep geothermometry

Follow-up to Session 15's NDEP alkalinity fix: cleaned up the flagged
duplicate HCO3/CO3 rows, spot-checked FIELD's Alkalinity convention (per
Session 15's own flagged caveat), and ran the multicomponent
temperature-sweep geothermometer -- which surfaced a second, independent
instance of the same class of bug, this time in the FIELD lab-ingest path.

- **HCO3/CO3 duplicate cleanup (both NDEP pathways)**: confirmed the same
  duplicate-convention pattern also exists in `promote_staged_ndep.R`'s
  `sgs_analyte_map` (a plain named-vector map, no conversion factor, and
  -- separately -- **no dedup-before-insert at all**, unlike every other
  ingest script's `anti_join` pattern; this is what let source_id=7
  samples 827-831 accumulate 2 Lab_Analyses rows per analyte). Fixed
  both pathways the same way: `ndep_analyte_map.R`'s "HCO3 as CaCO3"/"CO3
  as CaCO3" rows now map to distinct, explicitly-excluded codes
  (`HCO3_as_CaCO3_dup`/`CO3_as_CaCO3_dup`, role='excluded') instead of
  colliding with the true-mass `HCO3`/`CO3` codes; `sgs_analyte_map`
  converted from a named vector to a tribble with the same
  `conversion_factor` mechanism, with "Alkalinity, Total (As CaCO3)" now
  mapping to `Alkalinity` (factor 1.2189, matching the main NDEP fix) and
  "Alkalinity, Bicarbonate (As CaCO3)" remapped to the same
  `HCO3_as_CaCO3_dup` exclusion code (it's a different SGS parameter than
  "Total," not a duplicate of it, but not needed now that "Total" is the
  authoritative source); added the missing `distinct()` +
  `anti_join(existing_lab_rows)` dedup to `promote_staged_ndep.R`'s
  Lab_Analyses insert. **Retroactive DB cleanup**: backed up first
  (`database/archive/geochem_operational_pre_hco3_cleanup_<ts>.sqlite`),
  deleted 1,411 old HCO3/CO3 rows for both source_ids, reset
  `Staging_NDEP_WQ.promoted_at` to NULL for all 190 previously-promoted
  rows, re-ran both `ingest_ndep.R` and `promote_staged_ndep(con)` --
  zero remaining per-sample duplicates confirmed on both source_ids
  afterward. **Bug found while verifying**: the newly-fixed PRR
  Alkalinity rows kept the raw `units` string `"mg/L CaCO3"` even after
  the value itself was correctly converted to HCO3-mass-equivalent --
  `build_phreeqc_solutions()`'s unit-normalization `case_when` doesn't
  recognize that string and would have silently excluded these 10 rows
  (falls to its `TRUE ~ NA_real_` branch). Fixed by setting
  `units = "mg/L"` whenever a non-1 `conversion_factor` was applied, and
  retroactively corrected the 5 already-affected rows directly.
- **FIELD Alkalinity was never being ingested at all -- a real parsing
  bug, not a field-sampling gap as Sessions 14-15 assumed.** Spot-
  checking FIELD's raw lab report (`data/raw/lab/RE26169388.csv`) per
  Session 15's own flagged caveat found the "Alkalinity Total" column
  explicitly labeled `mg/L CaCO3eq` in its units row -- the same
  CaCO3-vs-HCO3 mislabeling risk as NDEP. But tracing why literally zero
  FIELD Alkalinity rows existed in `Lab_Analyses` (not just low
  coverage) found something more fundamental: `ingest_lab.R`'s
  `normalize_lab_wide()` runs raw CSV headers through `make.names()`
  for R-safe column names (turning `"Alkalinity Total"` into
  `"Alkalinity.Total"`, space -> dot) and then used that *mangled* name
  as the join key against `lab_analyte_map$raw_name` (`"Alkalinity
  Total"`, with a space) -- guaranteed to never match, silently dropped
  by the subsequent `filter(!is.na(analyte))`. Any multi-word raw_name
  has this problem, not just Alkalinity -- confirmed "NO3 (as N)" was
  equally affected. **Fixed**: `normalize_lab_wide()` now preserves the
  original (pre-`make.names()`) header text as a separate lookup and
  restores it as the `analyte` value before returning, so the
  `lab_analyte_map` join downstream sees real raw text again. Added the
  same `conversion_factor` mechanism to `lab_analyte_map.R` (Alkalinity
  = 1.2189, everything else = 1) and wired it into `ingest_lab.R`'s
  chemistry-processing `mutate()`. Re-ran `ingest_lab.R` against the
  real (already-backed-up) database: **all 8 real thermal FIELD
  samples now have real Alkalinity** (112-339 mg/L, plausible) and NO3
  is now populated too, both previously silently empty for every FIELD
  sample ever ingested.
- **Real downstream effect, immediately visible**: rebuilding
  `PHREEQC_Solutions` and re-running `run_phreeqc_pipeline(con)` after
  this fix, `Calcite`/`Aragonite`/`Dolomite` saturation indices -- which
  Session 14 found undefined for literally all 8 real thermal samples
  and attributed to a genuine data gap -- now compute real, geologically
  meaningful values for 7 of the 8 (calcite mildly-to-moderately
  supersaturated, SI 0.3-1.8; dolomite more strongly so, SI 1.5-4.5,
  consistent with known carbonate-scaling behavior in these waters).
  Charge balance for these 7 samples is now excellent (all within
  ±3.1%, most under 1%). **One sample (815, SBW_0002) now fails to
  converge with any database** ("Model failed to converge for initial
  solution 1") -- a genuine PHREEQC numerical limitation given its real
  (newly-complete) chemistry, correctly caught and logged to
  `PHREEQC_Run_Failures` rather than silently dropped or crashing the
  batch; not chased further this session.
- **Temperature-sweep multicomponent geothermometry run and
  cross-checked** (`run_phreeqc_temp_sweep()`, 25-300C by 25C steps,
  LLNL database) against the 7 successfully-converging real thermal
  samples, and compared to the activity-based Na/K geothermometer from
  Session 15. The two methods diverge in a geologically informative,
  not contradictory, way: quartz/chalcedony equilibration temperatures
  come out *below* measured discharge temperature for every sample
  (e.g. quartz 52-127C vs. measured 59-162C), while Na/K comes out
  *above* it (154-256C) -- consistent with a deep, Na/K-equilibrated
  reservoir fluid whose silica signature has been partly reset toward a
  cooler, more dilute end-member en route to discharge (silica
  re-equilibrates/dilutes faster than the Na/K ratio). This is exactly
  the kind of independent evidence a real two-end-member mixing
  analysis (still pending real overlapping Cl end-members, see Session
  14) would want to formally test, not a discrepancy to resolve away.
- **Committed and pushed to `origin/main`** this session (see git log
  for the exact commit) -- first git commit covering the full PHREEQC
  integration arc (Sessions 14-16).
- **Not done / next steps**: `IW-2`/`IW-3`-style deferred items from
  earlier sessions remain untouched; mixing/inverse modeling on real
  Cl end-members still blocked on chemistry that overlaps the
  conductivity logger deployment (unchanged from Session 14); the
  `docs/data/qc_summary.csv` / `export_website_data_files()` gap
  (flagged since Session 12) remains unaddressed; DEMO database still
  not rebuilt with any of the PHREEQC-era schema/ingest changes;
  `Alkalinity, Hydroxide (As CaCO3)` (NDEP PRR, 14 rows) remains
  deliberately unmapped/kept-as-is (hydroxide alkalinity is negligible
  at these near-neutral pHs) -- a documented, low-priority gap, not
  forgotten.

## Session 17 updates (2026-09-06, continued): SBW_0002 convergence failure diagnosed and fixed

Investigated the single remaining `PHREEQC_Run_Failures` row from Session
16 (sample 815, SBW_0002) per user request.

- **Root cause confirmed, not a database quirk**: read the raw PHREEQC
  `.pqo` error text directly -- `"Alkalinity has not converged... Is
  non-carbonate alkalinity greater than total alkalinity?"`. Sample 815's
  pH (9.0) sits close to boric acid's pKa (~9.24), so a large fraction of
  its Boron (37.1 mg/L -- not even unusually high in absolute terms)
  ionizes to alkalinity-contributing borate, pushing PHREEQC's internally
  computed total alkalinity ~26% above the specified value. Confirmed
  this is a genuine chemistry issue, not a solver/database quirk, by
  testing all 5 registered databases (LLNL, SIT, Pitzer, phreeqc.dat,
  WATEQ4F) with the sample's full chemistry -- all 5 failed identically;
  dropping Boron alone (all else unchanged) converged cleanly on every one.
- **Real bug found in the existing boron-exclusion guard**:
  `format_solution_block()` already had a guard for exactly this failure
  mode (ported from IGNIS), but it used a crude `B (mg/L) > 0.5 *
  Alkalinity (mg/L)` ratio -- for sample 815 that's 37.1 vs 160.9, nowhere
  close to triggering, which is exactly why it slipped through in Session
  16. Replaced with a physically-grounded check: estimate borate's
  charge-equivalent contribution at the sample's actual pH via
  Henderson-Hasselbalch (pKa=9.24, a 25C screening approximation --
  PHREEQC itself computes the real speciation at the sample's true T/mu),
  and exclude boron when that estimated contribution exceeds 15% of the
  specified total Alkalinity. Verified against all 81 complete real
  samples carrying both B and Alkalinity: only sample 815 crosses the new
  threshold (23.8%); the next-highest sample sits at 7.0%, comfortably
  clear -- confirms the new guard is a real improvement, not just a
  differently-wrong threshold, and doesn't regress any other sample.
- **Applied and verified against the real `geochem_operational.sqlite`**
  (no separate backup needed -- purely a code fix, re-running
  `run_phreeqc_pipeline(con, sample_ids = 815)` after the fix converged
  cleanly and stored 26 real result rows, including previously-missing
  carbonate SI: Calcite 0.85, Aragonite 0.71, Dolomite 1.61, consistent
  with the mild-to-moderate supersaturation pattern already seen in the
  other 7 real thermal samples). `PHREEQC_Run_Failures` is now empty
  database-wide (0 rows, down from 1).
- **Not investigated / out of scope**: whether the lab-titrated "Total
  Alkalinity" value itself already implicitly includes some borate
  contribution from the sample's native pH at the time of titration
  (which would make separately specifying total B and total Alkalinity
  together a mild double-count in principle for boron-rich samples in
  general, not just the one that happened to fail) -- the exclusion
  approach sidesteps this without resolving it; worth keeping in mind if
  boron-Cl or boron-based tracer ratios ever become analytically
  important for this project's mixing-model work.

## Session 18 updates (2026-09-06, continued): PHREEQC reference notebook, two bugs found while rendering it

- **New notebook**: `notebooks/06_phreeqc_geochemical_modeling.qmd` --
  the living reference for the whole PHREEQC workstream, mirroring
  `01_conductivity_temporal_structure.qmd`'s role for the Cl-sampling-
  frequency work. Covers scientific motivation, architecture, the
  8->233 eligible-sample story, charge-balance/alkalinity bug fixes,
  real speciation/SI, the Na/K-vs-silica geothermometer divergence, and
  the still-synthetic-only mixing/inverse/gas-phase modes. Verified with
  a real `quarto render` against the operational database, not just
  written and assumed to work.
- **Bug found while rendering**: `build_phreeqc_solutions()` (and other
  `scripts/phreeqc/*.R` functions) `source()` other project files using
  paths relative to the project root. Quarto's project-level
  `execute-dir` default runs `.qmd` files with their own directory
  (`notebooks/`) as the working directory, so those internal `source()`
  calls broke. A plain `setwd()` in the setup chunk wasn't enough either
  -- knitr's `in_dir()` restores the working directory in between every
  chunk, silently reverting it. Fixed with
  `knitr::opts_knit$set(root.dir = ...)`, which is knitr's actual
  supported mechanism for this, matching `run_pipeline.R`'s own
  root-relative-paths convention.
- **Real bug found and fixed in `12_run_phreeqc_gas_phase.R`**: its
  `SELECTED_OUTPUT` block used `"-gas true"`, which is not a real
  PHREEQC keyword -- PHREEQC prefix-matched it against `-gases` (which
  takes gas component *names*, not a boolean) and warned `"Did not find
  phase, true"`, silently punching zero real gas-component columns.
  This had gone unnoticed through all of Session 14's building and
  testing because the aggregate `-pressure`/`"total mol"` columns
  `parse_phreeqc_gas_output()` already fell back to happened to be
  *exactly* correct for the single-gas-component demo case -- only
  showed up as a stray warning when rendering the new notebook surfaced
  the raw PHREEQC log text. Fixed to the real `"-gases <names>"`
  keyword, and extended the parser to use the resulting real
  per-component `g_<name>` columns to compute a genuine partial
  pressure per gas (`moles_i / total_moles * total_pressure`) -- now
  correct for a real multi-gas mixture, not just the single-component
  case the aggregate fallback happened to get right by coincidence.
- Committed and pushed (`cadbd9d`).

## Session 19 updates (2026-09-06, continued): gas geothermometry/mixing, PHREEQC pipeline UX overhaul, well-log OCR progress bar, Mariner & Janik location matching

- **New gas modules** (`scripts/phreeqc/13_gas_geothermometry.R`,
  `14_gas_mixing.R`), same "hold off on Fischer schema, build the
  capability now" direction as the prior turn: D'Amore & Panichi (1980)
  multicomponent CO2-H2-H2S-CH4 gas geothermometer, cross-validated to
  within 0.3C against real published Mariner & Janik (1995) Table 2
  values for well 23-5 across all four sampling dates -- this caught a
  real formula-transcription risk (several secondary sources give the
  alpha term's H2 coefficient as 1; only coefficient 6, per Powell 2000,
  reproduces the real published temperatures). Forward/inverse
  two-end-member gas mixing (conservative N2/Ar ratio, mirroring
  Mariner & Janik's own Fig. 9 diagram) also built; its self-test caught
  a genuine math bug (a ratio of two linearly-mixing quantities is
  hyperbolic, not linear, in the mixing fraction -- reusing the water-Cl
  model's linear inversion formula directly on a ratio recovered 0.10
  instead of the true 0.85) before it could reach real use. Neither
  module creates a database table or is wired into `run_pipeline.R`.
- **Fixed a latent PHREEQC ambiguity bug**: `lab_analyte_map.R`'s SO4
  row had `phreeqc_name = "S"` (bare, unqualified) -- fine alone, but
  ambiguous the instant a second sulfur species (e.g. dissolved
  sulfide, `"S(-2)"`) is also specified in the same SOLUTION block;
  confirmed via a real PHREEQC error ("Analytical data entered twice
  for HS-") while building the multi-gas GAS_PHASE test. Fixed to
  explicit `"S(6)"` -- confirmed behaviorally identical for every
  existing SO4-bearing sample (no sulfide analyte exists in this
  project yet).
- **`run_pipeline.R` console-UX overhaul** (user-requested: "run timers
  and better subsection text... clear error messaging and warnings"):
  - New `section_banner()` helper replaces the repeated 3-line
    `message("\n===...")`/`message(" TITLE")`/`message("===...")` blocks
    throughout the file (13 call sites).
  - `PIPELINE_START_TIME`/`.STAGE_LOG`/`.log_stage()` accumulate every
    stage's name, elapsed seconds, and status (OK/FAILED/SKIPPED); a new
    **PIPELINE SUMMARY** section at the end prints the full table plus
    total runtime and a recap of any failed stages.
  - `run_step()` (ingest) and `run_analysis_step()` (derived analysis)
    both now use `withCallingHandlers()` to catch warnings (printed as
    `[WARNING] <name>: ...`, muffled from the default R warning
    printer) and `tryCatch()` to catch errors (printed as `[ERROR]
    <name> failed: ...`) -- **and the pipeline now continues** to the
    next step instead of hard-stopping on a single ingest/analysis
    failure (a deliberate behavior change, consistent with how
    per-file loops elsewhere in this project already tolerate
    individual failures; failures are never silent, just non-fatal).
  - **Real pre-existing bug found and fixed while doing this**: the
    `run_step(RUN_INGEST$well_logs, "WELL LOG PDFs", {...})` call was
    left nested *inside* `run_step(RUN_INGEST$well_network, ...)`'s
    block (a missing closing brace) -- well-log ingestion only ever ran
    when `RUN_INGEST$well_network` was `TRUE`, regardless of its own
    flag. Now properly independent.
- **PHREEQC stage made user-friendly** (user-requested: "make sure all
  phreeqc options are user friendly and ran from run_pipeline and auto
  if data becomes available redoes all and checks or just does certain
  updates by user toggle"):
  - New `PHREEQC_Pipeline_State` table (one row) + `should_rerun_phreeqc()`
    / `record_phreeqc_run_state()` (`scripts/phreeqc/run_phreeqc_analysis.R`):
    compares the current PHREEQC-eligible sample count/max sample_id
    against what was recorded last run; `run_pipeline.R`'s PHREEQC
    section only re-speciates when something actually changed (or
    `RUN_ANALYSIS$phreeqc_force_rerun = TRUE`), printing exactly why it
    ran or skipped. **Real bug found while wiring this up**:
    `get_phreeqc_eligible(con)` returns `list(eligible=, rejected=)`,
    not a bare data frame -- `should_rerun_phreeqc()`'s first draft
    treated it as one directly and crashed with "argument is of length
    zero"; fixed to `$eligible`.
  - `RUN_ANALYSIS$phreeqc_mixing`/`_inverse`/`_gas_phase` (each default
    `FALSE`) toggle three new CSV-config-driven runners
    (`run_phreeqc_mixing_from_config()`/`_inverse_from_config()`/
    `_gas_phase_from_config()`) that read
    `data/raw/phreeqc/{mixing,inverse,gas_phase}_config.csv`
    (auto-created, header-only, on first use) and run every row with
    `enabled=TRUE` -- a user adds/toggles a row in a plain CSV instead
    of editing R code to run a real mixing/inverse/gas-phase model.
    Still never guesses end-member `sample_id`s (a human fills them
    into the CSV), consistent with this project's standing rule.
- **Progress bar for well-log OCR** (user-requested, "could use a
  loading bar"): `ingest_well_logs.R`'s per-PDF loop now uses a base-R
  `utils::txtProgressBar` plus a per-file elapsed-time message --
  previously silent for the 10-60+ seconds/file OCR pass, which looked
  hung on a batch of a dozen scans.
- **Verified end-to-end**, twice, against a fresh DEMO rebuild: once
  exercising the real WELL LOG PDFs OCR + progress-bar path (12
  documents, 749.2 sec, all warnings/timing displayed correctly), and
  once (with `well_logs = FALSE` to skip the slow OCR re-run) exercising
  the new PHREEQC auto-rerun logic end-to-end (ran once, correctly
  recorded state) plus all three CSV-config toggles (created templates,
  ran cleanly with 0 enabled rows) and the full PIPELINE SUMMARY table
  -- zero stage failures in either run.
- **Notebook updated**: `notebooks/06_phreeqc_geochemical_modeling.qmd`
  gained a new "Gas geothermometry and gas mixing" section (the D'Amore-
  Panichi validation, the ratio-mixing bug story, both self-tests run
  live) and a changelog row; re-rendered successfully.
- **Website updated**: `website/results.Rmd`'s PHREEQC callout box
  updated with current real numbers (233 eligible samples -- was stale
  at "a handful"/8) and a mention of the new gas-geothermometry
  direction; `website/references.Rmd`'s Mariner & Janik citation
  upgraded from "under review, not independently verified" to a full,
  verified citation (read directly from the PDF this session and last).
  Rebuilt via `build_website()` (the literature-folder-backup-protected
  wrapper, not a bare `render_site()` call) -- `docs/literature/`
  confirmed intact afterward (33 files, including `Dhakal.pdf`, despite
  one harmless "Permission denied" warning on the restore-copy step for
  a file that was already present and unchanged). `docs/data/qc_summary.csv`
  (a known, previously-flagged gap -- not part of
  `export_website_data_files()`) got swept by `render_site()`'s cleanup
  as expected; restored via `git checkout` rather than expanding scope
  to fix the underlying gap this session.
- **Mariner & Janik (1995) site-name matching against this project's
  own database** (user asked "do we know the locations... for me to
  find"), read from the paper's Table 1/Table 2 site list, checked
  against `Wells`/`Locations`/`Well_Aliases`:
  - **Already resolved with real coordinates**: `23-5` (well_id 96,
    NBMG-sourced), `21-5` (as `21-5R`, well_id 94, no coordinate yet),
    `13-5` (as `13-5R`, well_id 93, no coordinate yet), `PW-1`/`PW-2`/
    `PW-3` (well_ids 79-81, no coordinates yet), `IW-3` (well_id 103, no
    coordinate), `IW-5` (a confirmed alias to canonical `46-28`, which
    does have a coordinate), `Curti` (both "Curti Domestic Well" and
    "Curti Barn Well," Klein-sourced, 39.39436/-119.7396), `Herz`
    ("Herz Domestic Well," Klein-sourced, 39.40547/-119.7533),
    `Galena Ck.` (a *different* thing than expected -- the only DB match
    is "GALENA CREEK PARK," an NDWR-sourced well ~4 km SW of the field
    near the Mt. Rose Highway area, almost certainly not Mariner &
    Janik's creek-sampling point; flagged as a coincidental name match,
    not a real identity), `Thomas Ck.` (three real Thomas/Whites Creek
    monitoring locations exist, `SB10`/`STBT03Thomas-4`/`STBT03Whites-2`
    -- plausible candidates, not confirmed which if any is Mariner &
    Janik's specific site), `Zolezzi` (both "North Fork Whites Creek @
    West Zolezzi Lane" and "Zolezzi Well," neither confirmed as their
    specific "Zolezzi Spr"), `DeMonte` (as "DiMonte Well," Klein-sourced,
    confirming Klein's spelling variant per earlier sessions),
    `STMGID` (four real NDWR-sourced MW1/MW3/MW10/11-MWA wells exist,
    but none confirmed as specifically Mariner & Janik's "Stmgid4").
  - **Not found in this database at all**: `83A-6`/`83-A6`, `COX-1`/
    `COX1-1`, `GS-5`, `PW2-1` through `PW2-5`, `PW3-1` through `PW3-4`
    (none of the real SB2/SB3-side wells confirmed in Session 7 have
    "PW2-x"/"PW3-x" as their literal `Wells.well_name` -- worth
    double-checking exact naming), `Stuart`, `Brown's School`,
    `Steinhardt`, `Peigh`, `Tick Spr.`, `Jumbo Gr. S.`, `Tahoe Mdw.`,
    `Third Ck. Spr.` -- consistent with several of these already being
    flagged unresolved in earlier sessions (Steinhardt, Peigh, Brown
    School, STMGID #3/#4 all appear in the Session 4 "still unresolved"
    list).
  - Not written anywhere (read-only lookup only, per the user's
    question) -- no new `Locations`/`Wells` rows created or coordinates
    guessed from this matching pass.
- **Committed and pushed** to `origin/main` (commit `7f0c318`,
  `tylerirvin543/Steamboat_Creek_Geochemistry_Database`) -- covers all
  of the above except the Mariner & Janik lookup itself (read-only,
  nothing to commit).

## Session 20 updates (2026-09-06, continued): PW2-x/PW3-x well aliases + provisional wells, pipeline_report refactor, annotated bibliography

Three independent, user-approved (via Plan mode) pieces of follow-up
work from the prior turn's Mariner & Janik location lookup and
console-UX session.

- **PW2-x/PW3-x naming mismatch resolved via aliases, not renames.**
  Confirmed directly against `geochem_operational.sqlite`: this
  project's `Wells.well_name` values for these wells (`PW 2-1`,
  `PW 2-3`, `PW 2-5`, `PW 3-1..4`) use a space, sourced from the
  ArcGIS satellite-overlay digitization (Session 7); Mariner & Janik
  (1995) print them with no space (`PW2-1`, etc.) -- confirmed by
  reading the paper's own text, which is why last turn's plain-text
  name search reported them as "not found." Added 7 new
  `Well_Aliases` rows (`data/raw/wells/well_aliases.csv`,
  `alias_type='other'`) mapping the no-space spelling to each
  canonical well, applied via `register_well_network(con)` against the
  real database (verified: 7 aliases registered, matching well_ids).
  **`PW2-2` and `PW2-4` specifically are a genuine gap, not a naming
  artifact** -- Mariner & Janik's Table 1/Fig. 3 list them as part of
  the same historical PW2-x/PW3-x group, but neither appears in
  Dhakal et al. (2025)'s current flow diagram, and neither has ever
  been digitized/coordinate-matched. **Per explicit user instruction**,
  added them as provisional `Wells` rows (well_role/port_name
  intentionally blank -> defaults to `'unknown'`, no coordinate) via
  `data/raw/wells/dhakal_well_network.csv`, so they're tracked as
  known-but-unlocated rather than only living in prose -- mirrors the
  `register_provisional_well_logs()` philosophy from the well-log
  workstream. Applied directly to the real database (well_ids 119,
  120); no scratch-copy verification needed since it's a pure additive
  insert via an idempotent, already-tested registration path.
- **`scripts/pipeline_report.Rmd` refactored from a mixed QC/science
  grab-bag into a lean "Pipeline QC & Status Report."** Removed: the
  "Well & Facility Flow Network Summary" section (now redundant with
  `notebooks/05_data_inventory_and_well_network.qmd`, which covers the
  same ground in more depth) and the ad hoc exploratory chunks
  (gradient histogram, `table(grad$gradient_class)`, raw
  `summary(grad$distance_m)`/temperature summaries, and an `sf`-based
  GeoPackage plot that re-read a multi-hundred-MB layer on every single
  pipeline run for no decision-relevant payoff). Added: a genuine
  `QC_Issues` summary (counts by `issue_type` x `severity`, top-10
  ERROR-severity issue types) and a `PHREEQC_Run_Failures` listing --
  neither had been surfaced in this report at all despite both tables
  existing and being populated every run. Retitled from "Pipeline Run
  Report" to "Pipeline QC & Status Report" to match its actual, now
  more honest scope; added an explicit pointer to the notebooks/website
  for anyone looking for interpretation rather than status. Verified by
  rendering directly against the real `geochem_operational.sqlite`
  (temporary output file, deleted after confirming it rendered cleanly).
- **New annotated bibliography**: `docs/literature/annotated_bibliography.qmd`
  (renders to both `.docx` -- the primary format, easiest to paste into
  an actual thesis document -- and `.html`; both outputs and the
  source `.qmd` are gitignored along with the rest of `docs/literature/`,
  consistent with this project's "cite, don't rehost" policy and this
  being a personal working thesis tool rather than a pipeline
  artifact). Covers all 30 unique documents then in `docs/literature/`
  (33 files minus 3 confirmed byte-identical duplicates, verified via
  `md5sum` before writing a single entry twice: `Geochem Data and
  concept model Mariner & Janik 1995.pdf` = `Marine_Janik_1995_...pdf`;
  `Sorey and Speilman 2008.pdf` = `Sorey_Spielman_2008_...pdf`;
  `Klein_Johnson_Spielman_2007_...pdf` = `Klein_etal2007_SteamboatMonitoring.pdf`),
  organized thematically (Steamboat aqueous/gas geochemistry;
  reservoir engineering/well history/monitoring; structural
  geology/geophysics; the 2025-2026 eruption literature; regional/
  Yellowstone comparative-methodology analogs; historical USGS
  characterization; non-NDEP-authored Steamboat Creek water quality),
  with every annotation written from each document's own extracted
  title/abstract/intro text (`pdftotext -layout`), not a secondary
  summary. **Excluded, per the explicit "not including NDEP documents"**
  instruction: `ACR_2024.pdf` (a statewide NDEP drinking-water
  compliance report, not Steamboat-specific) and the three 2020 NDEP
  Source Water Protection Program HUC-12 watershed profiles (Hidden
  Valley, Steamboat Valley, Thomas Creek) -- all four are NDEP-authored
  documents, a different (narrower) criterion than this project's usual
  ingestion-pipeline sense of "NDEP documents" (the PRR/UIC compliance
  PDFs under `data/raw/ndep/PRR/`, which were never in
  `docs/literature/` to begin with). This exclusion boundary is
  explicitly flagged in the bibliography's own text in case a future
  pass wants it narrowed. Also found and flagged two real, non-obvious
  facts while reading: `Lindsey_etal_2016_GeyserE_renewedA_steamboat.pdf`
  is filed under a "2016" filename but the paper itself (SGP-TR-230,
  51st Stanford GRC Workshop) is dated February 2026 and is entirely
  about the June 2025 eruption -- the filename year is wrong, not the
  content; and `Newman_2026_SC_paper.pdf`'s "Steamboat Springs" is in
  **Colorado**, a completely different geothermal system from Steamboat
  Hills, Nevada -- included as a methodological analog only, with an
  explicit warning against citing it as if it describes the Nevada
  system (this had been cited in `references.Rmd` previously without
  this distinction being surfaced).
- **Also found and deleted**: `docs/literature/nul`, a stray ~638 MB
  file (Windows's reserved `nul` device name, almost certainly created
  by an earlier `> nul` shell redirect run outside `cmd.exe`) -- not a
  literature document, removed as part of this pass.
- **Committed and pushed** to `origin/main`: the well-alias/provisional-well
  CSV changes and the `pipeline_report.Rmd` refactor. The annotated
  bibliography and its rendered outputs are intentionally NOT
  committed (gitignored, per the reasoning above).

## Session 21 updates (2026-09-12): NDOM permitted-well data ingested (cross-validation + gap-filling)

User received a new source from Keith Hayes (NDOM, Nevada Division of
Minerals) -- `data/raw/ndom/Ormat Steamboat Wells.xlsx`, 49 rows: the
official state permit record for every Ormat Steamboat well (Permit #,
API #, BLM Lease Number, Well Type [Obs/Ind-Prod/Ind-Inj/TG],
Status [In Use/Shut-In], Spud/Completion dates, Total Depth, UTM
Easting/Northing, Elevation). Planned in Plan mode with the user (4
explicit decisions confirmed via AskUser before implementing) and then
built and applied end-to-end.

- **UTM assumed NAD83 UTM Zone 11N (EPSG:26911)**, matching the
  convention already used elsewhere in this project (the well-log OCR
  parser's `.extract_utm_latlon()`) -- confirmed correct by spot-
  checking 9 already-coordinated wells before writing any code: most
  converted coordinates landed within ~15-50 m of the existing NBMG/
  ArcGIS-sourced value, consistent with existing `coordinate_uncertainty_m`.
- **New schema file**: `database/schema/09_ndom_wells_schema.R` (sourced
  after 01-08, both at initial connection and in the DEMO reset block).
  Adds 8 new `Wells` columns (`ndom_permit`, `api_number`,
  `blm_lease_number`, `well_status`, `spud_date`, `completion_date`,
  `field_name`, `land_type`) and a new `NDOM_Well_Records` staging table
  (mirrors `Well_Log_Documents`/`Staging_NDEP_WQ` -- full raw row
  preserved verbatim, unique on `Permit`, records `match_method` and
  `matched_well_id`).
- **Real, pre-existing unit bug found and fixed while scoping this**:
  `Wells.elevation_m` had been storing raw FEET since first populated by
  `ingest_ndwr.R` (e.g. "Sky Tavern Ski Resort" = 7619, "Galena Creek
  Park" = 6017 -- Steamboat's true elevation is ~1450-1750 m, nowhere
  close to those numbers even accounting for surrounding peaks). All 73
  then-populated rows were confirmed 100% feet (not a per-row mix)
  before writing a fix. **User explicitly chose the broad fix**: a
  one-time migration in `09_ndom_wells_schema.R` converts every
  `Wells.elevation_m > 3000` to true meters (`* 0.3048`) -- naturally
  idempotent, since post-conversion Steamboat elevations top out
  ~2325 m, safely under the 3000 threshold. NDOM's own elevations (also
  feet in the source file) are converted correctly on ingest using the
  same factor, so the column is now consistent both retroactively and
  going forward.
- **New ingest script**: `scripts/ingest/ingest_ndom_wells.R` /
  `ingest_ndom_wells(con)`. Per row: converts UTM, resolves the well
  name to an existing `Wells` row via (a) exact `well_name` match, (b) 7
  hardcoded confirmed spelling-variant matches (`21-5`->`21-5R`,
  `13-5`->`13-5R`, `21B-5`->`21B-5R`, `83B-6`->`83B-6R`,
  `83C(82)-6`->`83C-6ST1`, `23-33`->`23-33RD`, `46-28-2`->`46-28` --
  each independently corroborated by spelling-variant notes already in
  this file from earlier sessions), or (c) an existing `Well_Aliases`
  row; else creates a new provisional `Wells` row (no coordinate
  conflict possible for a brand-new row). Fills `well_role` (from Well
  Type: Obs/TG -> `monitor`, Ind-Prod -> `production`, Ind-Inj ->
  `injection`), coordinates, elevation, total_depth, and the 8 new
  identifier columns **only when the existing Wells field is currently
  NULL** -- never overwrites. **User explicitly chose never-overwrite +
  flag-for-review** for coordinate conflicts: existing coordinates >100 m
  from NDOM's are left untouched and logged to
  `data/derived/ndom_coordinate_discrepancies.csv` instead. Idempotent
  on `NDOM_Well_Records.permit` (verified: a second run finds 0 new rows
  and changes nothing).
- **Two names deliberately NOT auto-merged**, per user-approved plan:
  `"14-33"` (NDOM permit 0708) vs. existing `"14A-33"` (permit 0669) --
  two distinct real NDOM permits, kept as separate wells with a `notes`
  flag for manual review, not guessed as the same well. `"1"`/`"3"`
  (both Well Type `TG`, thermal-gradient holes, permits 0273/0275,
  **and the only 2 of the 49 rows with no UTM coordinate at all** in
  the source file, along with `"11-12-TG"`) -- renamed to `"TG-1"`/
  `"TG-3"` before matching per user's explicit choice, since a literal
  well_name of `"1"`/`"3"` is too generic/collision-prone.
- **Applied to the real `geochem_operational.sqlite`** (backed up first
  to `database/archive/geochem_operational_pre_ndom_<timestamp>.sqlite`,
  verified identically against a scratch copy first): 18 exact-name
  matches, 7 alias/variant matches, 24 new provisional wells created
  (Wells count 119 -> 143); 30 coordinates filled, 38 elevations filled,
  47 total_depths filled, 25 well_roles filled, 49 identifier sets
  filled. **6 real coordinate discrepancies found and logged** (existing
  values left untouched, per the user's chosen never-overwrite policy) --
  `24-5` (555 m), `34-32` (573 m), `14A-33` (476 m), `21-32` (211 m),
  `64A-32` (228 m), `41-5` (166 m) -- all in
  `data/derived/ndom_coordinate_discrepancies.csv`, worth a manual look
  since NDOM is the official permit-of-record coordinate and these gaps
  are large relative to this project's usual ~50-75 m NBMG/ArcGIS
  uncertainty.
- **Wired into `run_pipeline.R`**: new `RUN_INGEST$ndom_wells` flag
  (`TRUE` in profiles 1/2, `FALSE` in 3), sourcing
  `09_ndom_wells_schema.R` alongside 01-08 and calling
  `ingest_ndom_wells(con)` as its own `run_step()`-wrapped stage, placed
  right after the existing "WELL LOG PDFs" stage. Edited via the
  established `readLines()`/binary-write-with-explicit-"\r\n"-join
  round-trip (the `edit` tool's exact-string matching failed
  intermittently against this CRLF file, same recurring caveat as many
  prior sessions) -- verified with `parse()` afterward and a `grep -U
  $'\r\r'` check to confirm no doubled-CR corruption was introduced.
- **Not done this session**: DEMO database not rebuilt with this stage;
  the 6 flagged coordinate discrepancies are logged but not resolved
  (deliberately left for the user); `data/raw/ndom/` is untracked/
  gitignored like other raw sources (xlsx not `git add -f`'d); this
  session's file changes are not yet committed/pushed to git.

## Session 22 updates (2026-09-12, continued): Dhakal Table 1 cross-check, DEMO idempotency test, second elevation-unit bug (Locations)

Follow-up to Session 21. User attached an image (a zoomed map with fault
lines + surface-manifestation/mineralization legend matching Dhakal et
al. 2025 Figure 1's own caption almost exactly -- i.e. this appears to
literally be that figure) asking whether Dhakal confirms 34-32 = Middle
Steamboat, 14-33/14A-33 as distinct-but-adjacent wells, and 24-5's
position; also asked for an idempotent DEMO-mode test of the new NDOM
stage.

- **Read `docs/literature/Dhakal.pdf` directly (Table 1, "Steamboat
  Production Well classification")** -- confirms all three user
  observations from an independent, authoritative source (not just the
  image): Upper Steamboat = `13-5RD, 21-5, 21-5R, 21B-5R, 23-5, 24-5,
  41-5, 83A-6, 83B-6RD, 83C-6`; Middle Steamboat = `14-33, 14A-33, 28-32,
  34-32, 44-32, 44A-32`; Lower Steamboat = `78-29, HA-4, PW-1, PW-2,
  PW-3, PW2-1, PW2-3, PW2-5, PW3-1, PW3-2, PW3-3, PW3-4`. This
  independently corroborates the Session 20/21 decision to keep `14-33`
  and `14A-33` as separate wells (Dhakal's own table lists them
  separately too).
- **`14-33` added to `data/raw/wells/dhakal_well_network.csv`**
  (`well_role=production`, `port_name=Galena 3`, matching sibling
  `14A-33`) -- the one well from Table 1 that was a literature-confirmed
  gap in the network CSV. Noted in its own row that it's NOT in Figure
  5's 2024 flow snapshot and NDOM records it Shut-In (permit 0708,
  completed 9/15/2007, three months after 14A-33) -- grouped by Table 1's
  classification, not by an active-flow claim.
- **Deliberately NOT mapped**: `28-32` (Table 1 lists it as Middle
  Steamboat, but NDOM confirms Shut-In and it's absent from Figure 5 --
  consistent, no action needed, same pattern as `IW-2`/`IW-3`); `28A-32`
  (NDOM permit 1605, completed 8/6/2026 -- too new for Dhakal 2025 or any
  literature checked so far; no port assignment guessed).
- **Full DEMO-mode pipeline rebuild run end-to-end** (all ingest sources
  including the new `RUN_INGEST$ndom_wells` stage) for the first time --
  0 stage failures, NDOM stage completed in 3.3-3.4 sec with the same 6
  coordinate discrepancies as the operational-DB run (expected, same
  source file). Re-running `ingest_ndom_wells()` a second time against
  the same DEMO database confirmed clean idempotency (0 new rows, 0
  fields changed).
- **Second elevation-unit bug found via this idempotency test, not
  previously caught**: re-running `09_ndom_wells_schema.R`'s migration a
  second time against the DEMO database (after the full pipeline run)
  unexpectedly found 73 more `Wells.elevation_m` rows > 3000 to convert.
  Root cause: within a single fresh-DEMO pipeline run, the schema
  migration sources (and runs its one-time feet->meters fix) *before*
  `ingest_ndwr.R` runs later in the same INGEST STAGE -- so on a brand
  -new database, the migration finds 0 rows (Wells is still empty), then
  NDWR ingestion populates 73 more elevation_m rows in raw feet,
  uncorrected for the rest of that run. (This is why Session 21's fix
  looked complete against the already-populated operational DB but
  didn't fully close the loop for a from-scratch DEMO rebuild.)
  **Also discovered while chasing this**: the exact same bug independently
  affects **`Locations.elevation_m`** (72 rows, e.g. "Sky Tavern Ski
  Resort" = 7619, same NDWR source) -- missed by Session 21's fix, which
  only touched `Wells`. **Fixed at the actual root cause this time**:
  `ingest_ndwr.R` now converts `elevation * 0.3048` at insert time for
  *both* `Locations.elevation_m` and `Wells.elevation_m` (previously
  inserted the raw NDWR feet value directly into both), so this can't
  recur on any future ingest, DEMO rebuild, or new NDWR site added.
  `09_ndom_wells_schema.R`'s one-time retroactive migration extended to
  also cover `Locations.elevation_m > 3000`, so it's a real project-wide
  fix now, not just `Wells`. Verified three ways: (1) DEMO database's 72
  bad `Locations` rows fixed by re-running the migration; (2) a from-
  scratch scratch database running only `ingest_ndwr.R` fresh (both
  PV and TM basin files) confirmed new rows arrive already correct
  (elevation range 1345-2322 m for both `Locations` and `Wells`, no
  retroactive fix needed); (3) applied the same retroactive
  `Locations.elevation_m` fix to the real
  `geochem_operational.sqlite` (backed up first to
  `database/archive/geochem_operational_pre_locations_elev_fix_<timestamp>.sqlite`)
  -- 72 rows corrected, 0 remain > 3000 in either table.
- **Not done this session**: the DEMO database itself was not re-run a
  third time end-to-end to confirm the `ingest_ndwr.R` source fix holds
  up inside a full fresh pipeline run (only verified via the isolated
  scratch-db test above) -- worth doing on the next full DEMO rebuild;
  git commit/push still pending for all of Sessions 20-22's changes.

## Session 23 updates (2026-09-12, continued): NDWR file reorganization fix, NDWR spring/stream flow ingestion, docs pass

Follow-up to Sessions 21-22 (NDOM ingestion, Dhakal Table 1 confirmation).
User reorganized `data/raw/ndwr/` (moved the PV/TM `SiteData`/
`WaterLevelData` xlsx files out of the folder root and into their
respective `*_WellLogQuery_..._files/` companion folders) and supplied a
new source, `data/raw/ndwr/TM_Spring_Stream_Flowdata_2026_09_12_files/`
(2 files: `SiteData.xls.xlsx`, `SpringAndStreamFlow.xls.xlsx` -- daily
manual discharge in cfs at 4 gauged sites on Whites Creek, Truckee
Meadows basin, back to 2017).

- **Fixed `run_pipeline.R`'s hardcoded NDWR paths** (`RUN_INGEST$ndwr`
  step) to point inside the `_files` subfolders where the xlsx files now
  live -- confirmed via `find` that the `sheet001.htm` companion files
  `ingest_well_logs.R` reads were already inside those folders (the
  NDWR "Web Page, Filtered" export always puts them there), so only the
  `ingest_ndwr()` call's two direct file-path arguments needed updating,
  not that script. Verified by re-running `ingest_ndwr()` against the
  real database with the new paths (idempotent, 0 new rows since already
  ingested under the old paths).
- **New source ingested**: `scripts/ingest/ingest_ndwr_stream_flow.R` /
  `ingest_ndwr_stream_flow(con)`, new schema
  `database/schema/10_ndwr_stream_flow_schema.R`
  (`Stream_Flow_Observations`: `location_id`, `date`, `discharge_cfs`,
  `method`, `measured_by`, `remarks`, `source`, unique on
  `(location_id, date, method)`). Each of the 4 sites is registered as
  an ordinary `Locations` row (`site_type = 'creek'`) so it slots into
  the same GIS/website map machinery as every other location -- no new
  spatial concept needed, only the time series table itself is new.
  Wired into `run_pipeline.R` as `RUN_INGEST$ndwr_stream_flow` (`TRUE` in
  profiles 1/2, `FALSE` in 3), right after the `NDWR WELLS + WATER
  LEVELS` step.
- **Real bug caught and fixed while building this**: two of the four
  real sites (`087 N18 E19 35ABAC1` "Whites Creek Diversion to Mt. Rose
  WTP" and `087 N18 E19 35ABAC3` "Whites Creek Above MRWTP") share an
  **identical rounded lat/lon** in the source file -- matching/
  deduplicating Locations on `coord_key` (the pattern `ingest_ndwr.R`
  uses for wells) collapsed them into one row and broke the
  `External_Location_Map` unique constraint downstream. This is the same
  class of bug flagged in Session 1 for `ingest_field.R` (coord_key is
  not always a safe identity key). Fixed by matching/deduplicating on
  `external_station_code` (`"NDWR_SF_" + cleaned site name`) instead --
  each of the 4 sites now gets its own correct `Locations` row despite
  the coordinate collision. A second, unrelated bug (`ifelse()` returning
  the wrong type -- logical instead of character -- when its test vector
  has zero rows, hit on the very first idempotent re-run when
  `Stream_Flow_Observations` was still empty) was fixed by switching the
  dedup-key construction from `ifelse(is.na(x), "", as.character(x))` to
  `coalesce(as.character(x), "")`, which doesn't have this zero-length
  quirk.
- **Applied to the real `geochem_operational.sqlite`** (backed up first
  to `database/archive/geochem_operational_pre_streamflow_<timestamp>.sqlite`,
  verified against a scratch copy first): 4 new `Locations` rows, 4929
  new `Stream_Flow_Observations` rows (2017-12-30 through 2026-06-30
  across the 4 sites). Idempotent re-run confirmed (0 new rows).
- **Full DEMO-mode pipeline rebuild re-run** (all sources except the slow
  `well_logs` OCR stage, to save time) with both the path fix and the new
  stream-flow stage active -- 0 stage failures, ~4.2 min total.
- **Documentation pass**: `README.md` (new-data-drop-locations table row
  for both NDOM and NDWR stream flow, a note explaining the `_files`
  subfolder path convention, new "NDOM Well-Permit Cross-Validation" and
  "NDWR Spring/Stream Flow" sections, and a summary paragraph added to
  the existing "Well & Facility Flow Network" section); notebook
  `05_data_inventory_and_well_network.qmd` (new "4. NDOM Well-Permit
  Cross-Validation" and "5. NDWR Spring/Stream Flow" sections with live
  queries against the real database, re-rendered successfully; new
  changelog row); `scripts/pipeline_report.Rmd` (added `NDOM_Well_Records`
  and `Stream_Flow_Observations` to the table-row-count list, test-
  rendered successfully). All three CRLF files edited via the
  established `readLines()`/binary-write-with-explicit-`"\r\n"`-join
  round-trip (the `edit` tool's exact-string matching failed
  intermittently against them, same recurring caveat as many prior
  sessions) -- verified with a `grep -U $'\r\r'` check on each
  afterward to confirm no doubled-CR corruption was introduced.
- **Not done this session**: DEMO database's `well_logs` (OCR) stage was
  skipped in this session's rebuild to save ~12 minutes -- worth a full
  rebuild including it next time there's time; `data/raw/ndwr/` is
  untracked/gitignored like other raw sources (new xlsx files not
  `git add -f`'d); the flow-data `Accuracy` column (all-`NA` in the
  source file so far) and the small number of unit-mismatch/NA-discharge
  rows in the raw file were left as-is (stored/skipped respectively, not
  investigated further -- see `ingest_ndwr_stream_flow.R`'s warnings).

## Session 24 updates (2026-09-12, continued): large NDWR/ArcGIS well-log batch, PLSS lat/lon fallback, work-history tracking

User added ~100 new well-log PDFs (64 log numbers total, most with a
second "(2)" reformatted/streamlined scan) to `data/raw/ndwr/
Ormat_well_logs/`, sourced from NDWR's public ArcGIS well-log
database. Extended the existing well-log pipeline (built in Sessions
9-11) rather than replacing it.

- **Confirmed before writing any code**: both the original scans and
  the new "(2)" scans are image-only (checked with `pdftotext` directly
  on several examples) -- no shortcut around OCR for either variant.
  Also found 3 exact-duplicate re-downloads (` (1).pdf` suffix, same
  byte size/content as an existing file).
- **New extraction fields** (`scripts/ingest/helpers/parse_well_log_pdf.R`):
  Section/Township/Range (raw text, always attempted independent of
  lat/lon status), `work_type` (new/deepening/abandonment/
  reconstruction/repair/change_of_use, first-match-wins keyword
  search), `proposed_use` (domestic/monitor/geothermal/industrial/
  irrigation/municipal/stock/test), `hole_diameter_in`/
  `casing_diameter_in`.
- **New lat/lon fallback level 4**: `.convert_plss_to_latlon()` queries
  BLM's public PLSS CadNSDI ArcGIS REST service
  (`https://gis.blm.gov/arcgis/rest/services/Cadastral/
  BLM_Natl_PLSS_CadNSDI/MapServer`) -- Township layer (id=1) by
  state/township/range to get a `PLSSID`, then the Section layer
  (id=2) by `PLSSID`+section number for the polygon, centroid taken as
  the coordinate. Confirmed reachable and correct before relying on
  it: queried Section 2, T17N R19E and confirmed the returned polygon
  geometrically contains the independently-known real coordinate of
  the Shonnard well. `coordinate_uncertainty_m = 800` (bare section
  resolution) when used. Used on 3 of 52 newly-processed documents.
- **"(2)" alternate scans tracked on the SAME `Well_Log_Documents` row**
  (new `alt_file_path`/`alt_file_hash`/`alt_has_text_layer` columns),
  not as separate documents. Fields merge primary-then-alt, with one
  deliberate exception found via real testing: **lat/lon merges by
  confidence rank, not primary-first** -- logs `48594` and `126301`'s
  primary scan produced a low-confidence `unlabeled_scan` guess wildly
  outside Nevada/the Steamboat area, while their `(2)` alt scan had a
  properly `labeled_field` reading; a naive "primary always wins"
  merge would have kept the wrong one. Fixed by ranking lat/lon
  specifically (`labeled_field` > `utm_conversion` > `unlabeled_scan`
  > `plss_section_centroid`) and picking whichever source ranks
  better, flagging when the alt source won. Any other field
  (well_name, county, depths, etc.) still merges primary-first with a
  flag on disagreement, since there's no equivalent confidence
  ordering for those.
- **Exact-duplicate re-downloads deduplicated by content hash across
  ALL existing documents** (not just same file path), so a
  `"<log> (1).pdf"` re-download of an already-ingested file is
  recognized and skipped without re-running OCR -- confirmed working
  on a real case (`27732 (1).pdf` matched the already-ingested
  original `27732.pdf` from session 9/10, correctly skipped).
- **Real, pre-existing bug fixed**: `promote_well_log_documents()` and
  `register_provisional_well_logs()` both checked
  `WHERE well_id = ? AND method = 'driller_report'` with no
  `timestamp` in the check -- meaning only the FIRST driller's report
  ever ingested for a well had its static water level stored; any
  later report (deepening, re-permit) for the same well was silently
  dropped. Fixed to also match `timestamp`, aligning with the table's
  real `UNIQUE(well_id, timestamp, method)` constraint. Verified with
  a direct synthetic-well test: two documents with different
  completion dates for the same well now both produce their own
  `Water_Level_Observations` row.
- **New `Well_Work_Events` table** (`well_id`, `source_document_id`,
  `work_type`, `proposed_use`, `event_date`, `hole_diameter_in`,
  `casing_diameter_in`, `notes`) -- one row per promoted/registered
  document, so a well's status history (new -> deepened -> abandoned)
  is a real queryable time series instead of a single overwritten
  Wells snapshot. Populated by both `promote_well_log_documents()` and
  `register_provisional_well_logs()`. New `Wells.diameter_in` column
  (never overwritten) backfilled from the first log that reports a
  diameter, for a quick "is this a 1" piezometer or a full-scale
  production well" check without joining to the event table.
- **`Well_Lithology` populated for the first time** (schema existed
  since session 9, nothing had ever written to it) -- best-effort
  intervals from the primary scan's OCR text are staged at ingest time
  with `well_id = NULL` (schema migration: `Well_Lithology.well_id`
  was originally `NOT NULL`, rebuilt via table-recreate since SQLite
  can't drop a NOT NULL constraint via `ALTER TABLE`) and a
  `confidence=ocr_heuristic_unvalidated` note; still not blindly
  trusted, same posture as every other OCR-derived field. 5 documents
  produced staged intervals in this batch.
- **A water-level reading tied to a `work_type` of `abandonment`** is
  stored (not dropped) but gets an explicit `[FLAG: ...]` prefix in
  its `Water_Level_Observations.notes`, since it may not reflect a
  representative ambient water table.
- **New repeatable QC report**: `scripts/qc/qc_well_log_matches.R` /
  `qc_well_log_matches(con)` -- for every unmatched, coordinate-having
  `Well_Log_Documents` row, writes the nearest existing `Wells` and
  `Locations` row + distance to
  `data/derived/well_log_match_candidates.csv` (overwritten each run,
  never auto-matches). Replaces the earlier pattern (Sessions 10-11)
  of a one-off conversation-driven "nearest NBMG candidate" writeup
  per batch with a standing, regenerable artifact. Wired into
  `run_pipeline.R` right after `register_provisional_well_logs(con)`,
  inside the same `RUN_INGEST$well_logs` step.
- **`ingest_well_logs(con, source_batch = ...)`** now tags every
  document with a free-text provenance string (this batch:
  `"NDWR ArcGIS public well-log export, 2026-09-12"`), so future
  batches dropped into the same shared folder stay distinguishable.
- **Applied to the real `geochem_operational.sqlite`** (backed up
  first to `database/archive/
  geochem_operational_pre_well_log_batch2_<timestamp>.sqlite`, and
  verified twice against scratch copies first -- once catching the
  `Well_Lithology.well_id NOT NULL` bug, once catching and fixing the
  lat/lon confidence-merge bug, before the real run): 52 new documents
  processed (11 already-ingested skipped, 1 exact-duplicate-content
  skipped) in 6.4 minutes; 44 new provisional `Wells` rows (`Wells`
  187 total, up from 143); 42 `Well_Work_Events` rows; 5 staged
  `Well_Lithology` intervals; 1 new `driller_report` water-level
  reading (OCR only reliably found this phrase once in this batch --
  not chased further, same caveat as prior sessions' OCR-quality
  notes); idempotent re-run confirmed (0 processed, 64 skipped).
  `data/derived/well_log_match_candidates.csv` now has 2 rows for
  human review (one is the long-known `146403`/Gerlach bad-longitude
  case from session 10, unchanged; the other is a genuinely new
  candidate from this batch).
- **Still unresolved / not attempted this session**: no entries added
  to `data/raw/ndwr/well_log_document_map.csv` (still empty -- none of
  the new logs' extracted well names were confident enough to promote
  automatically, consistent with this project's standing rule); the 7
  documents with no coordinate at all (`146238`-`146241` --
  Gerlach-area, consistent with prior sessions; `147782`, `7587`,
  `7588` -- genuinely new, no PLSS parsed and no NDWR crossref match
  either) remain staged with `well_id = NULL`; DEMO database not
  rebuilt with this batch; this session's file changes (`database/
  schema/07_well_logs_schema.R`, `scripts/ingest/helpers/
  parse_well_log_pdf.R`, `scripts/ingest/ingest_well_logs.R`,
  `scripts/qc/qc_well_log_matches.R` [new], `scripts/run_pipeline.R`)
  not yet committed/pushed to git; the 3 exact-duplicate ` (1).pdf`
  files and the rest of the raw batch remain untracked/gitignored like
  other `data/raw/` sources.

## Session 25 updates (2026-09-12, continued): well-log doc/viz pass, P&A status, new visualization packages, full verification

Large follow-up to Session 24, covering documentation, a derived well
status field, new chemistry/geothermometer visualizations (ggdist,
ggbeeswarm, ggalluvial, ComplexHeatmap), two data fixes, and an
end-to-end verification pass (database -> website -> GeoPackage).

- **Data fixes**: log `146403`'s OCR longitude corrected from
  `-719.422608` to `-119.422608` (leading-digit misread; confirmed still
  a Gerlach-area, non-Steamboat well before and after). `qc_well_log_
  matches.R` gained a `recommendation` column (download the NDWR "(2)"
  page if missing; review as a close match if <200m; else "keep
  unresolved" -- log `80672`/"Greg Street" candidate explicitly left
  unresolved per user instruction). `ndom_coordinate_discrepancies.csv`
  gained `existing_coordinate_source`/`existing_coordinate_uncertainty_m`
  columns (all 6 current discrepancies trace to `nbmg_geothermal_wells`).
- **Derived well status for mapping**: `vw_wells_gis` gained a
  `display_status` column (`'plugged_abandoned'` if any `Well_Work_
  Events` row has `work_type='abandonment'`, else falls back to
  `well_role`) -- deliberately NOT a change to `Wells.well_role` itself
  (P&A is a status, not a role). 17 wells currently qualify, all
  provisional "Unidentified Well (NDWR Log ...)" rows from Session 24's
  batch. **Documented limitation**: wells known P&A only from earlier
  sessions' free-text prose (`64-32`, `IW-3`) do NOT show as P&A unless a
  `Well_Work_Events` row is added for them -- not guess-parsed from notes,
  to avoid false positives. Both website leaflet maps (`data.Rmd`,
  `results.Rmd`) now color/legend by this 5-way status
  (production/injection/monitoring/domestic/P&A), replacing `results.Rmd`'s
  previous fixed-color map and adding P&A to both.
- **Documentation**: `notebooks/05_data_inventory_and_well_network.qmd`'s
  well-log section rewritten to cover the full 3-table structure
  (`Well_Log_Documents`/`Well_Work_Events`/`Well_Lithology`), the Session
  24 batch, PLSS fallback, and status derivation, with live queries and a
  changelog row. `website/pipeline.Rmd`'s live DiagrammeR architecture
  diagram gained an `NDOM` source node, a `Wells` record box, and edges
  for both the well-log and NDOM ingestion pathways (verified by
  evaluating the DOT string directly, not just visually) plus a new
  prose section on adding future well-log batches. `scripts/templates/
  database_diagram.R` (a separate, standalone poster-style diagram,
  renders to `steamboat_poster_workflow.png`) similarly updated and
  regenerated -- required installing `DiagrammeRsvg`/`rsvg` (previously
  absent, silently never rendered before). **Note**: the two PNGs named
  in this file's own "Key Figures" section
  (`steamboat_database_architecture_diagram.png`/
  `steamboat_poster_database_diagram.png`) are dated July 7 and are not
  produced by any current script in this repo -- likely orphaned
  manually-made images from before this project's current schema;
  left as-is rather than hand-edited.
- **New chemistry/geothermometer exports** (`export_website_data_files()`):
  `chem_by_site.csv` (per-sample major-ion long format, joined to
  `site_type`, from `vw_major_ions`) and `geothermometer_by_site.csv`
  (Na/K activity-based + quartz/chalcedony temperature-sweep-derived
  geothermometer estimates -- the latter computed via linear
  interpolation to the temperature-sweep's zero-SI-crossing, a new
  calculation, restricted to the 8 samples with measured discharge
  temperature >50C per Session 15's established caveat that this method
  isn't meaningful for dilute cold water). Also added
  `production_to_port.csv`/`port_to_injection.csv` exports (previously
  DB-only) to back the new alluvial diagram.
- **New visualization packages installed and used on the website**:
  `ggdist`, `ggbeeswarm`, `ggalluvial` (CRAN) and `ComplexHeatmap`
  (Bioconductor, via `BiocManager` -- installed cleanly in this sandbox,
  no fallback needed). Specific uses, each tested against real data
  before committing to it:
  - `results.Rmd`'s temperature-by-logger boxplot replaced with a
    `ggdist::stat_halfeye()` half-eye/raincloud plot (handles the
    ~193K-row temperature table fine since it's density-based, not
    per-point).
  - New chloride-by-site-type chart: `ggbeeswarm::geom_quasirandom()` +
    a transparent boxplot overlay, log-scaled -- shows background creek
    samples spanning ~1-100 mg/L vs. real thermal fumarole/seep/spring
    samples tightly clustered ~600-800 mg/L.
  - New geothermometer comparison chart (paired-point/slope plot, plain
    ggplot2 -- only 7-8 real thermal samples, not a distributional
    case): visually confirms the Na/K-above-measured,
    quartz-below-measured divergence already described in prose.
  - New `ggalluvial` production-well -> port -> injection-well diagram:
    deliberately uses **link counts, not flow volumes** -- real kg/s
    values from Dhakal et al. (2025) Figure 5 exist only in session
    notes, not the database, and the chart's own caption says so
    explicitly rather than presenting invented widths as real
    measurements.
  - New `ComplexHeatmap` sample x analyte heatmap (log-transformed,
    z-scored, row-annotated by `site_type`, hierarchically clustered
    both axes): a genuinely different, clearly informative view --
    thermal samples (fumarole/seep/spring) cluster tightly on the
    high-Na/Cl/K, low-Ca/Mg side; domestic wells cluster oppositely.
- **New GeoPackage layers**: `well_log_documents` (every
  `Well_Log_Documents` row with a coordinate, including
  provisional/unmatched logs -- 53 rows) and `well_work_events` (joined
  to `Wells` for coordinates, one point per status-history event -- 42
  rows), added to `export_geopackage.R`'s standard `layers` list
  (reuses the existing `safe_write_layer()` lat/lon path, no new export
  logic needed).
- **Full verification pass, all against the real `geochem_operational.sqlite`**:
  schema/view rebuild (`create_analysis_views(con)`), `ingest_ndom_wells()`
  re-run (staging table cleared and rebuilt -- pure re-derivation from the
  source xlsx, no data loss -- to regenerate the discrepancy CSV with its
  new columns), `qc_well_log_matches()` re-run, `export_website_data_files()`,
  `build_website()` (the literature-folder-protected wrapper -- confirmed
  `docs/literature/` intact at 39 files afterward), `export_geopackage()`
  (18 layers, all succeeding except a pre-existing, not-newly-introduced
  `temperature_timeseries` geometry gap -- see Session 12 notes on view
  build order -- which left a stale-but-valid layer from a prior run
  rather than failing), and `run_qc_checks()` (0 PHREEQC run failures, 0
  logger outliers). **Real, re-discovered gotcha**: `render_site()`'s
  `docs/data/*.csv` cleanup (documented since Session 12) fired again
  during this session's manual testing since `export_website_data_files()`
  was only called once before `build_website()` in that test sequence --
  re-ran it after, per the established double-call pattern; `run_pipeline.R`
  itself already calls it both before and after, so this is a
  testing-order artifact, not a pipeline bug.
- **Final counts**: 65 `Well_Log_Documents`, 187 `Wells` (180 with
  coordinates), 42 `Well_Work_Events`, 5 `Well_Lithology` rows, 17 wells
  showing `display_status='plugged_abandoned'`, 49 `NDOM_Well_Records`.
- **Not done this session**: this session's changes are not yet
  committed/pushed to git (touches many CRLF files, all edited via the
  established `readLines()`/`writeLines(sep="\n")` round-trip); the
  pre-existing `temperature_timeseries` GeoPackage-layer geometry gap
  (Session 12) was newly re-observed but not fixed (out of this
  session's scope); DEMO database not rebuilt with any of this session's
  changes.

## Session 26 updates (2026-09-12, continued): temperature_timeseries view/GeoPackage-layer bug fixed at the root

Investigated the `temperature_timeseries` GeoPackage geometry gap
flagged as "pre-existing, not fixed" at the end of Session 25.

- **Root cause confirmed**: two different files each defined a view
  named `vw_temperature_timeseries` with **incompatible columns** --
  `create_analysis_views.R`'s had `logger_id` (required by
  `build_analysis_products.R`'s `build_thermal_summary()`, which groups
  by it) but no geometry; `create_gis_views.R`'s had `geom_wkt` but no
  `logger_id`. Whichever `CREATE VIEW` ran last simply won, silently,
  with no error -- purely a function-call-order dependency in
  `run_pipeline.R` (`create_analysis_views(con)` at line ~565, then
  `create_gis_views(con)` at line ~911, so a full pipeline run is fine,
  but any manual/partial re-run that calls only one of the two --
  exactly what Session 25's interactive verification did when it called
  `create_analysis_views(con)` alone to refresh `vw_wells_gis` --
  silently leaves the database in the "wrong" state for GIS export).
- **A second, independent, previously-unnoticed bug found in the same
  investigation**: the GIS version's `timestamp` column was never
  converted from the raw storage format at all (`Temperature_
  Observations.timestamp` is stored as Unix-epoch-seconds text) -- so
  even when the "GIS" version *did* win, its exported timestamps would
  have been raw epoch numbers, not real dates. This had never been
  caught before because nobody had compared the two definitions' output
  side by side.
- **Fixed by unifying into one definition** (in `create_analysis_views.R`,
  the file that runs first): `vw_temperature_timeseries` now carries
  `logger_id`, `location_id`, `coord_key`, `location` (name), `latitude`,
  `longitude`, a correctly-converted `timestamp`, `temperature`, AND a
  `geom_wkt` (NULL when the logger's location has no coordinate) all at
  once -- both consumers' needs met by the same view, so no caller can
  leave the database in a half-updated state again.
  `create_gis_views.R`'s competing definition (and its `DROP VIEW`) was
  removed entirely, with a comment explaining why, rather than just
  re-flagging the fragility again for a future session to rediscover.
- **A third, real bug surfaced immediately by testing the fix**:
  ~11,000 of ~205,000 rows have no matching `Locations` coordinate (a
  logger with no location, or a location missing lat/lon) and get
  `geom_wkt = NULL` -- `sf::st_as_sf(..., wkt = "geom_wkt")` fails
  **outright for the entire layer** the moment even one row has a NULL
  WKT string, not just those rows. Fixed in `export_geopackage.R` by
  filtering the export query itself (`WHERE geom_wkt IS NOT NULL`),
  consistent with how `vw_wells_gis`/`vw_locations_gis` already filter
  to coordinate-having rows -- the underlying analysis view stays
  unfiltered (broader) since `build_thermal_summary()` etc. want every
  row regardless of geometry.
- **Verified end-to-end against the real `geochem_operational.sqlite`**
  (no separate backup needed -- pure view/query logic, no data
  mutation): rebuilt both view-functions in the correct order,
  confirmed `build_thermal_summary()` and `build_temp_gradient_links()`
  (the two real consumers) both still work correctly against the
  unified view, then re-ran `export_geopackage()` -- `temperature_
  timeseries` now exports 193,656 real point features with `logger_id`,
  a correctly-converted `timestamp`, and real `POINT(...)` geometry all
  together, confirmed by reading the layer back out of the `.gpkg` file
  directly. Final `run_qc_checks()` pass clean (0 PHREEQC failures, 0
  logger outliers).
- **Not done this session**: DEMO database not rebuilt with this fix;
  this session's three files (`scripts/analysis/create_analysis_views.R`,
  `scripts/ingest/create_gis_views.R`, `scripts/ingest/export_geopackage.R`)
  not yet committed/pushed to git.

## Session 27 updates (2026-09-12, continued): Sorey & Colvard (1992) integrated as a historical baseline

User added `docs/literature/Sorey_StmbtSprgsHSActivity_1992.pdf` (a
297-page USGS Administrative Report for the BLM, Sorey & Colvard 1992,
never previously cited anywhere in this project) and asked for a
thorough review of its figures/tables/text and how it could extend this
project's own long-run record and documentation.

- **Confirmed the PDF has a real, OCR'd text layer** (extracted directly
  with `pdftotext -layout`, not guessed) despite being a large scanned
  volume -- readable in full via `bash`/`pdftotext`, unlike the more
  limited toolset an explore-subagent first tried this with.
- **Table 1 chemistry (1950-1991, 9 features) ingested for the first
  time**: new `data/raw/historical/sorey1992_table1_chemistry.csv` +
  `scripts/ingest/ingest_historical_sorey1992.R`
  (`RUN_INGEST$historical_sorey1992`, `TRUE` in profiles 1/2). Resolved
  features (`21-5`->`21-5R` via existing alias, `PW-1/2/3` exact
  matches) reuse existing `Wells` coordinates; unresolved features
  (`83A-6`, `Cox 1-1`, `GS-58`, `GS-59`, "hot spring 6") get new,
  coordinate-less provisional `Locations` rows rather than being
  dropped -- same posture as the well-log/NDOM provisional-entity
  patterns. Stores HCO3 under the project's standard `Alkalinity` code
  (already true HCO3-mass basis, no CaCO3 conversion needed here);
  keeps SiO2 under a **new, distinct `SiO2` code** (not this project's
  `Si` element code) since the mass-basis equivalence between the two
  was not independently confirmed -- flagged, not assumed. TWH
  (wellhead, a real measurement) -> `temperature`; TDH and the Na-K-Ca
  geothermometer estimate are stored as separate, clearly-derived codes
  (`temperature_downhole`, `temperature_geothermometer_nakca`) so they
  can never be mistaken for a field measurement downstream.
- **Real bug caught and fixed while testing this**: `readr::read_csv()`
  auto-parsed the `sample_date` column into a real `Date` object, which
  RSQLite/DBI then silently stored as a numeric day-since-epoch value
  rather than the intended `"YYYY-MM-DD"` text -- the exact same bug
  class already flagged project-wide for `Sampling_Events.date`. Fixed
  with an explicit `col_types = cols(sample_date = col_character())`;
  caught by testing against a scratch DB copy before ever touching the
  real database.
- **A second real bug found and fixed while running the full pipeline
  after this ingest**: the new provisional Locations rows (no
  coordinate) fed into `vw_major_ions` (via `vw_sample_master`, which
  builds `geom_wkt` unconditionally) produced `geom_wkt = NULL` for
  several rows, which made `export_geopackage()`'s `major_ions` layer
  fail **entirely** (`sf::st_as_sf()` errors on the whole layer if even
  one row has a NULL WKT string) -- the exact same bug class already
  fixed for `temperature_timeseries`/`vw_wells_gis` in Sessions 7/26,
  latent here only because no major-ion sample had ever had a
  NULL-coordinate Locations row before. Fixed the same way: added
  `WHERE geom_wkt IS NOT NULL` to the `major_ions` export query in
  `export_geopackage.R`. Verified: `major_ions` now exports 2,805 rows.
- **Well/site cross-reference against `Wells`/`Well_Aliases`/
  `Locations`**: most named wells/springs in Table 1 and Table 10 were
  checked. Several names were found **already independently resolved
  from unrelated sources**, months before this 1992 report was read --
  `Boyd Well`/`Rogers Well`/`Jeppson Well` (NDEP), `Curti Barn`/`Curti
  Domestic Well` (Klein 2007), and "Steamboat Creek at Rhodes Road"
  (this project's own SBRR conductivity-logger site, plus existing
  Locations `SB5`/`SB6`) -- a genuine, independent validation that
  these are the same real, multi-decade monitoring locations. Still
  unresolved (consistent with, and in several cases literally the same
  names as, gaps already flagged in earlier sessions): `83A-6`, `Cox
  1-1`/`COX-1`, stratigraphic test wells (`strat 2/5/6/7/9/13/14`),
  GS-numbered pre-Ormat wells (`GS-58`, `GS-59`), `Steinhardt`,
  `MacKay`, `Woods`, `Tangen`, `PTR-1/2`, `Bianco`, `Brown School`,
  `STMGID Went`. None guessed or fabricated. "Hot spring 6" (sampled
  1977, ceased flowing entirely by 1987 per this same report) is
  flagged as thematically important: exactly the class of
  historically-active-now-dormant Lower Sinter Terrace spring this
  thesis's own spring-remapping fieldwork is designed to find.
- **Cl/B and Cl/Li ratio cross-check, a real quantitative "then vs.
  now" finding**: Sorey & Colvard's 1990-91 Cl/B = 19.3 +/- 1.7 is
  closely matched by this project's own real 2024-2026 thermal FIELD
  samples (Cl/B ~20-23) -- the same conservative-element geochemical
  signature, essentially unchanged 35 years later. NDEP
  domestic/background wells (Boyd, Jeppson, Rogers) show much noisier
  ratios, consistent with their B values sitting near a plausible
  analytical detection limit (0.05-0.18 mg/L) -- read as DL noise, not
  a real signal, matching this project's established dilute/background
  classification for those wells.
- **Discharge-through-time table assembled** (White 1968's 1955/1964
  estimates, Shump 1985, Collar 1990's 1988-89 values, Sorey & Spielman
  2008/2017, this project's own 2026 poster ~27 L/s) -- a single
  ~70-year view, presented explicitly as transcribed literature values
  (not a live query) in both the new notebook and on the website.
- **Barometric efficiency documented as a recommended, not-yet-runnable
  capability, not implemented against real data**: Sorey's method
  (linear regression of spring water level against Reno Airport
  barometric pressure; BE = 0.42-0.45 for springs 6/12, White 1968's
  0.2-1.18 across other vents) is described precisely, and a
  `compute_barometric_efficiency()` stub with only a synthetic
  self-test is included in the notebook (`#| eval: false`, not wired
  into `run_pipeline.R`) -- confirmed via a live query that this
  database has **no barometric/station-pressure parameter anywhere**
  (`Weather_Observations` only has PRCP/TMAX/TMIN/TAVG/SNOW/SNWD), so
  there is nothing real to run this against yet. Mirrors the existing
  "build the capability, wait for real overlapping data" posture
  already used for PHREEQC mixing/inverse/gas-phase.
- **New notebook**: `notebooks/07_historical_context_sorey1992.qmd` --
  the living reference for this thread (mirrors `01`/`05`/`06`'s
  convention). Rendered successfully end-to-end against the real
  operational database. A pre-existing, unrelated data-quality
  artifact was noticed (not fixed) while building this: one
  `Water_Level_Observations.timestamp` value is the malformed string
  `"7-07-10"`.
- **Documentation updated**: `website/references.Rmd` and
  `docs/literature/annotated_bibliography.qmd` gained a full citation
  and annotation for Sorey & Colvard (1992) (previously cited nowhere);
  `website/results.Rmd` gained a new "A Longer Baseline" section (the
  discharge-timeline chart + Cl/B cross-check, with a link to the new
  notebook) placed just before the existing 27 L/s poster-finding
  section; `website/project.Rmd` got a one-sentence tie-in linking
  "Michael Sorey's classic studies" to this specific 1992 report.
- **Full pipeline run (profile 3, skip-ingestion, `MODE="OPERATIONAL"`,
  `BUILD_WEBSITE=TRUE`) completed with 0 stage failures** after the
  `major_ions` fix; `docs/literature/` confirmed intact (43 files,
  including the new Sorey PDF) after `build_website()`'s
  literature-folder-protection wrapper ran (one harmless "Permission
  denied" warning on a file that was already present and unchanged,
  same benign pattern noted in Session 19).
- **Known pre-existing gap, not fixed this session (out of scope)**:
  website pages link to `notebooks/0N_*.html` (e.g. the new
  `notebooks/07_historical_context_sorey1992.html` link added this
  session), but nothing in `run_pipeline.R` or `build_website()` copies
  rendered notebook HTML (`output/reports/notebooks/`, gitignored) into
  `docs/notebooks/` -- these links are very likely already broken on
  the live GitHub Pages site for `06` and now `07` too, not something
  introduced this session.
- Backed up first to
  `database/archive/geochem_operational_pre_sorey1992_<timestamp>.sqlite`;
  verified against a scratch copy before applying to the real database.
  This session's file changes are **not yet committed/pushed to git**.

## Session 28 updates (2026-09-12, continued): 83A-6/Cox 1-1/GS-5 resolved, well-log date-parsing bug fixed

Follow-up to Session 27, per explicit user request to (1) try to resolve
`83A-6`, `Cox 1-1`, or the GS-numbered wells against NDWR/NBMG records,
and (2) dig into the malformed `"7-07-10"` `Water_Level_Observations`
timestamp flagged (not chased down) while building the Session 27
notebook.

- **`83A-6` and `Cox 1-1` resolved via exact NBMG name matches**, found
  directly in `data/raw/nbmg/Geothermal_Wells.csv`/`GEOTHERM06102019.csv`:
  `Well No. 83A-6` (API 27-031-90080, CPI production well, drilled 1987,
  P&A 2003, Sec 6 T17N R20E) and `Cox I-1` (API 27-031-90051, CPI
  injection well, originally drilled as observation well "Cox No. 1" for
  Phillips Petroleum in 1981, Sec 32 T18N R20E -- explicitly distinct
  from the nearby, differently-permitted `Well No. 65-32`/formerly
  "Cox I-2"). New `data/raw/wells/sorey1992_nbmg_resolved_wells.csv` +
  `register_sorey1992_resolved_wells()` (in
  `scripts/ingest/ingest_historical_sorey1992.R`) creates real `Wells`
  rows with these coordinates; `Cox I-1` also got `Well_Aliases` rows for
  `Cox 1-1`/`COX-1`/`Cox1-1`/`Cox well` (the spellings used in this
  report and flagged unresolved under those names in prior sessions).
- **"GS-58" and "GS-59" turned out not to be real well names at all --
  an OCR artifact, not a missing well.** Re-reading Table 1's own
  footnote list (`8From White (1968).` / `9New seep adjacent to well
  GS-5, analysis by Nevada Division of Health Laboratory.`) shows both
  are superscript footnote markers ("8" and "9") that the PDF's OCR
  layer fused directly onto a single real well name, **GS-5** --
  producing "GS-58" (= "GS-5" + footnote 8) and "GS-59" (= "GS-5" +
  footnote 9). Confirmed two independent ways: NBMG's statewide
  compilation has real wells `GS-1` through `GS-8` (the pre-Ormat USGS
  1950-51 thermal-gradient/chemistry test-hole program, White 1968 Plate
  1) but nothing numbered `GS-58`/`GS-59`; and GS-5's own NBMG record
  (API 27-031-80055, Sec 33 T18N R20E, drilled 1950-1951, chemistry
  suite including Cl) matches both the "Well GS-58" row's 1950 sample
  date and footnote 9's literal "new seep adjacent to well GS-5" text
  for the "Spring GS-59" row. Both `sorey1992_table1_chemistry.csv` rows
  now carry `matched_well_name = "GS-5"` and were renamed/recategorized
  accordingly (the GS-58 row -> "Well GS-5, 1950 sample (White 1968)";
  the GS-59 row -> "New seep adjacent to well GS-5 (1991)", stored as a
  `seep`-type Location, not `spring`, since that's literally what the
  footnote calls it).
- **`ingest_historical_sorey1992.R` extended with a coordinate/identity
  backfill path**: previously, once a Locations row existed (even with a
  NULL coordinate), a re-run would never touch it again. Now, for any
  `SOREY1992_*` Locations row with `latitude IS NULL`, a re-run
  re-attempts the `matched_well_name` lookup and -- only if it now
  resolves -- fills the coordinate AND corrects `name`/`site_type`
  (mirrors `register_well_coordinates.R`'s "only fill if currently NULL,
  never overwrite" idiom, extended here to also cover identity fields
  for this one well-justified correction event). Verified idempotent
  (0 further changes on a second re-run) on a scratch copy before
  applying to the real database.
- **Real, independent bug found and fixed while investigating the
  malformed timestamp**: `ingest_well_logs.R`'s `.safe_completion_date()`
  tries `as.Date(x, format = "%m/%d/%Y")` first, and R's `%Y` silently
  accepts a 2-digit year as a literal, unpadded year value (year 7 CE)
  rather than rejecting the format mismatch the way the function's
  design assumed -- so well-log document 104216's
  `completion_date_raw = "7/10/07"` "matched" this format immediately,
  producing the nonsensical `Water_Level_Observations.timestamp` value
  `"7-07-10"` instead of falling through to a better parse. Fixed by (1)
  adding an explicit `%m/%d/%y` format attempt, and (2) a
  plausible-year-range sanity check (1900 to next calendar year) that
  every candidate parse must pass before being accepted -- confirmed
  this doesn't change the result for any of the other 60+ real
  `completion_date_raw` values already in `Well_Log_Documents` (all
  either already 4-digit-year or unparseable OCR noise that still
  correctly returns `NA`). The one bad row (observation_id 153437) was
  corrected directly to `2007-07-10` (plausible: document 104216 is a
  "WELL DRILLER'S PLUGGING REPORT," i.e. an abandonment report, dated
  July 2007) -- this is now the only real `driller_report`-source
  timestamp correction needed database-wide; confirmed no other
  malformed timestamps exist in `Water_Level_Observations`.
- **Applied to the real `geochem_operational.sqlite`** (backed up first
  to `database/archive/geochem_operational_pre_sorey_resolve_<timestamp>.sqlite`,
  verified against a scratch copy first): 3 new `Wells` rows (`83A-6`,
  `Cox I-1`, `GS-5`), 4 aliases added for `Cox I-1`, 4 Locations rows'
  coordinates/identities backfilled (`83A-6`, `Cox 1-1`, and both
  GS-5-derived rows), 1 `Water_Level_Observations` timestamp corrected.
  `notebooks/07_historical_context_sorey1992.qmd` updated with a new
  "4.1 Resolving 83A-6, Cox 1-1, and the GS-58/GS-59 OCR artifact"
  section and an updated timestamp-bug aside; re-rendered successfully
  against the real database.
- **Still unresolved, not attempted this session** (consistent with
  prior sessions' flags, none guessed): the stratigraphic test wells
  (`strat 2/5/6/7/9/13/14`), `Steinhardt`, `MacKay`, `Woods`, `Tangen`,
  `PTR-1/2`, `Bianco`, `Brown School`, `STMGID Went`, `OW-1`. "Hot spring
  6" also remains genuinely unresolved (no modern counterpart identified
  in this database) -- unchanged from Session 27, still flagged as
  thematically important for the thesis's own spring-remapping work.
- **Incidental catch-up noticed while re-running `register_well_network()`**
  to pick up the new `Cox I-1` aliases: a `14-33 -> Galena 3`
  `Production_Port_Links` row from Session 22's `dhakal_well_network.csv`
  edit had apparently never actually been applied to the real operational
  database until now (link_id 25) -- a harmless, idempotent catch-up, not
  a new decision.
- This session's file changes (`scripts/ingest/ingest_historical_sorey1992.R`,
  `scripts/ingest/ingest_well_logs.R`, `scripts/run_pipeline.R`,
  `data/raw/historical/sorey1992_table1_chemistry.csv`,
  `data/raw/wells/sorey1992_nbmg_resolved_wells.csv` [new],
  `data/raw/wells/well_aliases.csv`,
  `notebooks/07_historical_context_sorey1992.qmd`) are **not yet
  committed/pushed to git**. Several CRLF files (`ingest_historical_sorey1992.R`,
  `ingest_well_logs.R`, `run_pipeline.R`) were edited via the established
  `readLines()`/`writeLines()` round-trip since the `edit` tool's
  exact-string matching intermittently failed against them, same
  recurring caveat as many prior sessions -- notably, this session also
  found that a file freshly created by the `write` tool itself
  (`ingest_historical_sorey1992.R`, `07_historical_context_sorey1992.qmd`)
  can already come out CRLF-terminated on this Windows setup, not just
  pre-existing files -- worth remembering for any brand-new file, not
  just edits to old ones.

## Session 28 continued (2026-09-12): Sorey & Colvard (1992) Tables 3, 6-9, and Appendix G mined

Follow-up to the same session's 83A-6/Cox 1-1/GS-5 resolution work, per
explicit user request to "touch all of" Table 8 (stratigraphic test
wells), Appendix G (stream discharge/chloride flux), Table 3 (South
Truckee Meadows wells), and to scope Tables 4-7/9 -- read directly via
`pdftotext -layout` again, not guessed.

- **Table 8 (stratigraphic test wells) registered as real, coordinate-less
  provisional `Wells` rows** (strat 2, 5, 6, 7, 8, 9, 13, 14;
  `well_role='monitor'`) via new rows appended to
  `data/raw/wells/sorey1992_nbmg_resolved_wells.csv`. No coordinates exist
  anywhere in the source table; two real proximity clues from the report's
  own text are preserved as prose notes only, never converted into a
  fabricated coordinate: strat 13 "located next to CPI production well
  23-5" (independently corroborated by a real hydraulic-connection signal
  -- strat 13's water level rose during a 23-5 shut-in), and strats 2/5/9
  "in the general vicinity of the Cox 1-1 injection well". Real
  depth/formation/temperature/water-level-change facts captured in
  `notes` for all eight.
- **Table 3 (South Truckee Meadows ground-water wells) -- two new exact
  NBMG matches, one tentative, several still unresolved.** `Steinhardt`
  and `Brown School` are exact NBMG Geothermal_Wells name matches
  ("Steinhardt Geothermal Well"; "Brown School Geothermal Well", owned by
  "Brown Elementary School" -- an unambiguous identity confirmation), both
  independently corroborated by the report's own directional description
  (NE / N of the ACEC respectively) matching their real coordinates. `Bianco`
  is only a **surname match** in NDWR's Truckee Meadows WellLogQuery table
  ("BIANCO, U J", Log 5916, Sec 28 T18N R20E, completed 1961) --
  resolved to a bare PLSS-section centroid via the BLM PLSS REST service
  (`.convert_plss_to_latlon()`, reused from the well-log parser,
  `coordinate_uncertainty_m=800`), and flagged as **tentative, not
  confirmed**: its NDWR drill depth (232 ft) does not match Table 3's own
  Bianco depth (400 ft). `PTR-1`, `PTR-2`, `STMGID MW-3`, `STMGID MW-4`
  remain genuinely unresolved after a fresh NDWR/NBMG owner-name search
  (NBMG's only STMGID-named record, "STMGID Well 4 Shadowridge", is a
  production well, not this monitor-well pair, and was explicitly NOT
  used) -- all four registered as real, coordinate-less provisional
  `Wells` rows anyway, carrying their Table 3 depth/temperature/
  chloride-range/water-level-decline facts in `notes` rather than leaving
  them stranded in prose only. `Herz-2` (explicitly a *geothermal* well
  per the report's text, distinct from "the shallower Herz domestic
  well") could be either of NBMG's two already-ambiguous "Harold Herz
  Geothermal Well 1/2" candidates (flagged since Session 3, ~1.3 km
  apart) -- Table 3's own OCR for this well is split across multiple
  garbled rows and could not be confidently disentangled; left
  inconclusive, not guessed.
- **Tables 6/7 (CPI/SB GEO well-completion information) filled a
  currently-100%-empty field.** `Wells.top_perforation`/
  `bottom_perforation` were NULL for every CPI/SB GEO well in this
  database, even the already-coordinate-resolved ones. New
  `data/raw/wells/sorey1992_perforation_data.csv` +
  `register_sorey1992_perforation_data()` (in
  `ingest_historical_sorey1992.R`) fills them, but only after real,
  well-by-well verification -- the source table's OCR layout has visible
  column-alignment slippage across rows, so each well's casing-depth +
  open-hole-thickness was checked to reconcile exactly against its
  stated total depth before being trusted (confirmed for every SB GEO
  well and for 83A-6). Filled for `83A-6`, `Cox I-1`, `PW-1`, `PW-2`,
  `PW-3`, `21-5R`, `IW-3` (7 wells, 18 fields total) -- per-field,
  fill-only-if-NULL, never overwriting an existing value (mirrors
  `register_well_coordinates.R`'s idiom). **Two real, deliberately
  unfilled conflicts**: `23-5`'s 1990-era report depth (2422 ft) is 19%
  shallower than the 3001 ft already on record (NDOM-sourced), and
  `IW-2`'s 1990 report depth (1403 ft) is less than a third of the
  4700 ft on record -- both almost certainly explained by subsequent
  deepening of these still-active wells, not a data error or misread.
  Rather than overwrite or awkwardly average, the 1990 construction facts
  are recorded in `Wells.notes` as explicitly historical, and
  `top_perforation`/`bottom_perforation` were left NULL for both.
- **Appendix G (stream discharge and chloride flux) -- documented, not
  parsed further.** Confirms the real 1988-89 methodology behind the
  already-used Collar (1990) discharge numbers: chloride as a
  conservative tracer, an 820 mg/L thermal / 6 mg/L non-thermal
  end-member split, gaining/losing-reach mass-balance equations --
  methodologically almost identical to this project's own SBRR/SBBV Cl
  mass-balance approach, predating it by ~35 years. Four real synoptic
  survey dates identified (6/26-6/30/1988, 7/1-7/2/1988, 8/9/1988,
  3/4/1989) across ~40 named stream/ditch stations. **Deliberately not
  parsed further**: the raw per-station table (Table G-1) is visibly
  OCR-misaligned (values shifted relative to station-name rows, in some
  blocks by a full row) -- the same class of "real data trapped in a
  badly-OCR'd table" problem already flagged for the NDEP TFT Appendix D
  tables and well-log lithology tables. The aggregate numbers actually
  used in the discharge-timeline chart are already the synthesized
  output of this same appendix, so nothing new was lost by not parsing
  it further; a denser historical Cl-flux series would require reading
  the scanned page images directly, not the OCR text -- flagged as a
  much larger, separate effort, not attempted.
- **Table 9 (reservoir parameters) -- reference-only, no schema change.**
  Four dated aquifer/interference-test results (1980, 1986, 1987, 1988)
  with real transmissivity (~1,250-9,500 ft2/day) and storage-coefficient
  (~10^-4-10^-3) values, added as a plain reference table in the notebook
  since no table in the current schema models a dated aquifer test and
  no immediate analytical use was identified; worth revisiting if
  hydraulic-gradient work ever needs a real transmissivity/storage
  reference range.
- **Tables 4/5 (CPI/SB GEO production intervals since 1986) --
  deliberately NOT built.** Real, structured, dated on/off production
  intervals with net production rates exist in the source, but modeling
  them properly would need a new table distinct from the current
  `Production_Port_Links`/`well_role` (which model the *current*,
  2024-Dhakal-diagram flow network, not a historical day-by-day
  production record) -- flagged as a candidate future addition, not a
  quick add, and out of scope for this pass.
- **The 40 figures**: re-confirmed out of scope -- line-plot hydrographs
  with no accompanying data table, not extractable without digitizing
  pixel positions from scanned page images.
- **`notebooks/07_historical_context_sorey1992.qmd` substantially
  extended**: new subsections 4.2 (Table 3), 4.3 (Table 8), 4.4 (Tables
  6/7), a new "Appendix G and Table 9" section, updated cross-reference
  table/prose reflecting all of the above, and a new changelog row.
  Rendered successfully end-to-end against the real operational
  database (all new query chunks execute cleanly).
- **Applied to the real `geochem_operational.sqlite`** (backed up first
  to `database/archive/geochem_operational_pre_sorey_tables368_<timestamp>.sqlite`,
  verified against a scratch copy first): 15 new provisional/resolved
  `Wells` rows, 18 `top_perforation`/`bottom_perforation` fields filled
  across 7 wells, 9 historical-construction notes appended. Idempotent
  re-run confirmed (0 new rows/fields on a second pass).
  `export_geopackage()` re-run cleanly afterward (13 layers, `wells`
  186 rows up from 180, `locations` 171 up from 167, `major_ions` 2822
  up from 2805 -- no NULL-geometry regressions from the new
  coordinate-less rows, since none of them feed a GIS layer with an
  unconditional `geom_wkt` build). QC re-run clean (0 PHREEQC failures).
- **Not done this session**: no attempt to disambiguate `Herz-2` further
  (would need the actual scanned Table 3 page image, not just OCR text);
  Tables 4/5 not modeled; Appendix G's raw station-level data not
  digitized. This session's file changes are committed and pushed to
  git (see commit history) -- includes a `git add -f` for the new
  gitignored `data/raw/wells/sorey1992_perforation_data.csv`, per this
  project's standing convention for hand-maintained CSVs under the
  blanket-ignored `data/raw/`.

## Session 29 (2026-09-12, continued): Leapfrog 3D geologic model export -- scoped as a proposed direction, not built

User asked about Leapfrog-ready well-data layers, incorporating fault
data (from the Dhakal figure or literature) and eventually lithology/
alteration for a full 3D geologic model to inform PHREEQC end-member
grouping and a future MODFLOW build, and whether to overlay in ArcGIS
first. Checked feasibility directly against the database rather than
guessing, then wrote up the full scope as a new **"Planned: Leapfrog 3D
geologic model export"** section in `README.md` (right after the
existing "Planned: potentiometric surfaces" section) -- **nothing was
built this session**, this is documentation/scoping only, for a future
session to implement.

- **Well collar data: mostly ready.** 109 of 205 `Wells` rows have
  lat/lon + `elevation_m` + `total_depth` all populated (collar-ready);
  ~76 more have partial data. No deviation surveys exist anywhere in
  this project, so every hole would import as a straight vertical trace
  -- stated explicitly in the README, not silently assumed.
- **Lithology: not ready, a real gap.** `Well_Lithology` has only 5
  rows, all `well_id = NULL` and tagged
  `confidence=ocr_heuristic_unvalidated` (unusable OCR garbage from the
  well-log pipeline, see Sessions 9-11/24). 83 wells have
  `top_perforation`/`bottom_perforation` (casing/screen interval) --
  useful as a distinct "completion interval" layer, explicitly NOT the
  same thing as lithology.
- **No fault data or alteration data exists anywhere in this project.**
  The only Dhakal-sourced spatial data on disk
  (`data/raw/arcgis/dhakal .shp/`) is well points and power-plant
  polygons, not fault traces -- the Dhakal Figure 1 fault map (and
  possibly White et al. 1964, PP 458-B, Plate 1) are raster figures in
  PDFs, not georeferenced layers, and need manual digitizing (ArcGIS,
  using this project's own well coordinates as control points), not
  something OCR/scripting can extract. No alteration source has been
  identified at all yet.
- **Proposed design** (full detail in README.md): a new, separate,
  optional pipeline stage (`scripts/leapfrog/export_leapfrog.R`,
  `RUN_ANALYSIS$leapfrog_export`, default `FALSE`) mirroring
  `export_geopackage.R`'s pattern exactly -- never replaces or slows
  down the GeoPackage export. Proposed "ArcGIS out, ArcGIS back in"
  loop: export wells/locations to the GeoPackage (already possible
  today) as digitizing control points -> user digitizes faults/
  alteration in ArcGIS -> a new `ingest_fault_traces.R` (mirrors
  `register_facility_areas.R`'s `sf::st_read()` + reproject pattern)
  reads the shapefile back into new `Fault_Traces`/`Alteration_Zones`
  tables -> `export_leapfrog.R` reformats those same tables into
  Leapfrog's collar/survey/interval/polyline input format.
- **Three open decisions explicitly deferred to the user, not guessed**:
  (1) coordinate system for the Leapfrog export (lat/lon WGS84 vs. UTM
  Zone 11N meters -- leaning UTM but undecided); (2) who digitizes
  faults and how (ArcGIS-led with well-coordinate control points
  recommended over a rough automated pixel-referenced attempt); (3)
  alteration data source (White et al. 1964, PP 458-B is an unchecked
  candidate; otherwise stays out of scope).
- **Proposed 4-phase build order for the next session** (README has
  full detail): (1) `export_leapfrog_wells(con)` alone -- collar +
  assumed-vertical survey + completion-interval proxy, buildable today,
  no external dependency; (2) `Fault_Traces`/`Alteration_Zones` schema
  + ingestion, structure-only, testable against a synthetic/empty
  shapefile (same "build the capability, wait for real data" posture
  already used for PHREEQC mixing/inverse); (3) extend
  `export_leapfrog.R` once real digitized fault/alteration data exists,
  resolving the CRS decision then; (4) much later, out of scope for now
  -- a MODFLOW grid/zone export and revisiting PHREEQC end-member
  grouping by fault-bounded compartment.
- **Not done this session**: no code written, no schema changes, no
  database changes -- purely a README.md scoping section plus this
  AGENTS.md entry. `README.md` edited via the established
  `readLines()`/`writeLines()` round-trip (CRLF file, `edit` tool's
  exact-string matching failed against it, same recurring caveat as
  every other CRLF file in this project). Not yet committed/pushed to
  git.

## Session 30 (2026-09-25): Leapfrog export, real PHREEQC mixing/inverse, ArcGIS Cl points, statistics-driven Cl-timeline work, Steinhardt data-quality fix

Large session executing (not just scoping) the Leapfrog/PHREEQC/ArcGIS/
statistics plan from Session 29's scoping work, plus two new literature
documents and a real, previously-undetected data-quality fix.

- **New literature**: `Collar.pdf` (Collar, R.J. and Huntley, D. 1990,
  12th New Zealand Geothermal Workshop) and `of00-037.pdf` (Janik et al.
  2000, Anderson Springs/SE Geysers, explicitly flagged as a **different
  geothermal system**, methodological analog only -- same pattern as the
  Newman-Colorado flag). Collar & Huntley's Figure 1 is a real fault and
  air-photo-lineament map with 10 already-coordinated wells visible on it
  (a materially better fault-digitizing candidate than the Dhakal flow
  diagram); gives a second reservoir-parameter point (spring 42w, T=3000
  ft2/day, S=2.6e-3) and a discharge-deficit statistic (3-4 gpm measured
  vs. 34-40 gpm predicted, 1988). Cited in `references.Rmd` and
  `annotated_bibliography.qmd`; both added to `notebooks/
  07_historical_context_sorey1992.qmd` (new Section 4.6). Cox I-1's
  previously-NULL elevation filled (5050 ft = 1539.24 m) from this source.
- **`scripts/leapfrog/export_leapfrog.R` built and wired in**
  (`RUN_ANALYSIS$leapfrog_export`, default FALSE): collar/survey/
  completion-interval CSVs in UTM Zone 11N (EPSG:26911) -- resolves the
  CRS open decision from Session 29's scoping. 110 wells fully
  collar-ready, 95 partial (reference-only), all vertical (no deviation
  surveys exist), 74 with a completion-interval (explicitly NOT
  lithology) proxy.
- **`Fault_Traces`/`Alteration_Zones` schema built**
  (`database/schema/11_fault_traces_schema.R`), structure-only -- no real
  digitized fault/alteration data yet. Distinguishes mapped faults
  (inferred/concealed) from air-photo lineaments, per Collar & Huntley's
  own legend.
- **First REAL (non-synthetic) PHREEQC mixing and inverse runs.**
  Populated `data/raw/phreeqc/mixing_config.csv`/`inverse_config.csv`
  (previously header-only templates) with real sample_ids: thermal
  end-member = sample 816 (SBF_0001, Cl=815 mg/L), meteoric end-member =
  sample 829 (Boyd Domestic Well, Cl=45 mg/L) -- explicitly a
  typical/representative end-member pair, not a real-time-paired
  validation (same posture as Sorey & Colvard's own 820/6 mg/L split).
  Mixing run stored 1,443 real `PHREEQC_Mixing_Results` rows; found that
  `SBW_0002` (Cl=849) is slightly MORE concentrated than the chosen
  thermal reference itself (mixing fraction 1.044) -- a genuine, novel
  finding, not an error. Inverse run (target=Soccer Field Monitoring
  Well, sample 827; end-members 816+829; phases Calcite+Quartz) found 1
  real candidate solution (unlike the synthetic self-test, which finds 0
  due to a known C(-4) numerical quirk).
- **New `chloride_points` GeoPackage layer** (`export_geopackage.R`) --
  one row per real Cl sample/date/location, for ArcGIS's own
  interpolation tools to consume directly (Empirical Bayesian Kriging/
  IDW), distinct from the all-major-ions `major_ions` layer. 763 rows.
- **Statistics-driven Cl-timeline analysis, added to notebook 07**: a
  naive Cl-vs-year regression across all thermal-influenced samples is
  significant (p=0.0099) but this is confounded by which wells count as
  "thermal" -- excluding two 2024-only intermediate NDEP wells weakens it
  to marginal (p=0.099); reported honestly as an open question, not a
  confirmed trend. A proper two-sample t-test on real thermal Cl/B
  ratios (excluding Cox and the SBRR/SBBV creek mixing points) finds the
  1990-91 vs. 2024-2026 difference (19.6 vs. 21.9) is small but
  **statistically significant** (p=0.015) -- revises the earlier
  Session 27 "closely matching... essentially unchanged" claim to
  something more precise. Documented why the discharge-timeline chart
  has no confidence intervals (no source reports measurement
  uncertainty -- fabricating one would be worse than omitting it).
- **New database-computed discharge point**: this project's only real
  paired Cl+discharge dataset (SBRR Cl=17.1, SBBV Cl=126 mg/L, both
  2026-05-01; USGS gauge 10349300 discharge ~11.2 cfs near the SBRR
  sample time) gives Q_TW = 42.1 L/s using the same formula as the
  poster's own 27 L/s figure -- a real, reproducible, distinctly-dated
  point, not a re-quote of the poster. The ~56% gap versus the poster's
  averaged figure is larger than the ~25%-or-less seasonal Cl-flux
  variability Sorey & Spielman (2017) themselves document (already
  cited in this project, not a new source) -- flagged as a real,
  partially-explanatory effect (matches the user's own recollection of
  seasonal Cl-outflow variability from their poster), not a full
  reconciliation.
- **Real, previously-undetected data-quality fix: Steinhardt's chloride
  range.** Table 3 of Sorey & Colvard (1992) had (in Session 28-continued)
  attributed a "16-22 mg/L" chloride range to the Steinhardt well from
  the table's own OCR'd row position. Re-reading the report's narrative
  text (p.52) directly shows it unambiguously ties a 300-to-140 mg/L
  chloride DECLINE since 1987 to "the mixed-water Steinhardt well"
  specifically -- the narrative is far less prone to the already-flagged
  OCR row-misalignment than a table cell position. Corrected
  `Wells.notes` for both Steinhardt and Brown School (the table value
  most likely belongs to Brown School instead, or is itself
  unreliable -- left unconfirmed, not guessed) and added two real dated
  Lab_Analyses rows for Steinhardt (1987=300 mg/L, ~1990=140 mg/L,
  bracketing the described decline; a new Locations row created for it
  since it previously had none).
- **Plots reworked three times this session per direct, iterative
  critique** -- worth recording the exact feedback loop since it's a
  real example of catching a live analysis mistake: (1) well/spring
  labels and lines added to the Cl-timeline plot, connecting real repeat
  measurements, with the 6 single-snapshot 2026 FIELD samples dropped
  from that specific plot (shown elsewhere) to reduce crowding; (2) the
  discharge chart gained the two new points above with text labels; (3)
  the Cl/B plot was consolidated from two separate, confusingly similar
  attempts into one (date on the x-axis, not era-on-y), with t-test
  statistics moved into the figure caption -- and a live mistake was
  caught and fixed mid-session: an early re-run of this plot in the
  console forgot to exclude the background/domestic and intermediate
  wells, pulling in Boyd/Jeppson/Rogers' near-zero-boron ratios and
  inflating the "modern" mean to 83 instead of the correct 21.9; caught
  immediately by comparing against the already-correct notebook version
  before it was ever written anywhere permanent.
- **Applied to the real `geochem_operational.sqlite`** (backed up first
  to `database/archive/geochem_operational_pre_steinhardt_fix_<timestamp>.sqlite`):
  Steinhardt/Brown School notes corrected, 1 new Locations row, 2 new
  Sampling_Events/Samples/Lab_Analyses rows, Cox I-1 elevation filled.
  QC re-run clean (0 PHREEQC failures); GeoPackage re-exported cleanly
  (14 layers now, up from 13, `major_ions` 2824 up from 2822, `locations`
  172 up from 171); Leapfrog export re-verified (110/95/220/74 rows,
  unchanged in count but now includes Cox I-1's elevation).
- **Not done this session**: Brown School's real chloride range remains
  genuinely unconfirmed (flagged, not resolved); no attempt yet to
  digitize real fault traces from Collar & Huntley Figure 1 (schema
  ready, no data); this session's file changes are committed and pushed
  to git (see commit history).

## Session 31 (2026-09-25, continued): README setup guide, barometric-pressure ingestion + real BE calculation, facies-clustering/fault-overlay Q&A

Follow-up covering three user requests: a deeper README setup/run
guide (written, no build needed); scoping a real barometric-pressure
source (answered: NOAA LCD or IEM ASOS for Reno Airport, no live web
fetch available this session); and, once the user supplied real IEM
ASOS pressure data, building the actual ingestion + a real barometric-
efficiency calculation. Also answered direct questions about the
existing facies-clustering work and fault-trace overlay status.

- **README.md**: new top-level "Setup and Running the Pipeline"
  section (prerequisites incl. optional feature-specific packages and
  the PHREEQC executable, first-time setup, non-interactive/scripted
  invocation with a real `RUN_INGEST`/`RUN_ANALYSIS` example, typical
  workflows, where outputs land) inserted right after Overview, plus a
  matching TOC entry. Edited via `readLines()`/`writeLines()` (default
  `"\n"` separator) since this is a CRLF file.
- **Facies clustering / fault-trace overlay -- answered, nothing new
  built** (direct answers to the user's questions, confirmed by reading
  the actual scripts): `scripts/analysis/cluster_hydrochemical_facies.R`
  and `facies_depth_map.R` are pure in-R/ggplot analyses -- cluster
  assignments are **not** written to any database table, have **no**
  GeoPackage layer, and there is **no** flag/metadata table recording
  which clustering method (Ward hierarchical, k, silhouette score,
  mclust cross-check agreement %) produced a given result -- all of that
  currently only exists as console messages and in-memory objects when
  `run_facies_clustering()` is called from the notebook. Real fault
  traces do NOT exist yet from any source, including Dhakal: the only
  Dhakal-sourced spatial data on disk (`data/raw/arcgis/dhakal .shp/`)
  is well points and power-plant polygons, not fault lines -- the
  best real fault-trace candidate remains Collar & Huntley (1990)
  Figure 1 (already flagged in Session 30, still not digitized). The
  `Fault_Traces`/`Alteration_Zones` schema (`11_fault_traces_schema.R`,
  Session 30) is structure-only and would receive Collar & Huntley
  traces once digitized in ArcGIS, per the Session 29 "ArcGIS out,
  ArcGIS back in" loop already scoped in README. Recommended next step
  if the user wants this taken further: (1) digitize Collar & Huntley
  Figure 1 in ArcGIS using this project's own well coordinates as
  control points, ingest via a new `ingest_fault_traces.R`; (2) add a
  small persisted `Facies_Clusters`/`Facies_Cluster_Assignments` table
  (method, k, silhouette/agreement metadata + per-sample cluster
  label) and a GeoPackage layer, so the clustering result can be
  overlaid against the digitized faults in ArcGIS the same way
  `chloride_points` already supports ArcGIS-side interpolation --
  neither built this session, both flagged as concrete next steps only.
- **Barometric pressure source scoping** (before the user supplied real
  data): recommended NOAA NCEI Local Climatological Data (LCD) for the
  same Reno Airport station already in `Weather_Stations`
  (`USW00023185`) as primary, with the Iowa Environmental Mesonet (IEM)
  ASOS archive (mesonet.agron.iastate.edu) flagged as a quicker
  bulk-download fallback -- explicitly caveated as not live-verified
  since web search/fetch was unavailable this session. The user then
  supplied real IEM ASOS data directly, matching the fallback recommendation.
- **New real barometric-pressure ingestion**:
  `data/raw/airpressure/README.md` (source, download process, file
  format, database landing spot, known limitations) +
  `scripts/ingest/ingest_barometric_pressure.R`
  (`ingest_barometric_pressure(con, base_dir = "data/raw/airpressure")`).
  Deliberately reuses the existing generic `Weather_Observations`/
  `Weather_Stations` tables (no new schema) -- `parameter = "MSLP"`,
  `unit = "hPa"`, `date` holds a full hourly timestamp (the table's PK
  is `(station_id, date, parameter)`, which tolerates this fine).
  Reuses station_id `USW00023185` (the same physical Reno Airport
  already used for NOAA GHCN daily temperature/precipitation) rather
  than registering a second station, even though IEM's own reported
  ASOS coordinate differs by ~2.7 km from the existing GHCN coordinate
  on file (both real points on/near the same airport; the existing
  coordinate is left untouched, per this project's "never overwrite an
  existing field" convention -- only logged to the console). Any file
  anywhere under `data/raw/airpressure/` whose header matches the IEM
  export's column signature is auto-detected, mirroring the existing
  NOAA-weather "new file just works" convention. Idempotent via
  `Weather_Files_Processed` + an anti_join on `(station_id, date,
  parameter)`. Wired into `run_pipeline.R` as
  `RUN_INGEST$barometric_pressure` (`TRUE` in profiles 1/2).
- **New real barometric-efficiency calculation**
  (`scripts/analysis/barometric_efficiency.R`,
  `run_barometric_efficiency()`), replacing the Session 27/29
  synthetic-only stub in `notebooks/07_historical_context_sorey1992.qmd`
  now that real paired data exists. Computes BE two ways per eligible
  well -- Sorey's original level-vs-pressure regression, and a
  first-differenced change-vs-change regression that removes any
  secular trend (a full calendar year of daily transducer data is not
  the same situation as Sorey's own one-week synoptic campaign, where a
  trend has no time to matter; both forms are reported side by side,
  neither presented as simply "more correct"). Deliberately prefers a
  Steamboat Hills-area well (reusing `facies_depth_map.R`'s own
  bounding box) for the overlay plot over whichever well has the most
  overlapping days region-wide, since most of this database's
  `Water_Level_Observations` network is the much wider South Truckee
  Meadows/Reno basin, not Steamboat-specific.
- **Real result**: only two wells qualify as both continuous
  (2025 daily transducer) AND inside the Steamboat field AND
  overlapping the new pressure record -- **STMGID MW10** and
  **STMGID MW3** (South Truckee Meadows GID monitoring wells, resolved
  in Session 4). BE = 0.58/0.60 (level method) and 0.34/0.29 (diff
  method) -- inside White (1968)'s 0.2-1.18 range and the same order
  of magnitude as Sorey & Colvard's own 0.42/0.45 for springs 6/12. Read
  as a real methodological validation that the calculation behaves
  sensibly on real data, explicitly **not** a claim that Steamboat's
  actual thermal springs share this BE -- neither well is a thermal
  spring, and getting a real spring-specific BE still needs continuous
  water level at an actual spring/CPI/SB GEO well overlapping a
  pressure record, which doesn't exist yet. `run_barometric_efficiency()`
  is written to pick up such a well automatically the moment one
  qualifies, not hardcoded to MW10/MW3.
- **Real bugs found and fixed while building/testing this** (all on a
  scratch copy first): `find_eligible_wells()`'s well x method_type
  grouping could return more than one row per `well_id`, causing a
  many-to-many join and duplicate rows in the results table -- fixed
  with `distinct(well_id, .keep_all = TRUE)`. The overlay plot's water-
  level series was pulled for the well's ENTIRE historical record
  (decades, in one case back to 2003) while the pressure series only
  covered 2025-2026 -- `facet_wrap(scales = "free_y")` silently hid the
  mismatch rather than erroring; fixed by restricting both series to
  the real intersecting date range before plotting.
- **Applied to the real `geochem_operational.sqlite`** (backed up first
  to `database/archive/geochem_operational_pre_barometric_<timestamp>.sqlite`,
  verified against a scratch copy first): 15,154 new hourly MSLP
  `Weather_Observations` rows (2025-01-01 through 2026-09-24). Notebook
  07's barometric section rewritten from stub to real result + new
  changelog row; rendered successfully end-to-end against the real
  operational database (`quarto render`, confirmed clean in this
  session, not just assumed).
- **Not done this session**: no `Facies_Clusters` persistence table or
  GeoPackage layer built (recommended above, not requested as a build
  yet); no fault traces digitized; this session's file changes are not
  yet committed/pushed to git.

## Session 32 (2026-09-25, continued): data-folder README sweep, real earthquake catalog, temp-pressure/precip/seismicity analysis, well-completion visualization, fault-trace ingest built

Large follow-up covering a full documentation sweep plus several new
real (not synthetic) analyses requested together: pulling the original
Sorey & Colvard (1992) barometric hydrographs, precipitation-recharge
and earthquake cross-checks, a well-completion/confining-layer
visualization, and scoping PHREEQC's conceptual role -- all written up
in `notebooks/07_historical_context_sorey1992.qmd`.

- **Data-folder README sweep**: new top-level `data/README.md` (the
  three-layer raw→ingest→database→derived pattern, reproducibility
  rules, a full subfolder index table) plus 13 new per-folder
  `README.md` files for previously-undocumented `data/raw/` subfolders
  (`arcgis`, `conductivity`, `discharge`, `earthquakes`, `historical`,
  `images`, `isotopes`, `nbmg`, `ndom`, `noaa`, `phreeqc`, `usgs`,
  `wells`) -- `field`/`ndep`/`ndwr`/`loggers`/`lab` already had
  adequate `README.Rmd`/`README.md` documentation from earlier
  sessions and were left as-is rather than duplicated.
- **Real USGS earthquake catalog ingested for the first time**: pulled
  directly via the USGS FDSN Event Web Service (`webfetch`, not a
  search -- a real, cited data API), 139 events, greater Reno/Washoe
  Valley/Tahoe region, 2025-01-01 to 2026-09-25, M≥1.5. New
  `database/schema/12_earthquake_schema.R` (`Earthquake_Events`,
  pre-computed haversine distance to the Steamboat field center) +
  `scripts/ingest/ingest_earthquakes.R`, wired into `run_pipeline.R` as
  `RUN_INGEST$earthquakes`. `data/raw/earthquakes/README.md` documents
  the exact reusable query URL. Verified idempotent on a scratch copy
  before applying to the real database.
- **Real cross-checks against this catalog, both honestly reported**:
  the 3 nearest real events (M1.5-1.6, ~3-4 km, near Virginia City, May
  2025) overlap the STMGID water-level record but show **no detectable
  step-change** beyond the ~0.1-0.2 ft baseline daily noise at either
  MW10 or MW3 -- a real negative result, not omitted. **No earthquake
  in the catalog overlaps the temperature-logger deployment window at
  all** (loggers started 2026-04-14; every event within ~15 km predates
  that) -- stated plainly as a real data gap, not stretched into a
  comparison against a distant (>16 km) later event.
- **Real hourly temperature-vs-barometric-pressure test, testing the
  boiling-point-suppression ("inverse relationship") hypothesis
  directly**: at hourly, first-differenced resolution, well **A009**
  (`SBW_0002`, the hottest real logger, 62.8-77.2°C) shows a real,
  highly significant inverse coupling (r=-0.17, p<1e-10, n≈1400) --
  small effect size but directionally consistent with the mechanism.
  This flips sign from a naive **daily**-resolution test (r=+0.35,
  p=0.0045) -- explained, not just noted, as daily-averaging aliasing
  the true short-lag coupling. Fumarole **A005** (13.8-88.0°C, the
  widest range of any logger) shows **no significant coupling** at
  either resolution and no spike-vs-pressure-drop alignment -- a real,
  mixed (not uniformly positive) result across the two most
  boiling-adjacent sites.
- **STMGID MW10 vs. MW3 barometric-efficiency correlation-quality gap,
  explained**: per the user's own observation that MW10 "is not very
  well correlated" -- confirmed (MW10 diff-method R²=0.25 vs. MW3's
  R²=0.38) and traced to a real, physical, falsifiable candidate cause:
  MW10's screened interval is 480 ft (220-700 ft) vs. MW3's 100 ft
  (186-286 ft) -- a well open across 5x the interval length is more
  likely averaging more than one real hydrostratigraphic zone's
  response, adding noise to a clean single-zone barometric signal.
  Documented as a real hypothesis consistent with the data, not proven
  outright (no true nested piezometer pair exists yet to test it
  directly).
- **Real precipitation-recharge check**: the largest 2025-2026 storm
  (2025-12-25, 46.2 mm, part of a 2025-12-21 to 12-26 >110 mm system)
  produces a real, visible ~0.27 ft rise at MW10 (deep/long-screened)
  peaking on the storm date, with **no comparable signal at MW3**
  (shallow/short-screened) -- reported with the honest caveat that a
  big storm also brings a real barometric-pressure drop, so this one
  event alone cannot cleanly separate a recharge response from a
  barometric one at MW10.
- **Sorey & Colvard's original 1988 barometric hydrographs (Figures
  39-40) rendered and embedded directly** in the notebook (via
  `pdftools::pdf_convert()` on pages 96-97 of the real PDF, regenerated
  on demand rather than committing a static image, consistent with
  this project's reproducibility rule) -- read carefully alongside the
  real 2025-2026 STMGID result: the original figures show the same
  tension (a real but modest barometric coupling, easily dominated by
  a slower multi-day water-level trend), not a cleaner historical
  signal than what the current data shows.
- **New well-completion-interval / confining-layer visualization**
  (`scripts/analysis/well_completion_profile.R`,
  `plot_well_completion_profile()`) -- explicitly a completion-interval
  inventory, **not lithology**: `Well_Lithology` has only 5 rows, all
  `well_id = NULL`, tagged `confidence = ocr_heuristic_unvalidated`
  (unusable OCR garbage, confirmed directly rather than assumed from
  memory). Flags wells with a real screened interval >200 ft as
  `long_open_interval` (likely multi-zone: `21-5R`, `STMGID MW10`,
  `Cox I-1`, `83A-6`, `PW-3`). **Honest limitation stated plainly**: no
  two wells in this database currently sit close together with
  different screen depths AND a current water level, so a real
  vertical-head-difference (confining-layer) argument cannot yet be
  made from head data alone -- checked directly (STMGID MW10/MW3 are
  ~2.5 km apart at very different elevations, so their head difference
  is dominated by topography, not a shared confining layer).
- **Real, minor data-quality bug found and fixed while building the
  completion-interval plot**: well_id 149 ("Unidentified Well (NDWR
  Log 129060)") had `top_perforation`/`bottom_perforation` reversed
  (84/35 instead of 35/84) -- an OCR/parsing ordering slip, fixed
  directly in the database (a one-row, unambiguous correction, not a
  parser rewrite).
- **PHREEQC's role in this composite picture scoped, not built**: gas-
  phase equilibria (`12_run_phreeqc_gas_phase.R`) is flagged as the
  most direct conceptual link (a `GAS_PHASE` model is fundamentally a
  pressure-equilibrium calculation, physically the same mechanism
  tested against A009/A005 above) -- running a real gas-phase model
  across this project's real MSLP range for a real dissolved-gas
  sample would let PHREEQC predict the response and test it against
  the real A009 finding directly; not attempted this session (needs a
  real dissolved-gas-bearing sample identified first). A second
  possibility (SI tracking through a real before/after recharge event)
  is similarly scoped, not run -- no well currently has real chemistry
  both before and after a real precipitation event.
- **`ingest_fault_traces.R` built and wired into `run_pipeline.R`**
  (`RUN_INGEST$fault_traces`, mirrors `register_facility_areas.R`'s
  `sf::st_read()` + reproject-to-EPSG:4326 pattern, for LINESTRING
  geometry instead of polygons) -- this is the receiving end of the
  "ArcGIS out, ArcGIS back in" loop scoped in README's Leapfrog
  section; currently a safe no-op (confirmed by running it against the
  real database) since no fault shapefile has been digitized yet.
  Ready the moment the user saves a digitized fault-trace shapefile
  under `data/raw/arcgis/faults/` (Collar & Huntley 1990 Figure 1
  remains the best candidate source, per Session 30/31's notes).
- **Statistical summary table added to the notebook**, consolidating
  every test run this session (STMGID BE x2 methods, 4 logger
  temp-pressure correlations, 2 earthquake cross-checks, 1
  precipitation-response comparison) with n, r/BE, and p-value for
  each -- all reproducible directly from the notebook's own live code
  chunks against `geochem_operational.sqlite`, none hand-transcribed.
- **Full notebook rendered successfully end-to-end** (`quarto render`,
  confirmed clean, all new chunks including the on-demand PDF-page
  rendering and the completion-interval plot execute without error)
  against the real operational database. QC re-run clean (0 PHREEQC
  failures, 0 logger outliers, 1 logger without observations -- A011,
  correctly "standby" status).
- **Not done this session**: real fault traces still not digitized
  (blocked on the user's own ArcGIS work, per their stated intent to
  source lineaments from literature figure overlays next); no
  `Facies_Clusters` persistence table (flagged in Session 31, still
  not built); `data/derived/qc/` remains untracked (regenerable QC
  output, consistent with the "derived is disposable" convention).
  This session's file changes ARE committed and pushed to git (see
  commit history) -- including several previously-uncommitted files
  from Session 30/31 (`cluster_hydrochemical_facies.R`,
  `facies_depth_map.R`, `ingest_mariner_janik_1995.R`,
  `qc_temperature_vs_air.R`, `barometric_efficiency.R`,
  `ingest_barometric_pressure.R`) discovered untracked while preparing
  this commit despite earlier session notes claiming they'd been
  pushed -- swept in now rather than left stranded again.

## Session 33 (2026-09-25, continued): Facies_Clusters persistence, BE-based aquifer classification, real deviation survey/lithology, Leapfrog extension, historic figures

Implemented via an approved Plan-mode plan
(`.posit/assistant/plans/2026-09-26-2002-plan.md`). Covers a persisted
facies-clustering table + GeoPackage layer, a barometric-efficiency-
derived aquifer-type label per well, the project's first real (not
assumed-vertical) well deviation survey, a Leapfrog export extension,
two more historic comparison figures, and PHREEQC/statistics/
potentiometric-surface write-ups -- all landing in
`notebooks/07_historical_context_sorey1992.qmd`.

- **`Facies_Cluster_Runs`/`Facies_Cluster_Assignments`** (new schema,
  `database/schema/13_facies_clusters_schema.R`) persist
  `run_facies_clustering()`'s result for the first time (previously
  console-only) -- one row per run with method/k/silhouette/mclust-
  agreement metadata, one row per clustered sample per run. New
  `scripts/analysis/register_facies_clusters.R`. New
  `vw_facies_clusters_gis` view + `facies_clusters` GeoPackage layer
  (132 real points, latest run only) so cluster assignments can be
  overlaid against digitized fault traces in ArcGIS. Wired into
  `run_pipeline.R` as `RUN_ANALYSIS$facies_clusters` (opt-in). Real
  run persisted: k=4, mclust agreement 70.1%, 157 samples.
- **Aquifer type classification from real barometric efficiency**
  (`Wells.aquifer_type`/`aquifer_type_basis`,
  `database/schema/14_aquifer_classification_schema.R`,
  `classify_aquifer_type()` in `barometric_efficiency.R`). Thresholds
  grounded in this exact site's own historical BE range (White 1968:
  0.2-1.18 for confined vents at Steamboat), not an arbitrary generic
  cutoff -- BE >= 0.2 (diff-method, p<0.05) -> "confined"; <0.1 ->
  "unconfined"; 0.1-0.2 -> "semi-confined_leaky"; not significant ->
  "unknown" (never guessed). Applied project-wide (every well with
  real BE evidence, not just the 2 Steamboat-field wells): **7 wells
  classified "confined"**, including both real Steamboat-field wells
  (STMGID MW10, MW3). Wired into `run_pipeline.R` as
  `RUN_ANALYSIS$aquifer_classification` (opt-in).
- **First real (non-assumed-vertical) well deviation survey**: a
  project-wide keyword search of all 65 `Well_Log_Documents` OCR
  texts (`DEVIATION`/`AZIMUTH`/`INCLINATION`/`DIRECTIONAL`/`DOGLEG`)
  confirmed, again, zero real hits -- NDWR public driller's reports
  genuinely never carry directional data for this field. Real data
  instead came from literature: the user added (then, after
  confirming the pipeline had already handled it correctly, deleted)
  a `docs/literature/well_logs/` folder -- 12 of 14 files turned out
  to be exact-duplicate NDWR PDFs already ingested; the other 2 were
  not well logs at all. One (`1033641.pdf`) was an exact duplicate of
  an already-known literature PDF. The other, **`1034459.pdf`**
  (Akerley et al. 2021, GRC Transactions Vol. 45, "Drilling Challenge
  and Pumping Innovations for the Steamboat Hills Enhancement"), was
  genuinely new and turned out to describe a real directional well --
  **83C-6ST1** (well_id 98, total depth 3000 ft, an exact match to
  this project's on-record depth): vertical to a ~1600 ft kick-off
  point, then built toward the NE at up to 4.75°/100ft, intersecting a
  target fracture at 2687 ft MD before reaching 3000 ft TD. New
  `Well_Deviation_Surveys` table
  (`database/schema/15_well_deviation_surveys_schema.R`, self-seeding
  4 real rows for 83C-6ST1 on schema load) -- 2 rows are real, precise
  `surveyed_station`s (vertical 0-1600 ft); 2 are `narrative_derived`
  with `azimuth_deg`/`inclination_deg` deliberately left `NULL`
  (the paper gives the target fracture's own orientation and a build
  *rate*, not the wellbore's own station-by-station survey -- computing
  a specific final inclination would fabricate precision the source
  doesn't support). Real lithology for the same well also added to
  `Well_Lithology`: Gardnerville formation grading into schist/
  conglomerate/quartzite (whole-hole generalization, flagged as such)
  plus a precisely-bounded 1960-2031 ft swelling-clay interval that
  caused real drilling problems -- the file the citation came from was
  deleted by the user after the excerpt needed was already captured in
  conversation; only what was already read could be transcribed
  (flagged to the user as a real limitation, not silently worked
  around). **`docs/literature/well_logs/` folder deleted by the user**
  after this was extracted -- confirmed nothing else of value was lost
  (the 12 well-log duplicates were already ingested; `1033641.pdf` is
  still on file at the top level of `docs/literature/`).
- **A second, real lithology find deliberately NOT promoted to a named
  well**: re-reading well-log `61248` (rather than trusting its
  original OCR-heuristic parse) found a genuinely legible lithologic
  table (basaltic andesite 0-72 ft, metamorphosed volcanic rock 72-125
  ft, metamorphosed sedimentary rock 125-3001 ft) with strong
  circumstantial evidence it's well **23-5** (coordinates ~160 m apart,
  an exact 3001 ft total-depth match, owner "Phillips Petroleum Co." --
  a documented historic pre-Ormat operator) -- stored in
  `Well_Lithology` with `well_id = NULL` and a flag for human
  confirmation, per this project's standing rule against guessing an
  identity from circumstantial evidence alone. Promoting it would set
  `well_id = 96`.
- **A related lead checked and self-corrected in the same session**:
  well-log `104216` (owner "N.D.O.T.") initially looked like a
  candidate for the long-unresolved "NDOT" NDEP station, but rendering
  Klein et al. (2007) Figure 1 directly confirmed the real NDOT sits
  ~2.5 km north of this log's coordinate, in the Herz/Curti/Soccer
  Field cluster -- so it's a different, real N.D.O.T.-owned well.
  Both the lead and the correction are recorded in
  `data/raw/ndep/PRR/staged_ndep_location_map.csv`'s notes for the
  `NDOT` row.
- **`scripts/leapfrog/export_leapfrog.R` extended**: `survey.csv` now
  checks `Well_Deviation_Surveys` first per well, falling back to the
  assumed-vertical two-point trace only when no real survey exists
  (109 of 110 collar-ready wells still fall back; 83C-6ST1 is the one
  real exception). New `lithology.csv` output includes only
  `well_id`-confirmed `Well_Lithology` rows (candidate/pending rows
  like log 61248's correctly excluded). Verified end-to-end against
  the real database: 110 collar-ready, 95 incomplete, 222 survey rows,
  2 real lithology intervals, 74 completion intervals.
- **Two more historic comparison figures** rendered on demand into
  `output/figures/literature_reference/` (disposable/regenerable, like
  the Sorey Figures 39-40 from the prior session): **Klein et al.
  (2007) Figure 1** (labeled production/injection/monitor-well map
  with the sinter-deposit extent -- independently confirms several
  already-resolved names: NDOT, STMGID 3/4, Zolezzi, Peigh, Mackay,
  Stuart, Johnson/Woods, ST-1/2/4/5) and **White (1968) Plate 1**
  (generalized geologic map -- sinter/alluvium/basaltic-andesite/
  granitic-metamorphic units, mapped faults, GS-1 through GS-8 drill
  holes) -- both embedded directly in `notebooks/07_historical_context_sorey1992.qmd`.
- **New "known issue" tracking, not fixed**: the user noticed some
  GeoPackage well coordinates don't exactly match satellite imagery.
  No automated fix attempted (pixel-level satellite matching is out of
  scope) -- new `data/derived/well_coordinate_review.csv` scaffold +
  a README.md note under "GIS Export and Spatial Integration" for
  logging confirmed mismatches by hand as they're found.
- **New notebook sections, all rendered and verified**: PHREEQC
  next-steps table (5 real directions, each with what real data is
  still missing to run it), a potentiometric-surface-mapping
  feasibility + software recommendation (checked real coverage
  directly: only 2-3 wells inside the field itself have usable water
  level, vs. 21 in the wider-but-different South Truckee Meadows
  basin; recommended ArcGIS Pro Geostatistical Analyst/EBK as primary,
  with an R `gstat` cross-check and QGIS as a free alternative; noted
  Leapfrog would inform *which wells get kriged together*, not the 2D
  interpolation itself), and a master statistics-summary table
  consolidating every real test run anywhere in the notebook.
- **Full notebook rendered successfully end-to-end** (`quarto render`,
  confirmed clean) against the real operational database, including
  all new chunks (facies persistence, aquifer classification,
  deviation survey, lithology, both new historic figures,
  potentiometric coverage query). `scripts/pipeline_report.Rmd`
  extended with the 4 new tables and test-rendered cleanly.
  `qc_data_integrity_checks.R` re-run clean (0 PHREEQC failures, 0
  logger outliers). GeoPackage re-exported cleanly (`facies_clusters`
  layer confirmed, 132 rows).
- **Not done this session**: real fault traces still not digitized
  (unchanged, blocked on the user's ArcGIS work); the deeper
  production/injection/monitor wells' water levels are still not on
  file (Session 4's NDEP request remains the concrete blocker for any
  real potentiometric surface); no gas-phase-vs-pressure PHREEQC run
  attempted (needs a real dissolved-gas sample first, per the
  next-steps table). This session's file changes are committed and
  pushed to git (see commit history).

## Session 34 (2026-09-25, continued): well-log 23-5 promotion, statistical
synthesis notebook, documentation/console-UX polish, notebooks consolidated
into one PDF

Large multi-part follow-up covering a real database promotion, a new
cross-cutting statistics notebook, a documentation sweep across
previously-undocumented script folders, console UX (a printed flag
reference table + a README console-command cheat sheet), and stitching
all 8 living-reference notebooks + the annotated bibliography into one
combined PDF -- the last of which surfaced and fixed several real,
previously-latent structural bugs.

- **Well-log 61248 promoted to well 23-5**, per explicit user
  instruction (the circumstantial-evidence match flagged for review
  since Session 33: coordinate ~160 m match, exact 3001 ft
  total-depth match, owner 'Phillips Petroleum Co.' -- a documented
  historic pre-Ormat operator). Added to
  `data/raw/ndwr/well_log_document_map.csv`, ran
  `promote_well_log_documents(con)` (fills `Wells` fields only when
  currently `NULL`), then manually set the 3 `Well_Lithology` rows
  sourced from this document to `well_id=96`. **Real merge bug found
  and fixed while doing this**: `promote_well_log_documents()` only
  fills `Well_Log_Documents.well_id` when it is currently `NULL` --
  but this document already had a NON-NULL `well_id` (182, a
  provisional 'Unidentified Well (NDWR Log 61248)' row created by an
  earlier session's `register_provisional_well_logs()`), so the
  promotion silently kept pointing at the wrong (provisional) well
  instead of the newly-confirmed 23-5. Fixed by directly merging the
  now-redundant provisional well_id 182 into canonical well_id 96
  (repointed its one `Well_Work_Events` row, updated
  `Well_Log_Documents.well_id`/`match_method`, deleted the empty
  provisional `Wells` row) -- verified clean on a scratch copy first,
  then applied identically to the real, backed-up
  `geochem_operational.sqlite` (backup:
  `geochem_operational_pre_23-5_promotion_<timestamp>.sqlite`). QC
  re-ran clean afterward. This is a real, generalizable gap worth
  remembering: any future well-log promotion needs to check for and
  merge a pre-existing provisional well_id, not assume `well_id` is
  `NULL` just because a document was never manually promoted before.
- **New action-items document**: `docs/action_items_for_user.md` --
  NDEP data requests (what/why/blocking-what), the fault-digitization
  reminder (Collar & Huntley 1990 Figure 1, save target
  `data/raw/arcgis/faults/`), unresolved well-identity confirmations
  pending user judgment, the water-level-data gap stated plainly, and
  confirmation that git status was clean and `docs/literature/` stays
  permanently gitignored per this session's explicit instruction (not
  just 'still open' as several earlier session notes had implied).
- **New notebook**: `notebooks/08_statistical_synthesis.qmd` --
  equations paired with the exact production code that implements
  each (charge balance, SI, mixing fraction, Cl mass-balance
  discharge, Na/K geothermometers, D'Amore-Panichi gas
  geothermometer, barometric efficiency, the boron-exclusion guard);
  real PHREEQC SI/charge-balance-error distribution analysis (sentinel
  `-999.999`/`+/-100` values identified and excluded, Shapiro-Wilk
  testing, `fitdistrplus` AIC model comparison against logistic/
  Cauchy alternatives, bootstrap 95% CIs on the small n=7-8 real
  thermal-sample means); new cross-cutting methods not used elsewhere
  in the project -- Kruskal-Wallis + pairwise Wilcoxon on Cl by site
  type, a significance-tested Pearson correlation matrix
  (`Hmisc::rcorr`) on major ions, a PCA biplot colored by the
  persisted facies clusters, a population-level (not
  facies-restricted) `lme4::lmer` mixed-effects Cl-vs-year trend
  across all 157 clustered samples (complementing, not replacing,
  `07`'s facies-restricted `glmmTMB` model), and an exploratory
  `gstat` semivariogram on all real geolocated Cl samples (explicitly
  caveated as all-time-pooled, not synoptic, so not yet a kriging-
  ready result). New packages installed: `fitdistrplus`, `Hmisc`,
  `gstat` (`boot`, `lme4`, `corrplot` were already present). Rendered
  successfully end-to-end against the real operational database.
- **Documentation sweep**: new `scripts/README.md` (top-level folder
  index) plus new per-folder READMEs for every previously-
  undocumented `scripts/` subfolder (`analysis/`, `phreeqc/`,
  `documentation/`, `templates/`, `leapfrog/`) and a new
  `database/schema/README.md` (one row per numbered schema file,
  01-15, plus the two `*_map.R` files). **Found and fixed real
  documentation staleness**: `scripts/ingest/README.Rmd`/`.md` and
  `scripts/qc/README.md` still only documented 3-4 scripts each from
  an early project phase, missing essentially all ~24 sources/checks
  added across Sessions 3-33 -- both substantially rewritten with a
  full per-script table (reads/writes/notes), re-knit via
  `rmarkdown::render(..., output_format='github_document')` for the
  `.Rmd`-backed one.
- **Console UX**: `run_pipeline.R` gained `print_pipeline_help()`,
  called automatically right after `RUN_INGEST`/`RUN_ANALYSIS` are
  finalized -- prints every flag's name, current value, and a
  one-line description, so a user can `source('scripts/run_pipeline.R')`
  and immediately see what a run will/won't do without opening the
  script. Verified the existing PIPELINE SUMMARY table already covers
  every newer stage (facies clusters, aquifer classification,
  earthquakes, fault traces, Leapfrog export) since they all go
  through the shared `run_step()`/`.log_stage()` wrapper -- no gap
  found there. README.md gained a new 'Quick Console Commands for
  Common Tasks' section with copy-pasteable snippets for every
  routine workflow (full/chemistry-only/skip-ingestion profiles,
  PHREEQC-only, real mixing/inverse/gas-phase config runs, GeoPackage-
  only export, Leapfrog-only export, single/all-notebook rendering,
  website-only rebuild, QC-only).
- **Notebooks consolidated into one PDF**: new
  `notebooks/00_full_report.qmd`, transcluding `01`-`08` plus the
  annotated bibliography via `{{< include >}}`, front matter linking
  the GitHub repo and live website, and a Key Figures appendix.
  Renders to a real 225-page, ~13 MB PDF
  (`output/reports/notebooks/00_full_report.pdf`) via TinyTeX/
  LuaLaTeX (confirmed already installed in this environment). Getting
  there required real debugging, not just assembly, and surfaced
  several genuine, previously-latent bugs in the individual notebooks
  themselves (all fixed at the source, and re-verified standalone
  after fixing):
  1. **Duplicate knitr chunk labels across files** (`setup`/`cleanup`/
     `load`/`connect`, each independently reused by 2-7 of the 8
     notebooks) -- knitr requires document-wide-unique labels once
     `{{< include >}}` flattens everything into one document; fixed
     by renaming the ~11 colliding labels to be file-suffixed
     (`setup-01`, `connect-02`, etc.) directly in
     `01`/`02`/`03`/`05`/`06`/`07`/`08`. `options(knitr.duplicate.label
     = 'allow')` does NOT help here (that only applies to
     `knit_child()`-based inclusion, not raw-text `{{< include >}}`,
     which knitr sees as genuinely one file at parse time, before any
     chunk executes).
  2. **Root-directory pinning compounds across chapters.**
     `01`/`02`/`03` each unconditionally computed
     `root.dir = normalizePath(file.path(getwd(), '..'))` in their own
     setup chunk -- correct in isolation (cwd starts at `notebooks/`),
     but since `opts_knit\$set(root.dir=...)` persists globally across
     ALL subsequent chunks in a merged document, chapter 2's setup ran
     with cwd already pinned to the project root by chapter 1, so its
     own `'..'` climbed one level too far (landing one directory
     above the real project root) -- broke every relative `db_path` in
     chapters 2 onward. Fixed by wrapping all three in
     `if (basename(getwd()) == 'notebooks') { ... }`, mirroring the
     guard `06` already had (Session 18). `04`'s two hardcoded
     `'..'`-prefixed paths (for `source()` and `db_path`) had the
     same underlying problem and were rewritten to the
     file.exists()-based fallback pattern `05`/`07` already used.
  3. **`knitr::include_graphics()` mishandles a path when `root.dir`
     is pinned**, even an absolute one -- it recomputes the path
     relative to the ORIGINAL document directory (`notebooks/`) for
     the rendered output, and that recomputation is what actually
     failed ('Cannot find the file(s): ../output/figures/...'), not
     the caller's own `file.exists()` check (which had already passed
     on the correct absolute path). This broke the 4 on-demand
     literature-figure embeds in `07` (Sorey Figs. 39-40, Klein
     2007 Fig. 1, White 1968 Plate 1) only in the combined-document
     context -- each rendered fine standalone, where `root.dir` is
     never pinned to begin with. Fixed by bypassing
     `include_graphics()` entirely for these 4 chunks: emit a raw
     markdown image tag directly via
     `knitr::asis_output(sprintf('![...](%s)', path))` (with
     `#| results: asis` on each chunk) using a path built fresh from
     `normalizePath(getwd())` at execution time -- immune to knitr's
     internal path-rewriting since it never touches
     `include_graphics()`'s special-cased logic.
  4. **Stale `_freeze/` caches masked source fixes** mid-debugging --
     `_freeze/07_historical_context_sorey1992` (dated Sep 12, i.e.
     from that notebook's last STANDALONE render) was silently reused
     for the SAME chunks when transcluded into the new combined
     document, even after editing the source and even after deleting
     `_freeze/00_full_report` specifically -- quarto's freeze cache is
     keyed by the underlying source file's own identity, not just the
     outer including document. Had to `rm -rf _freeze` (all of it, not
     just the master document's own slot) before a source edit would
     actually take effect in a combined-doc render. Worth remembering
     for ANY future edit-then-re-render cycle on a document that
     transcludes other, independently-frozen `.qmd` files.
  5. **Pandoc/quarto metadata merging across transcluded files is
     last-wins**, which silently overwrote this document's own
     `title`/`subtitle`/`author` YAML with whichever chapter's own
     front matter was processed last (first the bibliography's, then
     -- after that file was excluded from the merge, see below --
     notebook `08`'s). `title-block-style: none` did NOT suppress the
     resulting stray auto-title page; a `pandoc-args`/`-M` metadata
     override was ALSO tried and did not take effect (order of
     precedence between YAML-block metadata and `-M` flags did not
     work the way expected). **Two real fixes landed, one workaround
     accepted**: (a) the annotated-bibliography chapter -- the file
     most directly under this project's own control -- is no longer
     transcluded via `{{< include >}}` at all; a chunk now reads it
     with `readLines()`, strips everything up to and including its
     second `---` line (its YAML block), and emits the rest via
     `knitr::asis_output()`, so it can never contribute frontmatter to
     the merge; (b) an explicit, correct title block was added directly
     in this document's own body (a LaTeX `titlepage` environment for
     PDF + a plain `# ...` heading for HTML/other formats) so the
     INTENDED title always appears correctly on what is now page 2;
     (c) the underlying stray page 1 (now carrying notebook `08`'s
     title, since the bibliography no longer contributes) was NOT
     further chased -- a full fix would need the same YAML-stripping
     treatment applied to all 8 transcluded notebooks, which was
     judged not worth the additional multi-file edit risk for a purely
     cosmetic, one-extra-page issue. Documented in
     `00_full_report.qmd`'s own body as a known limitation for future
     editors, including an explicit warning about the next bullet.
  6. **`pdftools::pdf_subset()` corrupted the rendered PDF** when
     tried as a quick way to drop the stray page 1 -- silently reduced
     it from a real 13 MB, 225-page file to a broken 190 KB one full of
     'Unknown compression method in flate stream' errors (a real
     poppler/pdftools incompatibility with this specific lualatex
     output, not a usage mistake). Caught immediately by re-checking
     file size/page text after the 'fix,' reverted by re-rendering from
     source rather than attempting to repair the corrupted file. **Do
     not use `pdf_subset()` on this project's rendered PDF output
     without first confirming it round-trips cleanly on a throwaway
     copy.**
- Standalone rendering of every edited notebook (`01`, `04`, `07`
  spot-checked directly; `02`/`03`/`05`/`06`/`08` share the same fix
  patterns) was re-verified working correctly after all of the above
  -- none of the combined-document fixes broke independent use.
- Cleaned up incidental artifacts from this session's many render
  attempts (`phreeqc.log` at the repo root, an accidental
  `scripts/ingest/README.html` from re-knitting the `.Rmd`) before
  committing.
- **Not done this session**: the DEMO database was not rebuilt with
  the well-log-23-5 promotion; the stray PDF title-page cosmetic issue
  (above) remains unresolved by design (documented, not silently
  worked around further); `data/derived/qc/` remains untracked
  (disposable/regenerable QC output, consistent with existing
  convention).

## Session 35 (2026-09-25/26, continued): real well-log transcriptions, Boyd Domestic Well link, outreach docs, sampling proposal, Sorey (2000) elevated

Follow-up to Session 34, covering real user-transcribed well-log data
for 5 NDWR logs (one with an attached lithology-table image), continued
human-confirmed well mapping from published figures, two new outreach
documents, a calibration-sampling cost-benefit mini-proposal, and
elevating Sorey (2000) to a critical reference.

- **New, broader well-log manual-transcription tooling**:
  `apply_well_log_manual_transcriptions()` (a sibling of Session 34's
  water-level-only override) reads
  `data/raw/ndwr/well_log_manual_transcriptions.csv` (total depth,
  hole/casing diameter, cased-to depth, perforation interval, static
  AND pumping water level, lat/lon corrections, free-text notes for
  first-water depth/max temperature) and
  `well_log_lithology_manual.csv` (mirrors Well_Lithology's own
  schema) -- a human-transcribed value from directly reading a scan
  always overwrites whatever OCR did or didn't produce, logged either
  way. Water_Level_Observations gets a NEW `method='driller_report_pumping'`
  row for pumping-level readings (no schema change needed --
  `method`/`method_type` are free text, no CHECK constraint). Wired
  into `run_pipeline.R` right after the Session 34 override call.
- **Real transcribed data applied to the real database** for logs
  5711 (48 ft, 8"/6" hole/casing, static WL 10 ft, first water 30 ft,
  lithology 0-10 black sandy loam/10-40 fine sand/40-48 coarse sand),
  5731 (300 ft, static WL taken as 26 ft [first water, no separate
  static value given], chief aquifer 120-180 ft, reported temperature
  up to 360 deg F/~182 C, full 8-interval lithology from the user's
  attached 'Log of Formations' image), 8188 (56 ft, perf 32-52 ft,
  static WL 19 ft), 8771 (cased to 90 ft, perf 55-84 ft, static WL
  8 ft, pumping WL 68 ft), and 21796 (300 ft, static AND pumping WL
  both reported as 215 ft -- recorded as-given, flagged not assumed
  to be a slip). 16 Well_Log_Documents field updates, 5
  Water_Level_Observations rows, 11 Well_Lithology intervals; verified
  on a scratch copy first, then applied to the real, backed-up
  `geochem_operational.sqlite` (backup:
  `geochem_operational_pre_well_log_transcriptions_<timestamp>.sqlite`).
  21796's water-level rows were skipped (garbled OCR completion date,
  same `.safe_completion_date()` guard as always) -- the raw values are
  still recorded on `Well_Log_Documents`/notes.
- **Real identity resolved, and a genuine mistake caught mid-session**:
  log 8188 is `Boyd Domestic Well`. Initially misidentified this as a
  `Wells.well_id=151` "merge" case (mirroring the 61248->23-5 pattern
  from Session 34) based on a garbled recollection of an earlier bash
  query's two-query output -- re-checking directly found `Wells.well_id=151`
  is actually an unrelated `Unidentified Well (NDWR Log 138974)`, and
  "Boyd Domestic Well" is really `Locations.location_id=151` (already
  sourced from this exact log per Session 4/5's own notes -- coordinate
  39.38325/-119.73992 vs. this document's 39.38325/-119.74, and owner
  cross-reference "BOYD, VERNON D"). Fixed correctly by *linking* (not
  merging) -- `Wells.well_id=186` (the provisional well created from
  log 8188's OCR/crossref data) got `location_id=151` and
  `well_name='Boyd Domestic Well'` via a plain `UPDATE`, confirmed no
  other well already claimed that `location_id`. A real reminder that
  `Wells` and `Locations` are different ID spaces and a coincidentally-
  matching integer from an earlier query needs re-verifying before
  acting on it, not just recalling from context.
- **8188/8771's coordinates needed no correction** -- the user's own
  independent re-derivation of "-119.74" for both (after doubting an
  implausible-looking value on the original 1960s scan) matches what
  was already on file from the NDWR cross-reference for each.
- **Continued human-confirmed well mapping from Klein (2007)/White
  (1968)'s already-rendered figures** (read directly via the image
  tool, not from memory): both are schematic maps with a scale bar and
  north arrow but no coordinate grid, so **no new coordinates were
  written** -- reading a position off a flat scan without a real
  georeferencing tool would be a visual guess, against this project's
  standing rule. Real outcomes anyway: a genuinely new historic name
  spotted on White (1968) Plate 1 ("Steamboat Resort," adjacent to
  "Steamboat wells"/"Steamboat Cold Spring" -- distinct from the
  user's own SBW_0001/0002 sample series, which the user confirmed IS
  what "resort well" meant for the sampling-proposal work below);
  visual confirmation (not new resolution) that PTR#1, Trans Sierra
  #3/#4, Johnson/Woods, Flame, Mackay Geoth/Geoth B/Dom, Stuart Dom,
  Peigh Pool New/Peigh Pool/Peigh Dom, STMGID 3/4, ST-1/2/4/5, and
  several named springs are all real, clearly labeled, and spatially
  clustered near the already-resolved Herz/Curti/Soccer Field/NDOT
  group. Documented in `notebooks/07` with the concrete recommended
  next step: georeference these two scans directly in ArcGIS using
  already-known-coordinate wells as control points (the same "ArcGIS
  out, ArcGIS back in" workflow already scoped for fault digitizing).
- **New outreach documents**: `docs/outreach/ndep_data_request.qmd`
  and `ormat_data_request.qmd` (+ rendered PDFs) -- real, ready-to-send
  letters reusing content already assembled in
  `docs/action_items_for_user.md` and Session 4's drafted-email notes.
  NDEP's asks are chemistry/water-level/location-focused (the standing
  monitoring-network requests); Ormat's are well-identity/location-
  focused (the still-unmatched Dhakal-network wells, their own
  production/injection/monitor well water levels, and fissure-site
  access) -- deliberately different content per party, not a shared
  template.
- **New `manuscript/06_calibration_sampling_proposal.qmd`** -- a
  decision-facing mini-proposal, deliberately separate from
  `notebooks/09`'s raw statistics per explicit user request: a reasoned
  (not power-analysis-computed, since no real Cl-EC paired data exists
  yet to compute one against) n=15-20 minimum / n=30-40
  seasonally-defensible calibration-sample-count target; real
  discussion of pairing Cl with major ions (mixing-model cross-check,
  already used in `notebooks/06`) and isotopes (the only way to
  distinguish evaporation from conservative mixing); cost/benefit of
  adding the active fissure (Ormat-access-gated) and SBW_0001/0002 (the
  "resort" wells, already known/sampled, low incremental cost) as
  sites; a tiered 20/40/60+ total-analyses-per-year table with an
  explicit Tier-2 (~40) recommendation as the realistic one-person-
  thesis target.
- **Sorey (2000) elevated to a critical reference**, not just a
  bibliography entry: a `callout-important` added directly above its
  `docs/literature/annotated_bibliography.qmd` entry, and a new,
  substantive discussion paragraph added to
  `notebooks/07_historical_context_sorey1992.qmd`'s discharge-through-
  time section framing its real 2000 finding (spring flow had not
  resumed even after the groundwater-decline driver partly blamed for
  its cessation had itself reversed) as the direct historical baseline
  for asking whether the 2025 eruption is a genuine reawakening of the
  *same* system or a mechanistically different event -- tied explicitly
  to this project's own poster conclusion (conduit reactivation, not a
  new source).
- **Verified**: `ingest_well_logs.R`/`run_pipeline.R` still parse and
  have no CRLF corruption; `notebooks/06`/`07` and
  `manuscript/06_calibration_sampling_proposal.qmd` all re-render
  cleanly standalone after these edits; QC re-run clean on the real
  database (0 new PHREEQC failures introduced by this session's
  changes).
- **Committed and pushed** to `origin/main` (commit `22b8ff5`) --
  includes this session's work plus Session 34's still-uncommitted
  `ROADMAP.md`/`manuscript/` skeleton/`notebooks/09`/well-log-override
  tooling, all in one batch. The three new well-log CSVs under
  `data/raw/ndwr/` needed the usual `git add -f` treatment (gitignored
  directory).
- **Not done this session**: no new coordinates were added for any of
  the still-unresolved named wells (PTR#1, Trans Sierra #3/#4, etc.) --
  genuinely blocked on a real georeferencing step, not attempted as a
  guess; the DEMO database was not rebuilt with any of this session's
  changes; `manuscript/01`/`04`/`05` remain stubs/partial drafts as
  explicitly scoped in Session 34.

## Session 36 (2026-09-27): DEMO database finally rebuilt end-to-end; five real pipeline-crashing bugs found and fixed; k-means facies cross-check; website notebooks/qc_summary fixes; proximity audit

Closed out the "DEMO database has never actually been rebuilt" gap
flagged across dozens of prior sessions, plus four other independent
follow-ups from the same request. Full plan at
`.posit/assistant/plans/2026-09-27-2040-plan.md`.

- **DEMO database (`geochem_demo.sqlite`) rebuilt completely for the
  first time**, exercising every schema addition (well-network,
  PHREEQC, facies-clustering, NDOM/Skalbeck, earthquakes, fault
  traces, aquifer classification, Leapfrog export) via profile-1
  `RUN_INGEST` + `RUN_ANALYSIS` flags. **Five real, previously-latent
  bugs were found and fixed** -- this is almost certainly why the
  DEMO rebuild had silently never completed before, not just time
  pressure:
  1. `database/schema/15_well_deviation_surveys_schema.R`'s hardcoded
     `well_id=98` seed INSERT crashed outright (`FOREIGN KEY
     constraint failed`) the moment `Wells` is genuinely empty (a
     freshly-reset/never-built DEMO database) -- fixed to check
     well-existence first and skip gracefully with a message.
  2. `scripts/ingest/helpers/align_timeseries.R`'s rolling join
     crashed (`stopifnot(inherits(..., "POSIXct"))`) on a zero-row
     result (e.g. a station with no overlapping USGS coverage --
     common on DEMO's smaller real dataset) -- fixed to return a
     well-typed empty result instead.
  3. `scripts/analysis/calc_gradients.R`'s `st_as_sf()` crashed
     ("missing values in coordinates not allowed") the moment any
     `vw_hydraulic_head_clean` row lacks a coordinate (a provisional
     Wells row from the well-log/NDOM paths) -- fixed to drop those
     rows first, with a message.
  4. Three bare dplyr generics (`lag()` in `qc_conductivity_checks.R`,
     `first()` x2 in `extract_ndep_samples.R`, `count()` in
     `ingest_field.R`) broke under a `conflicted`-package session
     (loaded transitively by `tidymodels`, which this project's own
     sampling-frequency workstream uses) -- fixed by qualifying all
     four `dplyr::`. Worth remembering: this class of bug is
     session-dependent (only bites when `conflicted` happens to be
     loaded), so it can look intermittent.
  5. `run_pipeline.R`'s `.interp_zero_crossing()` helper (geothermometer
     website export) crashed (`seq_len(-1)`) on a single-row
     `PHREEQC_Temp_Sweep` group -- fixed with a `length(temps) < 2`
     guard.
  A sixth failure (`SKALBECK (2001) HYDROGEOLOGIC DISSERTATION:
  cannot open the connection`, and the resulting `LEAPFROG WELL
  EXPORT: no such column: surface_elevation_m` knock-on) turned out
  to be a **transient** issue (network/file-lock blip during a
  heavy-ingestion moment) -- confirmed by manually re-running
  `fetch_skalbeck2001_point_elevations(con)` and the Leapfrog export
  functions directly against the live DEMO connection, both succeeded
  immediately on retry with no code change needed.
  Final verified counts (DEMO): 264 Wells, 64 Well_Log_Documents, 911
  PHREEQC_Solutions/8289 PHREEQC_Results, 157 Facies_Cluster_Assignments
  (k=4, kmeans-vs-hc agreement 98.1%), 49 NDOM_Well_Records, 241
  Geophysical_Depth_Model_Points (all with real USGS-3DEP elevation),
  17-layer GeoPackage export clean, full Leapfrog CSV set. Total
  runtime ~19 min (dominated by ~14 min of well-log OCR, matching the
  historical estimate). Not committed (gitignored `.sqlite`).
- **k-means added as a third, independent facies-clustering
  cross-check**, alongside the existing hierarchical (Ward)/mclust
  pair -- `scripts/analysis/cluster_hydrochemical_facies.R` (same
  scaled/log-transformed matrix, same silhouette-selected k, `nstart
  = 25`), `register_facies_clusters.R` and
  `database/schema/13_facies_clusters_schema.R` (additive migration:
  `Facies_Cluster_Runs.kmeans_agreement_pct_hc`/
  `_mclust`, `Facies_Cluster_Assignments.facies_cluster_kmeans`),
  `build_facies_diagnostic_plots.R`'s `plot_facies_agreement_heatmap()`
  (now a faceted 3-way pairwise comparison when k-means data is
  present, falls back to the original 2-way plot otherwise). Real
  result against the operational database: hierarchical-vs-mclust
  70.1%, hierarchical-vs-kmeans 98.1%, mclust-vs-kmeans 77.7% (k=4,
  n=157) -- k-means and Ward hierarchical agree closely, both diverge
  from mclust's Gaussian-mixture assumption similarly. Registered as
  a new real run (`run_id=33` on the operational DB) with notes.
- **`docs/notebooks/*.html` broken-link gap fixed**: website pages
  (`project.Rmd`, `references.Rmd`, `results.Rmd`) have linked to
  `notebooks/<name>.html` since they were added, but nothing ever
  copied the real rendered notebook HTML
  (`output/reports/notebooks/`, gitignored) into `docs/notebooks/` --
  confirmed via a real, protected `build_website()` run that these
  links were 404ing. New `copy_notebook_html_to_docs()` in
  `run_pipeline.R`, called from inside `build_website()` right after
  the existing `docs/literature/` restore, every time (not just once)
  -- same root cause class (`render_site()` deletes anything under
  `docs/` with no counterpart in `website/`'s own input tree).
  `docs/notebooks/` committed to git for the first time (11 HTML + 2
  PDF files).
- **`docs/data/qc_summary.csv`'s render_site()-survival gap fixed**
  (flagged since Session 12, never closed): `qc_data_integrity_checks.R`
  now writes to a stable `data/derived/qc/qc_summary.csv` instead of
  directly into `docs/data/`; `export_website_data_files()` copies it
  into `docs/data/qc_summary.csv` on both of its existing before/after
  `build_website()` call sites, exactly matching every other website
  CSV's protection.
- **New systematic coordinate-proximity audit**:
  `scripts/qc/qc_location_proximity.R` /
  `qc_location_proximity(con, threshold_m = 200)` -- generalizes the
  one-off SBRR/SB5/SB6/STBT02Steamboat-2a discovery (which produced
  the `Location_Aliases` table) into a standing report. Scans
  `Locations` pairwise (covers every Conductivity_Loggers/
  Temperature_Loggers point too, since neither table has its own
  coordinate -- both resolve only via `location_id`) plus a separate
  `Wells`-vs-`Locations` pass (`Wells` has its own independent
  coordinate). Excludes pairs already resolved in `Location_Aliases`.
  Wired into `run_pipeline.R` unconditionally, right after
  `register_location_aliases(con)`. Writes
  `data/derived/location_proximity_candidates.csv`, never
  auto-matches. **Real result this session (against the operational
  database, 200 m threshold)**: 892 candidate pairs, but essentially
  all of them trace to three already-understood, deliberate,
  non-confusion patterns, not new SBRR-style duplicates: (1) ~41
  exact-0m pairs are historical-chemistry-ingestion `Locations` rows
  (`SOREY1992_*`/`MJ1995_*`/`KLEIN_*`/Skalbeck-sourced, no
  `external_station_code`) deliberately coordinate-copied from an
  existing `Wells` row to attach old chemistry to a location record
  -- by design, documented in each row's own `notes`; (2) real,
  intentionally-paired NDWR shallow/deep monitoring wells 1-3 m apart
  (e.g. "4th Street Deep MW"/"4th Street Shallow MW") -- a real
  hydrogeological pattern, not a data error; (3) closely-spaced
  `SBO_000xx` field-observation/photo points (sub-meter to a few
  meters apart) -- legitimately dense, not duplicates. **No new
  alias rows were added** -- nothing found rose to the SBRR level of
  "two independently-sourced records for the literal same real-world
  monitoring point," so nothing was proposed to the user for
  confirmation this round. Re-runnable any time real new data sources
  are added.
- **Real, unrelated data-loss incident caused and fully recovered
  this session**: while testing the notebook/qc_summary fixes, a
  bare `rmarkdown::render_site("website")` call (made before the
  `build_website()` wrapper's protections were re-verified in this
  session) deleted **47 tracked `docs/` files** it has no protection
  for (`docs/site_libs/` -- leaflet/plotly/crosstalk JS bundles,
  several `docs/figures/*.png`, `docs/outreach/*.pdf/.qmd`,
  `docs/action_items_for_user.md`, several `*_files/figure-html/*.png`)
  -- the same root-cause class as the Session 13 literature incident,
  just hitting files that were never given the same backup/restore
  treatment (only `docs/literature/`, and now `docs/data/`/
  `docs/notebooks/`/`docs/figures/data_availability_timeline.png`,
  are protected). **Fully recovered via `git checkout --` against
  each file's last-committed version** (all were tracked, unlike the
  gitignored `docs/literature/` in the 2013 incident) -- confirmed
  zero content loss. **Standing lesson reinforced**: never call
  `rmarkdown::render_site()` directly on this project outside the
  `build_website()` wrapper, even for quick testing -- it has no
  protection of its own, and more of `docs/` is vulnerable than just
  literature/data/notebooks/figures.
- Not done this session: `docs/site_libs/`, `docs/figures/*.png`
  (beyond `data_availability_timeline.png`), `docs/outreach/`, and
  `docs/action_items_for_user.md` remain **unprotected** against a
  future bare `render_site()` call -- worth generalizing
  `build_website()`'s backup/restore pattern to the whole `docs/`
  tree (backup everything under `docs/` before `render_site()`,
  restore anything render_site() didn't itself regenerate) rather
  than enumerating protected subpaths one at a time, next time this
  bites someone. Committed and pushed to `origin/main` (commit
  `f86bb1e`).

## Session 36 continued (2026-09-27): generalized docs/ backup/restore; real sample_flow/temp_flow join-correctness bug found and fixed

Direct follow-up to the two items flagged at the end of the previous
turn (generalize `build_website()`'s protection to all of `docs/`;
investigate the still-0-row `sample_flow`/`sample_flux` joins). Both
turned into real, substantive fixes, not just investigation.

- **`build_website()`'s docs/ protection generalized.** Previously
  only `docs/literature/` had a dedicated backup/restore around
  `rmarkdown::render_site()`'s cleanup. Added a second, generic
  backup covering everything under `docs/` EXCEPT `docs/literature/`
  (excluded only to avoid a redundant ~500 MB copy every call, since
  literature already has its own protection) -- backs up before
  `render_site()`, then after, restores any file that is missing but
  does NOT overwrite anything `render_site()` correctly regenerated
  fresh (a "fill the gaps" merge, not a rollback). **Verified with a
  real, live `render_site()` call** (not a synthetic test): confirmed
  it reproduced the exact same deletion pattern as the earlier
  incident (`docs/site_libs/`, several `docs/figures/*.png`,
  `docs/outreach/`, `docs/action_items_for_user.md`, several
  `*_files/figure-html/*.png`), and this time the new restore step
  caught it automatically -- `"[WEBSITE] Restored 45 file(s) under
  docs/ that render_site() removed but did not regenerate"` -- with
  zero manual `git checkout` intervention needed. Before/after file
  listing diff confirmed 0 missing files (273 before, 273 after).
- **Real, previously-undetected join-correctness bug found and fixed
  in `scripts/ingest/helpers/align_timeseries.R`'s grouped branch**
  (used by both `build_temp_flow()` and `build_sample_flow()`).
  Confirmed via a minimal reproducible example that data.table's
  rolling-join convention overwrites the "on" column named on the
  x-side (here, `right_dt`'s `right_time`) with the i-side's matched
  KEY VALUE (`left_dt`'s `left_time`) in the join output --
  `right_dt`'s real matched timestamp is not retained anywhere else
  in the result. The grouped branch only ever preserved `left_time`
  (via a `join_time` side-channel) before this fix, so `right_time` in
  every aligned row was silently just a copy of `left_time`, making
  `time_diff_min` always exactly 0 and the `max_diff_minutes` filter a
  complete no-op -- confirmed this let real 1974-2024 chemistry
  samples "match" a 2025-2026 USGS discharge reading with an apparent
  0-minute gap, and (for `temp_flow`) meant EVERY temperature-logger
  reading ever matched a USGS discharge point regardless of true time
  distance (0% of rows were ever filtered out, in every prior pipeline
  run, going back to whenever this table was first built). Also traced
  why `sample_flow` looked like a "coverage gap" rather than a bug:
  spatial/station mapping was never the problem (matches ~1200 of
  1515-1517 samples to a real nearest USGS station); the real,
  separate limitation is that USGS live discharge data only covers
  2025-01-01 through 2026-06-06 while most chemistry samples are much
  older (Sorey 1992/Mariner & Janik 1995/Skalbeck 2001/NDEP going back
  to 1974) -- only 73 samples fall inside the gauge's real coverage
  window at all, and 73 is exactly the correct post-fix row count.
  **Fix**: mirrored the already-correct ungrouped branch's pattern --
  preserve BOTH sides' real timestamps in side-channel columns
  (`join_left_time`/`join_right_time`) immune to the join's own
  column-aliasing, then restore both afterward; join `on=` now also
  includes `group_col` itself (previously the "grouped" branch never
  actually joined by group at all, only sorted by it, so a sample
  could silently match a reading from the WRONG station when two
  stations' timestamps happened to tie -- confirmed this duplicate-
  station-tie pattern directly before the fix, e.g. sample 826
  matching both `USGS-10349300` and `USGS-10349849` at an identical
  timestamp).
- **Applied and verified against both databases**: DEMO
  (`geochem_demo.sqlite`) -- `temp_flow` 193656 -> 103693 rows (real
  time filtering now removes ~46%, not 0%), `sample_flow` 826 -> 73
  rows, `sample_flux` 0 -> 54 rows. Operational
  (`geochem_operational.sqlite`, backed up first to
  `database/archive/geochem_operational_pre_align_timeseries_fix_<timestamp>.sqlite`)
  -- same corrected counts (73 `sample_flow` / 54 `sample_flux` /
  103693 `temp_flow`). GeoPackage re-exported cleanly for both (16
  layers each, `sample_flow`/`temp_flow` layers now reflect the real,
  time-correct join). QC re-run clean on the operational database
  afterward.
- **Not done this session**: `build_temp_gradient_links.R` already
  explicitly passes `group_col = NULL` (the correct, ungrouped branch)
  and was unaffected -- not re-verified beyond a code-read confirming
  this, since its own filtering behavior (204622 -> 2160 rows,
  observed in the DEMO rebuild) was already consistent with real
  filtering happening correctly. The DEMO database's `temp_flow`
  GeoPackage layer was not separately re-exported after this fix
  (the DEMO GeoPackage was already re-exported once earlier this
  session for the Skalbeck/Leapfrog fix, before this join fix existed)
  -- worth doing on the next full DEMO rebuild. This session's file
  changes (`scripts/run_pipeline.R`,
  `scripts/ingest/helpers/align_timeseries.R`, `AGENTS.md`, plus the
  regenerated `docs/*.html`/`docs/site_libs/*`/`docs/data/qc_summary.csv`/
  `data/derived/qc/qc_summary.csv` from the live build_website() test)
  are not yet committed/pushed to git.

## Session 36 continued (2026-09-27, part 3): DEMO GeoPackage re-export, spot-check, and other-vulnerable-joins audit

Three quick follow-ups to the align_timeseries.R join fix.

- **DEMO GeoPackage re-exported** after re-running `build_temp_flow()`/
  `build_sample_flow()`/`build_sample_flux()` against
  `geochem_demo.sqlite` with the fixed join -- confirmed identical
  corrected counts to the operational database (`temp_flow` 103693,
  `sample_flow` 54, `sample_flux` matching). 16-layer GeoPackage export
  clean.
- **Spot-checked the 73 real `sample_flow` matches against known
  field-visit dates** -- all `time_diff_min` values now fall in a
  sensible 0-2.5 minute range (matches the USGS 15-minute reporting
  cadence), and the 73 rows cluster into exactly 7 real, independently
  documented field-visit days: 2025-04-17/2025-08-27 (NDEP grab
  samples), 2026-04-04/04-11 (the dense `SBO_000xx` steaming-ground
  survey walk), 2026-04-14 (temperature-logger deployment day), and
  2026-04-29/05-01 (the FIELD sampling campaign). **Precise
  cross-check**: the `SBRR` row (sample 819, 2026-05-01 12:37) gives a
  matched USGS discharge of 0.317 m3/s = exactly 11.2 cfs -- the same
  figure already independently documented in Session 30's real Cl+
  discharge Q_TW=42.1 L/s calculation. This is strong, independent
  confirmation the fix produces trustworthy, physically sensible
  matches, not just a plausible row count.
- **Audited the rest of the codebase for the same data.table
  on-column-aliasing quirk** -- grepped for every `roll =`/`on = .(...)`
  /`on = c(...)` rolling-join pattern project-wide. Only 5 files use
  `data.table` at all (`align_timeseries.R`, `nearest_station.R`,
  `sample_flow.R`, `sample_flux.R`, `temp_flow.R`), and only
  `align_timeseries.R` itself contains a rename-style `on=` join (two
  call sites -- the now-fixed grouped branch and the already-correct
  ungrouped branch). `nearest_station.R` uses a cross-join +
  `which.min()` (no rolling join, not vulnerable). `sample_flux.R`
  uses a plain `merge(by = "sample_id")` equi-join (no column
  renaming, not vulnerable -- it inherits correctness from
  `sample_flow` being fixed upstream). All three real call sites of
  `align_timeseries()` (`build_temp_flow`, `build_sample_flow`,
  `build_temp_gradient_links`) are covered by the one shared-helper
  fix -- **no other vulnerable instance of this bug exists anywhere
  else in the project.**

## Session 37 (2026-09-26): Skalbeck (2001) Table B-2/A-2/Table-3 completion, Leapfrog geologic model, logger uncertainty

Retroactively documenting a block of work that landed between the
prior "Session 35" and "Session 36" entries without its own session
note (commits `4fa34e7` through `f3b79d2`). Covers finishing the
Skalbeck (2001) subsurface dataset and building the first real
Leapfrog-facing geologic model artifacts.

- **Skalbeck (2001) Table B-2 (monthly Cl/B/temperature/water-depth
  monitoring, 1985-1998)** completed well-group by well-group, each a
  careful cross-check against the scanned page images, not blind OCR
  trust: Herz Geothermal (48 rows) + Herz Domestic (45 rows); Peigh
  Domestic (102 rows) + Pine Tree Ranch #1 (48 rows, correctly
  truncated to its real 1984-1990 sampling window); later, Herz
  Domestic (+29 rows, Nov89-Dec92) and Curti Domestic (+7 rows, gap
  1990-91) from additional user-supplied images. **Flame and
  Steinhardt were attempted but explicitly not resolved** -- ambiguous
  Cl/temperature range overlap broke the ordered-range parser;
  flagged honestly as needing better scans, not force-transcribed.
  Real bugs caught while transcribing: several Herz-Geothermal
  "depth" values were actually column-bleed from Herz-Domestic's Cl
  column (set to `NA`, not guessed); ~9 Herz-Domestic months excluded
  via a B>5 mg/L sanity check.
- **Table A-2 (241/353 spatial points) and Table 3 (41 wells: 10
  matched to existing `Wells`, 31 registered provisional) ingested**,
  with 112 genuinely ambiguous Table A-2 rows logged to
  `data/derived/skalbeck2001_table_a2_ambiguous_rows.csv` for human
  review rather than guessed. Real **TH-1/2/3 water-depth series**
  (160 readings, 1985-1998) is a rare multi-decade pre-2000 continuous
  water-level record. New `Well_Lithology.formation_unit` controlled
  vocabulary (`Qal`/`Tv`/`AltKgdpKm`/`Kgd`) classifies both existing
  and Table-3-derived lithology rows. **Real bug fixed later in this
  same block (`cc0ab92`)**: `AltKgdpKm` is the altered *cap* of the
  `Kgd` bedrock body (Skalbeck's own naming), not a separate layer
  between `Tv` and a disconnected deeper `Kgd` -- 19 already-inserted
  `Well_Lithology` rows were relabeled after cross-sections/mini-log
  plots made the mislabeling visually obvious.
- **New Leapfrog-facing geologic surfaces**: gridded IDW surfaces +
  quasi-3D plotly view of the Table A-2/Table-3 point cloud; later,
  `scripts/analysis/skalbeck_cross_sections.R` projects each real
  point onto its nearest Table-1 flight line (median perpendicular
  distance ~0.35 m, confirming points genuinely sit on the mapped
  lines) and draws sharp point-to-point "hard line" cross-sections as
  an alternative to the smoothed IDW grid, per direct user feedback
  that IDW blurs real geologic contacts. **Real bug fixed**:
  meter-based `Well_Lithology` intervals were silently treated as feet
  in the Leapfrog export -- fixed. No literature source gives
  per-formation-unit hydraulic conductivity -- documented as a real,
  stated gap, not filled with an assumed value.
- **New `Logger_Specifications`/`Logger_Calibration_Checks` schema**
  (real HOBO U24-002-C / Elitech LogEt 8 accuracy specs; 10 real
  temperature checks auto-detected from `Field_Measurements`).
- **New schema files `16_geophysical_depth_points_schema.R`,
  `17_formation_unit_schema.R`, `18_logger_uncertainty_schema.R`**
  (database/schema/ now runs 01-19, see Session 38 below for `19`).
- Vaughan et al. (2005) added to the bibliography as a qualitative
  (no numeric K value) cross-reference for `AltKgdpKm` alteration.
  Steamboat Ditch checked as a possible recharge end-member: dilute
  (Cl 0-5 mg/L, one flagged Cl=1100 mg/L ambiguous-date outlier),
  confirmed Cl alone can't separate Truckee-Ditch recharge from
  Whites Creek runoff since zero isotope samples exist for either --
  fed into the Steamboat Ditch losing-reach field-measurement proposal
  in `docs/action_items_for_user.md`. Little Washoe Lake checked as an
  end-member candidate: no `Locations` row or chemistry exists for it
  at all.
- **Two real PDF-render bugs fixed** while embedding new facies
  PCA/heatmap figures into notebook 07: the 3D plotly Skalbeck view
  broke PDF/LaTeX builds (now branches on `knitr::is_latex_output()`,
  static 2D fallback for PDF); an unescaped underscore in a
  kableExtra LaTeX caption ("Field_Measurements") hard-failed the PDF
  compile (escaped for LaTeX only). `notebooks/_freeze/` cleared and
  `00_full_report.pdf` regenerated to confirm.

## Session 38 (2026-09-26, continued): NDEP site_type fix, Location_Aliases, new diagnostic figures, tidymodels Cl~conductance (synthetic)

Also retroactively documented (commits `0c82e26` through `82d7543`).

- **Root-cause fix**: `scripts/ingest/helpers/ndep_locations.R` had
  hardcoded `site_type = "background"` for *every* NDEP station
  regardless of what kind of site it actually was. Replaced with a
  real classifier (Creek/Ditch name-pattern match on
  `WATERBODYNAME`/`STATIONNAME`); a retroactive, idempotent backfill
  reclassified all 15 existing `'background'` rows to `'creek'`
  (confirmed by name: all 15 are real creek/ditch surface-water
  stations, not wells). `'background'` remains in the schema as a
  legitimate "genuinely unclassified" fallback, not removed.
- **New `Location_Aliases` table** (`database/schema/
  19_location_aliases_schema.R`) groups multiple external
  names/codes that refer to the *same real-world monitoring point*
  under one canonical name, without merging or re-pointing any
  `location_id` (a deliberate, safer alternative to a merge, per
  explicit user decision). Seeded with real, coordinate-confirmed
  groupings: **SBRR group** (`SB5`/"Steamboat Creek @ Rhodes Road",
  `SB6`/"Steamboat Ditch @ Rhodes Road", `STBT02Steamboat-2a`, all
  within ~150 m of `SBRR` and the co-located USGS gauge 10349300) and
  **SBGG group** (`SB7`/"Steamboat Creek @ Geiger Grade", confirmed by
  Sorey & Spielman's own literature that SBGG = "Geiger Grade").
  Explicitly checked and NOT grouped: `SB44` (a different creek,
  despite being geographically closer to SBGG than SB7 is). New
  `get_location_family_chemistry(con, canonical_name)` helper
  (`scripts/analysis/location_aliases_helpers.R`) does a read-time
  UNION across an alias group's real `Samples`/`Lab_Analyses` rows --
  never blends or anonymizes the underlying rows.
- **Skalbeck flag-not-exclude convention implemented**: Table B-2's
  `.ingest_skalbeck2001_b2_well()` extended with a `flag` column
  (blank for normal rows, e.g.
  `possible_column_bleed_from_neighboring_well` for recovered
  ambiguous ones); flags are written into `Lab_Analyses.qualifier`
  (already existed, previously unused) / `Water_Level_Observations.
  notes`, so a future analysis can include/exclude flagged rows
  explicitly via `qualifier IS NULL` instead of them being silently
  absent. 8 new rows (3 Herz Domestic, 5 Curti Domestic) recovered
  from clearer images under this convention.
- **New diagnostic figures**
  (`scripts/analysis/build_facies_diagnostic_plots.R`,
  `build_mixing_and_distribution_plots.R`): facies dendrogram,
  silhouette plot, hclust-vs-mclust agreement heatmap, site-type
  alluvial diagram, per-cluster ion raincloud plot, PHREEQC
  mixing-fraction distribution, 3-way SI-by-group comparison. **Real
  bug found**: `cluster_hydrochemical_facies.R`'s PHREEQC SI join
  queried nonexistent columns (`mineral`/`saturation_index` instead of
  the real `parameter`/`value`), silently swallowed by a `tryCatch` --
  SI columns were never actually attached to the clustering output
  despite code comments claiming otherwise. New
  `scripts/analysis/facies_random_forest.R` (`ranger`): Na > Mg > Cl >
  Ca > K > Alkalinity > SO4 importance ranking, 97.4% held-out
  accuracy for facies-membership classification.
- **`run_pipeline.R` crash-fix**: `RUN_INGEST$skalbeck2001` (and by
  extension any flag) had no `is.null()` fallback default unlike every
  other flag -- a caller supplying a partial `RUN_INGEST` list (e.g.
  README's own documented "skip ingestion" snippet) crashed deep in
  the ingest stage with an opaque "argument is of length zero." Fixed
  generally: any `RUN_INGEST` list now backfills missing flags from
  the safest preset. Also fixed: a `count()` call masked by another
  package (qualified to `dplyr::count()`); a website heatmap chunk's
  NaN-only cleanup missed real `NA` `Temp` values introduced by the
  new Skalbeck rows (`is.nan` -> `is.na`); a missing `'creek'` entry in
  `site_colors` for the newly-reclassified creek-type samples; ~16
  tracked `docs/` files that `render_site()` had deleted mid-build,
  restored via `git checkout`.
- **First tidymodels Cl~conductance workflow, explicitly synthetic-
  only**: `scripts/analysis/sampling_frequency/03_chloride_models.R`'s
  synthetic data-generating process gained a real lag (default 6
  days/2 steps -- it previously had none at all, making a lagged-
  conductivity feature untestable); removing seasonal `doy_sin`/
  `doy_cos` terms dropped the lm's RMSE 1.26 -> 0.91 on lag-free
  synthetic data (they were actively hurting it). New
  `03b_chloride_models_tidymodels.R`: full recipe/workflow/
  workflow_set with `rsample::rolling_origin()` CV and `tune_grid()`
  for `mtry`/`min_n` (an apparent `min_n=15` boundary effect resolved
  into a genuine interior optimum ~20-25 once the grid was extended to
  30). Winning model
  (`models/chloride_prediction/tidymodels_lagged_lm_20260926_200611.rds`,
  lm on lagged sc_25c/temperature_c, RMSE=1.00 rolling-origin CV) saved
  and logged to `models/MODEL_REGISTRY.csv`. **No real paired Cl/
  conductivity field data exists yet** -- this entire workflow is a
  synthetic self-test/methods demonstration, not a real predictive
  model, exactly like the sampling-frequency framework it extends.

## Session 39 (2026-09-27): chloride mass-balance formula corrected (two-station flux, not single-station ratio)

- **Real formula error found and fixed.** A live notebook-07 chunk
  (commit `7fa5041`) had replaced an earlier hardcoded, non-reproducible
  "42.1 L/s" thermal-discharge figure with a live-computed value using
  a *single-station* concentration-ratio formula -- but re-reading the
  GRC 2026 poster PDF directly (`pdftotext`, not memory) found the
  poster's real formula is a **two-station chloride-flux difference**
  (Q_TW = (flux at SBBV minus flux at SBRR) / 820 mg/L, the thermal
  end-member concentration per Sorey & Colvard's own convention). New
  `scripts/analysis/chloride_mass_balance.R` implements the correct
  formula once, as the single source of truth; wired into
  `run_pipeline.R` as an always-on reporting step, writing
  `data/derived/chloride_mass_balance/chloride_mass_balance.csv`
  (copied into `docs/data/` for the website). Notebook 07's chunk and
  every downstream reference (a hardcoded tribble value, inline prose
  in `website/results.Rmd`) were rewritten to call this one script
  rather than re-deriving the formula inline.
- **Real result for the only paired SBRR/SBBV date on file
  (2026-05-01): 58.7 L/s** -- differs from the poster's own averaged
  ~27 L/s (a multi-date average, not yet reproducible with only one
  date on file) and from the two earlier, now-superseded 42.1/62.6 L/s
  figures from this same correction sequence -- presented transparently
  as a single real, dated data point, not silently reconciled with the
  poster's own multi-date average.
- `website/results.Rmd`'s "A First Answer" section: fixed the LaTeX
  formula display, added a live chunk, removed a stale "not yet
  reproducible" caveat. Rebuilt via the protected `build_website()`
  wrapper, confirmed 0 missing `docs/` files afterward.

## Session 40 (2026-09-27, continued): documentation catch-up, tidiness fixes, Cl/B t-test regression fixed, curated publication figures

Direct response to a request to refocus/tidy the project, catch
`AGENTS.md` up on undocumented work (Sessions 37-39 above), and curate
a small set of publication-quality figures tied to clearly stated
questions.

- **Two real, isolated bugs fixed**: `notebooks/02_sc_discharge_
  weather.qmd` had a stray leftover edit-artifact fragment
  ("`and interpratibility? ---`") sitting before its own YAML `---`
  delimiter (harmless to rendering, since pandoc happened to tolerate
  it, but a real tidiness defect); `notebooks/05_data_inventory_and_
  well_network.qmd` had an accidentally duplicated sentence about NDOM
  coordinate discrepancies (two adjacent, identical "ArcGIS uncertainty
  and are worth a manual look..." sentences). Both fixed; both
  notebooks re-rendered standalone to confirm no breakage. A project-
  wide grep for the same leftover-edit pattern found no other
  instances.
- **Real, previously self-flagged Cl/B t-test regression fixed** in
  `notebooks/07`'s `cl-b-test` chunk (see that notebook's own
  "Fixed 2026-09-27" note, added in this session, replacing a
  "this is not fixed here" flag from 2026-09-26): the chunk's query
  (`data_source != 'NDEP'`) was correct only while the curated Sorey &
  Colvard (1992) end-member set (n=7) and this project's own FIELD
  samples (n=6) were the only non-NDEP Cl+B sources on file. Once
  Skalbeck (2001) Table B-2's monthly domestic-well data (8 distinct
  `Skalbeck...` source labels, also `!= 'NDEP'`) landed, the query
  silently grew "1950-1991" from 7 to 604 rows (several with
  detection-limit `B=0`, producing `Inf`/`NaN`), breaking the `t.test()`
  outright (`p = NA`). **Fix**: scope the query explicitly to
  `data_source IN ('Sorey & Colvard 1992', 'FIELD')` -- the deliberate,
  narrow comparison Sorey & Colvard's own methodology intends -- which
  reproduces the original 19.6 vs. 21.9, p = 0.015 result exactly.
  Verified via a live re-render of notebook 07 (rendered HTML confirmed
  `p-value = 0.01538`). The separate "bootstrap-CI companion" figure
  (which deliberately uses the larger, Skalbeck-inclusive population as
  an alternate view) is unaffected and was left as-is, with its own
  cross-reference note updated to point at the now-fixed chunk instead
  of an open regression.
- **New shared plotting theme**: `scripts/analysis/plot_theme.R`
  (`theme_steamboat()`, a colorblind-safe `palette_steamboat` keyed to
  this project's recurring site_type/era/facies vocabulary). Does not
  retroactively touch already-generated PNGs -- applies the next time a
  figure's generating code is edited or re-run.
- **Five curated, captioned, publication-quality figures** saved to
  `output/figures/manuscript/` (regenerated on demand, not committed
  static images, consistent with this project's existing convention):
  `cl_b_ratio_by_era.png` (the corrected Cl/B comparison, well-name
  labels, t-test in caption), `geothermometer_comparison.png` (Na/K vs.
  quartz divergence, now aggregated to per-well means across all 67
  real geothermometer rows -- including Mariner & Janik 1995's wells,
  not just the original 8-sample set -- rather than the earlier
  cluttered all-rows plot), `sampling_frequency_error_curve.png`
  (notebook 09's real EC-based Monte Carlo reconstruction-error curve,
  with a 5%-reference line added). The other two curated figures
  (`facies_pca_biplot.png`, `facies_rf_importance.png`) already existed
  from Session 38's diagnostic-figures work and were reused as-is.
- **`manuscript/04_results.qmd` rewritten** from a bullet-point findings
  checklist into an illustrated results section: each of the five
  figures above is embedded with a question-first framing paragraph
  (what question it answers, why it matters, the real statistic behind
  it) plus an explicit "What these results do not yet show" closing
  section (the still-ambiguous Cl-vs-time trend, PHREEQC mixing on
  representative-not-paired end-members) so the chapter doesn't
  overstate what's actually been shown. Verified by a direct
  `quarto render 04_results.qmd --to html` (renders cleanly).
- **Notebook-07 restructuring was scoped but deliberately NOT executed
  this session**: direct investigation confirmed notebook 07
  (`07_historical_context_sorey1992.qmd`, 2,782 lines / 62 chunks) has
  become a grab-bag covering far more than its "Historical Context:
  Sorey & Colvard (1992)" title promises -- it now also carries the
  entire Skalbeck (2001) subsurface-model thread, most of the project's
  cross-cutting statistics (duplicating/coupling with notebook 08), and
  several "homeless" hydrology side-analyses (Steamboat Ditch,
  Truckee-Ditch separation, local seismicity, temperature-vs-pressure).
  A physical split (e.g. a new `notebooks/10_subsurface_geologic_
  model.qmd` for the Skalbeck thread) was judged too high-risk to do
  safely without dedicated time for careful line-range surgery plus a
  full standalone + combined-report re-render cycle (per the Session 34
  lesson about `{{< include >}}`/duplicate-chunk-label/stale-freeze
  pitfalls) -- deferred as a concrete, scoped next step rather than
  attempted partially. One genuine finding from the investigation,
  worth recording: notebook 08's facies-cluster PCA section does
  **not** actually require notebook 07 to have executed first in the
  same session, as earlier framing suggested -- it queries the
  *persisted* `Facies_Cluster_Assignments`/`Facies_Cluster_Runs` tables
  directly (populated via `run_pipeline.R`'s
  `RUN_ANALYSIS$facies_clusters` flag or a manual
  `register_facies_clusters()` call), so the real dependency is "has
  anyone ever persisted a facies-clustering run," not "did notebook 07
  run in this session" -- a smaller, easier-to-document reproducibility
  note than a structural coupling.
- **Not done this session**: the Skalbeck Steinhardt/Flame Table B-2
  transcription gaps remain open (flagged, not blocking); no new
  statistical-modeling directions were opened (the one clear candidate,
  real Cl~conductivity prediction, is correctly blocked on real paired
  field data, per Session 38 -- no action needed there beyond what's
  built); this session's file changes are not yet committed/pushed to
  git as of this note.

## Session 41 (2026-09-30): ~40-page thesis proposal assembled from the manuscript/ chapter skeleton

Built the full thesis-proposal document requested: a single, cohesive,
grad-student-voiced ~40-page PDF assembled from the six `manuscript/`
chapter files, covering background/chronology, geochemical background,
database/methods/QA-QC, results, discussion/future work, and the
calibration sampling proposal, with a real summarized bibliography and
a handful of curated figures. Planned in Plan mode
(`.posit/assistant/plans/2026-09-30-2226-plan.md`) and executed in full
in the same session.

- **New master document**: `manuscript/00_thesis_proposal.qmd` --
  title page, abstract, and `{{< include >}}` assembly of all six
  chapters, mirroring `notebooks/00_full_report.qmd`'s already-proven
  transclusion pattern (no duplicate chunk labels across the six
  chapters, confirmed by grep before assembling). Renders cleanly to a
  43-page PDF via the existing TinyTeX/LuaLaTeX toolchain. Inherits,
  and explicitly documents inheriting (in its own front-matter note),
  the same known cosmetic stray-title-page limitation
  `notebooks/00_full_report.qmd` already has and deliberately does not
  fix, for the same reason (fixing it would require stripping YAML
  from all six chapter files, breaking their standalone rendering).
- **All six chapters drafted/expanded from their prior stub/partial
  state**: `01_introduction.qmd` (new -- study area, a chronology
  table + new timeline figure spanning 1950-2026, the chloride-tracer/
  conductivity-proxy motivation, three explicit thesis questions);
  `03_methods.qmd` (expanded -- new "Database architecture, data
  sources, and quality control" section covering sources/pipeline
  design/real QC fixes at a top level, field methods, conductivity-
  as-Cl-proxy methods, a condensed sampling plan, and a new
  "Hydrologic and geologic modeling directions" section covering
  potentiometric mapping and the Leapfrog/ArcGIS fault-digitizing
  workflow); `04_results.qmd` (rewritten from a findings checklist
  into flowing prose, adding a new live discharge-through-time section
  and figure); `05_discussion_and_future_work.qmd` (new -- revisits
  the three thesis questions, restates the chemistry-first modeling
  principle, sequences the three real roadblocks from `ROADMAP.md`
  into prose, closes with a summary). `02_geochemical_background.qmd`
  and `06_calibration_sampling_proposal.qmd` (already drafted) were
  left largely as-is; `02` gained one new subsection (below).
- **`references.bib` expanded from ~15 to ~35 real entries**, pulled
  from `docs/literature/annotated_bibliography.qmd`'s 48
  already-read, individually-verified sources (Skalbeck 2001, Lindsey
  et al. 2026, the Irvin & Lindsey 2026 poster, McCleskey et al.
  2012/2016, Thompson & White 1964, Silberman et al. 1979, Cohen &
  Loeltz 1964, Nehring 1979, Arehart 2003, Johnson & Hulen 2006,
  Bjornsson 2014, Combs & Goranson 1994, Goranson 1995/2000, Newman
  2026 and Janik et al. 2000 -- the last two kept explicitly flagged
  as different-system methodological analogs, not Steamboat, Nevada
  data). A new "Related literature: reservoir engineering, structure,
  and regional analogs" subsection was added to `02_geochemical_
  background.qmd` specifically to give the less-central sources (slim-
  hole monitoring, magmatic-heat-source evidence, the 83C-6ST1
  directional-drilling account, regional Truckee Meadows hydrogeology)
  a real, brief summary and a citation, rather than leaving them in
  the bibliography unused. Confirmed via render log + a
  literal-`@`-leftover grep that every citation key resolves and the
  generated References section (pandoc citeproc, cites only what's
  actually referenced in prose -- about 27 of the ~35 entries) renders
  correctly.
- **Two new figures**, built via a new script,
  `scripts/analysis/manuscript_figures.R`
  (`build_manuscript_figures(con)`): `discharge_through_time.png`
  (factored out of `notebooks/07`'s own `discharge-plot` chunk into a
  reusable function so the manuscript and the notebook stay in sync
  automatically, using `chloride_mass_balance.R`'s real, corrected
  Q_TW calculation -- confirmed the real live value, 58.7 L/s for the
  single 2026-05-01 paired SBRR/SBBV date, matches Session 39's
  already-documented result exactly) and `steamboat_timeline.png` (a
  new, simple horizontal timeline figure spanning 1950-2026, built
  from dates already documented elsewhere in this project --
  `website/timeline.Rmd`, notebook 07's own discharge table, the
  annotated bibliography -- not estimated fresh). Both regenerated on
  demand, consistent with this project's "no static committed
  figures" convention; verified visually before use. The chapters
  otherwise reuse three already-existing figures
  (`cl_b_ratio_by_era.png`, `geothermometer_comparison.png`,
  `sampling_frequency_error_curve.png`) plus the facies PCA/RF-
  importance pair.
- **`manuscript/README.md` updated**: status table now shows all six
  chapters (plus the new master document) as drafted rather than
  stub/partial, and the "Honest status" note dated to this session.
- **Not done this session**: no new database ingestion, schema
  changes, or PHREEQC runs (this was a documentation/writing task
  only, reusing already-computed real results); no fault digitization
  or Leapfrog build-out (the proposal describes both as future work,
  per the existing README "Planned:" section); DEMO database untouched.
  This session's file changes are not yet committed/pushed to git.
  Also flagged to the user, separately from the plan: several
  standing action items remain open independent of this proposal --
  the NDEP/Ormat data requests, digitizing Collar & Huntley (1990)
  Figure 1, resolving the remaining ambiguous well identities, and the
  still-deferred notebook-07 restructuring (Session 40) -- none
  addressed this session.

## Session 42 (2026-09-30, continued): NDEP PRR outlet-station promotion, chemistry-by-port summary, WETLAB Appendix D parser

Three related tasks executed via an approved Plan-mode plan
(`.posit/assistant/plans/2026-09-30-2226-plan.md`), following up on the
prior turn's finding that most "Ormat well chemistry" in the NDEP PRR
source was either unpromoted (the six port-outlet samples) or unparsed
(the TFT Compliance Reports' Appendix D).

- **Six staged NDEP PRR outlet samples promoted** (`Galena 1/2/3
  Outlet`, `SB2 Outlet`, `SB3 Outlet`, `SBHR Outlet` -- 38 rows each,
  228 total, staged since Sessions 3-6, never promoted). Filled the six
  blank rows in `staged_ndep_location_map.csv` using the corresponding
  `Sampling_Ports` row's own real coordinate (ArcGIS facility-polygon
  centroid from `register_facility_areas.R`, Session 7) -- the same
  physical pad, not an independent survey point, documented as such.
  `SB2 Outlet`/`SB3 Outlet` both resolve to the single `SB2/3` port
  centroid (kept as two distinct Locations, since they're two distinct
  named taps). Filled `Sampling_Ports.location_id` (dangling NULL since
  Session 5) for the four 1:1 ports (`Galena 1/2/3`, `SBHR`); left NULL
  for `SB2/3` (fed by two distinct outlet locations, can't be one FK).
  Real result: all six now show genuinely thermal chemistry (Cl 740-860
  mg/L, Na 640-720 mg/L) in `vw_major_ions` -- but are **not**
  PHREEQC-eligible (`get_phreeqc_eligible()` correctly rejects all 12
  sample-rows with "missing temperature; missing pH", since this 2024
  semi-annual source never recorded field parameters for these outlets,
  and `build_phreeqc_solutions()` only ever pulls pH/temp from the
  *same* `sample_id`, never a cross-location/date fallback).
- **Real, project-wide bug found and fixed**: `vw_major_ions`'s analyte
  filter listed a literal `'HCO3'` code only -- never this project's
  own standard `'Alkalinity'` code (the Session 15-16 convention,
  HCO3-mass-equivalent, unit-converted from whatever raw CaCO3/HCO3
  basis a source used). This silently excluded 736 real Alkalinity rows
  (NDEP main + NDEP PRR + Sorey & Colvard 1992 + Mariner & Janik 1995)
  from the major-ions view project-wide, not just the newly-promoted
  outlet samples. Fixed additively (`IN (...,'HCO3','Alkalinity')`);
  `major_ions` GeoPackage layer grew from 2824 to 4355 rows as a direct
  result. Also added a missing `sgs_analyte_map` entry for `"Alkalinity,
  Hydroxide (As CaCO3)"` (previously fell through unmapped), following
  the existing `_dup`/excluded-code convention.
- **New chemistry-by-sampling-port summary**
  (`scripts/analysis/port_chemistry_summary.R`,
  `compute_port_chemistry_summary()`/`build_port_chemistry_report()`):
  joins the newly-promoted outlet samples to their port via an explicit,
  human-reviewed lookup table (needed since `SB2/3` can't be a single
  FK), reports n/mean/min/max per port/analyte (deliberately no SD --
  n=2 per port, n=4 for `SB2/3`), and includes a second, best-effort join
  through `Production_Port_Links` -> `Wells` -> chemistry that
  currently contributes nothing (confirmed: zero production/injection
  wells have both a populated `location_id` and real chemistry) but is
  ready for when that data exists. Writes
  `data/derived/port_chemistry/port_chemistry_summary.csv` and
  `output/figures/port_chemistry/port_chemistry_by_port.png` (every
  real point plotted, not just a bar-chart mean, given n=2). Wired into
  `run_pipeline.R` as an always-on read-only reporting step (mirrors
  `chloride_mass_balance.R`'s pattern). New Section 6 added to
  `notebooks/05_data_inventory_and_well_network.qmd` presenting this
  live, with the n=2 caveat stated in prose.
- **TFT Compliance Report Appendix D -- built, but a real scope
  correction first.** The two TFT reports on file
  (`data/raw/ndep/PRR/PPR_05_26_2026/`) do **not** contain chemistry
  broken out by individual production well -- each contains exactly one
  real WETLAB (Western Environmental Testing Laboratory) lab sample: a
  single required UIC-permit injection composite ("G2 Injection",
  confirmed via the accompanying U230 form: "Injection Piping downstream
  of HX in Plant"), not chemistry for well 24-5 itself despite that
  well's name being in one report's filename (it refers to a production-
  well-group flow narrative elsewhere in the document). Flagged to the
  user in the plan before building.
- **This project's first position-aware PDF parser**:
  `scripts/ingest/helpers/parse_wetlab_appendix_d_pdf.R`
  (`parse_wetlab_lab_report()`, `is_wetlab_format()`), using
  `pdftools::pdf_data()` word-level x/y coordinates instead of the
  existing `pdftotext -layout` + regex-split approach (confirmed, by
  direct inspection, to badly misalign this specific table -- e.g. a
  naive line-based read attributes the wrong result to "Total
  Alkalinity" vs "Bicarbonate"). Clusters words by exact y into rows,
  assigns each word to the nearest header column via midpoints between
  the real header row's own x-positions (general to any WETLAB report's
  exact pixel layout, not hardcoded), and recovered a complete, clean,
  self-consistent 42-analyte panel per report -- including real pH
  (6.75, 6.56) and temperature (24C, 22C), the field parameters the six
  outlet samples above are missing. Cross-checked several recovered
  values against independently-known plausible ranges (Cl 794/682 mg/L,
  Na 600/600 mg/L -- consistent with the other Galena-port outlet
  values from the same session) as informal validation that the parser
  is right, not just self-consistent.
- **Wired into `ingest_ndep_prr.R`**: `is_wetlab_format()` checked
  before the existing SGS-format attempt (which would otherwise
  silently produce zero rows on a WETLAB PDF, as it always had for
  these two files); a `.normalize_wetlab_station_name()` helper maps
  known composite-sample patterns ("G1/G2/G3 Injection", "SBHR",
  "SB2"/"SB3") to a stable canonical station name so repeat samples at
  the same physical point (different dates) resolve to the same
  Location, falling back to the raw `customer_sample_id` (kept
  distinct/unresolved) for any pattern not yet seen. New
  `force_reprocess`/`force_reprocess_pattern` parameters (mirrors
  `ingest_well_logs.R`'s own convention) let a re-parse target only
  specific filenames (e.g. `"TFT"`) after an extraction-logic change,
  without needlessly re-staging and duplicating already-working sources
  like the SGS-format Semi-Annual Digital Submittal.
- **Real, independent bug found and fixed while testing this**:
  `promote_staged_ndep.R`'s `staging_id` backfill
  (`UPDATE ... SET staging_id = rowid WHERE staging_id IS NULL`) only
  ever ran inside the one-time `ALTER TABLE ADD COLUMN` block -- any row
  appended by a *later* `ingest_ndep_prr.R` run (exactly this session's
  new WETLAB rows) kept a permanently NULL `staging_id`, which broke the
  final `"WHERE staging_id IN (...)"` promotion-marking `UPDATE` with an
  opaque `"no such column: NA"` error the moment such a row was
  promoted. Fixed by running the backfill unconditionally (a no-op once
  every row already has one) -- a real, previously-latent bug that
  would have hit *any* future new NDEP PRR ingest, not just this one.
- **Added new `sgs_analyte_map` entries** for the WETLAB-specific names
  with no SGS equivalent: `"Temperature at pH"` -> `temperature`,
  `"pH"` -> `pH`, `"Total Alkalinity"` -> `Alkalinity` (factor 1.2189),
  `"Bicarbonate (HCO3)"` -> `HCO3_as_CaCO3_dup`, `"Carbonate (CO3)"` ->
  `CO3_as_CaCO3_dup`, `"Total Suspended Solids (TSS)"` -> `TSS`,
  `"Total Dissolved Solids (TDS)"` -> `TDS`, `"Silica"` -> `SiO2`,
  `"Nitrate Nitrogen"` -> `NO3`. Trace metals (Aluminum, Barium,
  Beryllium, Cadmium, Chromium, Copper, Iron, Manganese, Molybdenum,
  Nickel, Silver, Zinc, Lead, Selenium, Thallium, Mercury) and the lab's
  own charge-balance QC rows (Anions/Cations/Error) are left unmapped
  (logged, not dropped) -- not needed for major-ions/PHREEQC purposes
  this session.
- **Real, positive result**: the two Galena 2 injection-composite
  samples (2025-07-09, 2026-04-07) are the **first NDEP-PRR-sourced
  samples ever to pass `get_phreeqc_eligible()`** (real pH+temperature+
  Na+Cl from the *same* sample). Ran the real PHREEQC speciation
  pipeline against both (`run_phreeqc_pipeline(con, sample_ids = ...)`,
  auto-recommended WATEQ4F for trace-metal speciation), storing 54 real
  result rows.
- **Applied to the real `geochem_operational.sqlite`** (backed up first
  to `database/archive/geochem_operational_pre_prr_outlets_<timestamp>.sqlite`;
  every step verified against a scratch copy first): 228 new outlet
  Lab_Analyses rows, 84 new WETLAB Lab_Analyses rows, 4 Sampling_Ports
  location_id fields filled, `vw_major_ions`/`create_gis_views()`
  rebuilt, `PHREEQC_Solutions` rebuilt (1522 rows, 314 complete),
  GeoPackage re-exported cleanly (16 layers; `major_ions` 2824 -> 4355,
  `locations` 198). QC re-run clean -- the only 2
  `PHREEQC_Run_Failures` rows are pre-existing (2026-09-26, unrelated
  wells `21-5`/`83A-6`), confirmed nothing new broke.
- **CRLF editing note for future sessions**: `scripts/ingest/
  promote_staged_ndep.R` and `scripts/ingest/ingest_ndep_prr.R` turned
  out to have *inconsistent* internal line endings (some physical lines
  LF, others CRLF, within the same file) -- worse than the usual
  "whole file is CRLF" caveat documented in many prior sessions. Even
  the established `readLines()`/`writeLines()` round-trip wasn't tried
  here; instead, every multi-line `edit` old_string on these two files
  failed unpredictably regardless of content correctness (verified
  byte-for-byte against the actual file each time), while every
  **single-physical-line** old_string succeeded reliably, including
  when the new_string itself spanned many lines. Worth trying
  single-line-anchored edits first on any file that mysteriously
  rejects an exact-match multi-line edit, before assuming the content
  itself is wrong.
- **Not done this session**: no attempt to recover chemistry for named
  individual production wells (24-5, 78-29, etc.) from any other source
  -- the TFT reports don't have it and no other candidate source is on
  file; DEMO database untouched.

### Correction (same session, continued): real U230 field pH/temperature/conductivity added for the Galena 2 injection composite

The "six outlet samples lack field pH/temperature" statement above is
about a *different, separate* NDEP document (the 2024 Semi-Annual
Digital Submittal) and remains accurate for those six. It does NOT
apply to the Galena 2 Injection Composite (TFT) sample from Task 1 --
the user supplied direct photos of that same sample's UIC Form U230
(Field Sampling & Monitoring Summary), a document `ingest_ndep_prr.R`
had previously skipped entirely as scanned/no-text-layer. That form
gives a real, field-measured pH (6.25), temperature (24.4C), and
specific conductance (3560 uS/cm) for the 2025-07-09 11:15 sample --
independent of, and different from, the WETLAB lab's own re-measured
pH (6.75) and temperature (24C) for the same sample (the lab report's
own "Were any holding times exceeded? YES, pH" flag on the U230 form
plausibly explains the divergence: the pH held past its holding time
before lab analysis).

- **Applied to the real database**: a new `Data_Sources` row ("Nevada
  DEP (Public Records Request) - U230 Field Form", distinct from the
  WETLAB lab report's own source) and 3 new `Field_Measurements` rows
  (pH, temperature, conductivity) for sample_id 1530. Backed up first
  to `database/archive/geochem_operational_pre_u230_field_data_<timestamp>.sqlite`.
- **Real effect, confirmed by design, not a bug**:
  `build_phreeqc_solutions()` already prioritizes `Field_Measurements`
  over `Lab_Analyses` for the same sample's pH/temperature (a real
  field instrument reading over a lab-reported one) -- rebuilding
  `PHREEQC_Solutions` correctly shifted sample 1530's modeled pH/
  temperature from 6.75/24.0C to 6.25/24.4C with no code change needed.
  Re-ran real PHREEQC speciation for this one sample with the updated
  values (27 result rows). QC re-run clean afterward.
- **Not done**: no equivalent U230 form has been supplied yet for the
  second real sample (sample_id 1531, 2026-04-07) -- it still uses its
  lab-reported pH/temperature only.

### Addendum: NDEP_compiled_U230_Steamboat_reports.pdf -- OCR unblocked, one real field sample added, SB2 Outlet coordinate upgraded

User asked to review this 138-page compiled U230 document (previously
recorded, Session 3, as "scanned, no extractable text, OCR required,
not attempted"). Retested using the already-built well-log OCR
helpers (`.ensure_tesseract()`/`.ocr_pdf()` from
`parse_well_log_pdf.R`) -- **OCR now succeeds on the whole document**
(138 pages, ~205,000 characters, confirmed via page-separator count).

- **Structural fields are legible; handwritten numeric fields
  mostly are not.** The document is a repeating ~2-page-per-event
  U230 (Field Sampling & Monitoring Summary + Facility/Permit Info)
  pattern, 68 distinct "SAMPLING INFORMATION" pages found. The typed/
  stamped `Location sample taken` field reliably distinguishes three
  real sample-type groups across many repeat rounds: the five named
  outlets (Galena 1/2/3, SB2, SBHR -- SB3 not yet confirmed in the
  pages checked), several "From Monitoring well pump outlet" events,
  and several "Water discharged from residence" / "Water from
  external faucet of residence" events (real domestic-well samples) --
  confirming the user's own description of monitoring-well samples
  appearing later in the report. The specific well/residence name for
  each (on the paired Facility/Permit page) and the handwritten
  pH/S.Conductivity/Temperature values were NOT reliably recovered by
  automated OCR (e.g. "pH: 7 -9@", "S. Conductivity :37 of") -- unlike
  the well-log driller's-report OCR work (Sessions 9-11), where the
  target fields are typed/stamped, not handwritten. A real, tolerant
  parser for this document (mirroring `parse_well_log_pdf.R`'s
  multi-fallback approach) is a concrete, scoped next step, not
  attempted this session given OCR's demonstrated unreliability on
  the numeric fields specifically.
- **One real event added directly from the two page-images the user
  supplied** (read directly, not via the noisy OCR of the same page):
  SB2 Outlet, 2025-08-04 14:20, sampler Bruce Wilkes, field pH = 7.56,
  temperature = 13.1 C, specific conductance = 3704 uS/cm (new
  `Field_Measurements` rows, new `Data_Sources` row distinguishing
  this bulk compiled document from the single TFT-report-specific
  U230 form added earlier this session). No accompanying lab
  chemistry exists for this date/tap, so this is a field-parameter-
  only sample (real, but not major-ion-complete).
- **SB2 Outlet's coordinate upgraded**: the same form gives a real,
  precise DMS coordinate for SB2 Outlet specifically (39 23'46.39"N,
  119 44'45.27"W) -- not a borrowed port centroid like the earlier
  `sampling_port_facility_centroid` approximation (~130-150 m away).
  Replaced, with the old value and reasoning kept in `notes` for
  context, `coordinate_source = 'ndep_u230_form'`,
  `coordinate_uncertainty_m = 15`.
- Applied to the real database (backed up first to
  `database/archive/geochem_operational_pre_u230_compiled_<timestamp>.sqlite`).
  Views rebuilt, QC re-run clean.
- **Not done**: no attempt to transcribe the other ~67 events (the
  remaining outlets, monitor wells, and domestic-well residences) --
  awaiting either more user-supplied images (the working pattern used
  for SB2 Outlet and the Galena 2 TFT sample) or a decision to invest
  in a real tolerant OCR parser for this specific form layout.

### Addendum: 2026 Table 2 (wellhead/flow re-observation), Galena 3 Outlet added, second P&A re-confirmation

User supplied the 2026-04-07 TFT Report's own Table 2 (same document
as the already-ingested 2026-04-07 Galena 2 injection composite,
`sample_id 1531`) plus a second compiled-U230 form pair, this time for
Galena 3 Outlet.

- **All 13 wells' `Wells.notes` got a second, appended entry** with
  the 2026-04-07 flow rate, enthalpy temperature, wellhead temperature,
  and wellhead pressure (per the user's explicit "account for pressure
  and flow too" instruction, mirrored from the 2025 table's own
  treatment) -- e.g. `24-5` flow dropped from 883.3 to 835 kph and
  wellhead temperature from 310 to 301.5 F between the two reports, a
  real, small production change now on record for both dates rather
  than only the most recent.
- **IW-3 and Cox I-1 re-confirmed P&A**: a second `Well_Work_Events`
  row (`event_date = '2026-04-07'`) was added for each -- a real,
  independently-dated re-observation of the same status, not a
  duplicate of the 2025-07-09 row, so the status history correctly
  shows P&A persisting across both reports rather than only being
  recorded once.
- **New real sample: Galena 3 Outlet, 2025-08-04 13:15** (from the
  compiled U230 document, same field-visit day as the already-added
  SB2 Outlet sample, different tap/time) -- field pH = 7.42,
  temperature = 13.5 C, specific conductance = 3705 uS/cm (the
  conductivity and temperature digits are the least legible of the
  three on the handwritten form; recorded as read, not independently
  verified against a second source the way SB2's values were not
  either).
- **Galena 3 Outlet's coordinate upgraded** the same way SB2 Outlet's
  was: a real, precise DMS coordinate from its own U230 form
  (39 23'04.32"N, 119 44'48.62"W) replaces the `Sampling_Ports`
  facility-centroid approximation -- **a ~498 m difference**, notably
  larger than SB2's ~140 m, flagged explicitly (not silently accepted)
  since it suggests the real G3 sample tap sits meaningfully off the
  G3 facility polygon's centroid, more so than at SB2/3's pad.
- Applied to the real database (backed up first to
  `database/archive/geochem_operational_pre_tft_table2_2026_<timestamp>.sqlite`).
  Views rebuilt, QC re-run clean.
- **Not done**: SB3, Galena 1, SBHR outlet U230 forms and the
  monitoring-well/residence pages from the compiled document remain
  unprocessed as of the previous paragraph -- SB3 Outlet is now done,
  see below.

### Addendum: SB3 Outlet added, same 2025-08-04 field-visit round

User supplied the SB3 Outlet U230 form pair from the same 2025-08-04
compiled-document field-visit round as SB2/Galena 3 Outlet, plus
confirmed Galena 3 Outlet's temperature reading (135 -> 13.5 C,
degrees with no unit letter specified on the form, following the same
Celsius convention already used for the other outlets this session).

- **New real sample: SB3 Outlet, 2025-08-04 14:10** -- field
  pH = 6.93, temperature = 13.5 C, specific conductance = 3825 uS/cm.
- **SB3 Outlet's coordinate upgraded** the same way SB2/Galena 3's
  were: a real, precise DMS coordinate from its own U230 form
  (39 23'36.92"N, 119 44'47.97"W) replaces the shared `SB2/3`
  Sampling_Ports facility-centroid approximation -- **~163 m away**,
  and now measurably different from SB2 Outlet's own (independently
  upgraded) coordinate, confirming these really are two distinct
  physical taps rather than two names sharing one point.
- Applied to the real database (backed up first to
  `database/archive/geochem_operational_pre_sb3_outlet_<timestamp>.sqlite`).
  Views rebuilt, QC re-run clean.
### Addendum: SBHR Outlet added, same 2025-08-04 field-visit round, large coordinate discrepancy flagged

User supplied the SBHR Outlet U230 form pair from the same 2025-08-04
field-visit round.

- **New real sample: SBHR Outlet, 2025-08-04 13:25** -- field
  pH = 6.67, temperature = 14.0 C, specific conductance = 362.6 uS/cm.
  **Flagged, recorded as read, not corrected**: this conductance is
  roughly 10x lower than the other three 2025-08-04 outlet readings
  (SB2/SB3/Galena 3 all ~3700-3825 uS/cm) -- plausibly a real
  operational difference at this specific outlet, or a handwriting/
  transcription artifact (e.g. a misplaced decimal), but not silently
  "corrected" to fit the pattern per this project's standing rule
  against guessing.
- **SBHR Outlet's coordinate upgraded**, same as the other three, to
  a real, precise DMS coordinate from its own U230 form
  (39 22'16.54"N, 119 45'59.97"W) -- but this one is **~1,248 m** from
  the previous SBHR-port-centroid approximation, far larger than SB2
  (~140 m), Galena 3 (~498 m), or SB3 (~163 m). Applied anyway (the
  form's own coordinate is the more authoritative, tap-specific
  source), but flagged explicitly in `Locations.notes` as worth a
  manual sanity check (e.g. satellite imagery) rather than assumed
  correct without question.
- Applied to the real database (backed up first to
  `database/archive/geochem_operational_pre_sbhr_outlet_<timestamp>.sqlite`).
  Views rebuilt, QC re-run clean. **Not yet committed to git**, per
  explicit user instruction to batch commits across this whole run of
  outlet-sample addenda rather than committing after each one.

### Addendum: Galena 1 Outlet added -- completes the 2025-08-04 five-outlet round; real low-conductivity pair confirmed

User supplied the Galena 1 Outlet U230 form pair from the same
2025-08-04 field-visit round, completing all five named outlets for
that date.

- **New real sample: Galena 1 Outlet, 2025-08-04 12:30** -- field
  pH = 7.09, temperature = 14.4 C, specific conductance = 365.7 uS/cm.
  No lat/long is given on this form's facility page (left blank) --
  Galena 1 Outlet's coordinate is unchanged (still the
  `Sampling_Ports` facility-centroid approximation from earlier this
  session).
- **Real, consistent pattern confirmed, not a one-off transcription
  error**: comparing all five outlets' 2025-08-04 conductivity
  together -- Galena 1 (365.7) and SBHR (362.6, flagged in the prior
  addendum) sit in a tight, mutually consistent ~360 uS/cm cluster,
  while SB2 (3704), SB3 (3825), and Galena 3 (3705) sit in a distinct
  ~3700-3825 uS/cm cluster. Two independently-transcribed forms
  landing within 3 uS/cm of each other is a real signal, not
  coincidence -- worth investigating further (e.g. whether Galena 1
  and SBHR are on a different, less-thermally-influenced flow path
  than the other three ports on this date) rather than treating either
  reading as suspect.
- Applied to the real database (backed up first to
  `database/archive/geochem_operational_pre_galena1_outlet_<timestamp>.sqlite`).
  Views rebuilt, QC re-run clean.
- **Not yet committed to git**, per the same explicit batching
  instruction as the prior three addenda -- this completes the full
  five-outlet 2025-08-04 round, a natural point to commit all of these
  addenda together if the user is ready.

- **Not done**: the monitoring-well/residence pages from the compiled
  document remain unprocessed, per the same OCR-unreliability caveat
  as the prior addenda.

### Addendum: Galena 2 Outlet added -- a much larger (~2.8 km) coordinate discrepancy flagged, NOT confidently resolved

User supplied the Galena 2 Outlet U230 form pair, same
"compiled U230" document. Exact date/time were not visible in the
provided crop (only the facility-info and field-measurements pages
were shown, not the sampling-info header) -- inferred as the same
2025-08-04 round by form layout/sampler pattern, flagged as inferred
rather than directly read, unlike the other five outlets this session.

- **New real sample: Galena 2 Outlet** -- field pH = 6.97,
  temperature = 14.1 C, specific conductance = 289.4 uS/cm (the
  lowest of all six outlets' 2025-08-04 readings, extending -- not
  breaking -- the low-conductivity cluster already flagged for
  Galena 1/SBHR).
- **Coordinate change applied but explicitly NOT trusted the way the
  other five were.** This form's own coordinate (39 23'49.34"N,
  119 45'11.79"W) is **~2,822 m** from the previous Galena-2-port-
  centroid approximation -- more than double the next-largest gap
  found this session (SBHR, ~1,248 m) and an order of magnitude beyond
  SB2/SB3/Galena 3's 140-500 m gaps. Applied per this session's
  standing "the form is the more authoritative source" policy, but
  recorded in `Locations.notes` as the single most suspect coordinate
  change made this session -- a transcription error on this specific
  handwritten form, or an error in the underlying Galena 2
  facility-polygon digitization, are both real possibilities. The
  outlet is described on its own form as "in pipeline 10 feet from
  wellhead," i.e. it should sit very close to the Galena 2 plant, which
  makes a multi-km discrepancy harder to explain than the smaller gaps
  already accepted for the other outlets. **Recommend checking this
  one directly against satellite imagery before relying on it.**
- Applied to the real database (backed up first to
  `database/archive/geochem_operational_pre_galena2_outlet_<timestamp>.sqlite`).
  Views rebuilt, QC re-run clean. Still not committed to git, per the
  same batching instruction.

### Addendum: first real "monitoring well" sample from the compiled U230 document -- Soccer Field, real Cl cross-check confirms plausibility

User supplied the first non-outlet event from the compiled document:
a "From Monitoring well pump outlet" page pair for **Soccer Field
Monitoring Well** (already a known `Locations` row, `location_id 154`,
resolved via NBMG exact-name match in Session 3-6 -- this is the same
real location, not a new one).

- **New real sample: 2025-08-27 09:15**, sampler Alex Benitez (SGS
  Laboratories - Reno), grab sample from pump discharge, 300 gallons
  purged -- field pH = 6.61, temperature = 50.7 C, specific
  conductance = 2,262 uS/cm.
- **Two real notation ambiguities resolved by inference, flagged in
  `Field_Measurements.instrument` rather than silently assumed**: the
  form's conductivity reads "2.262us" -- interpreted as 2,262 uS/cm
  (a comma-as-thousands-separator style), not literally 2.262 uS/cm,
  since the latter is implausible for any real groundwater. The
  temperature (50.7) has no unit letter on the form; assumed Celsius
  for consistency with every other outlet reading this session.
- **Real cross-check, not just an assumption**: this location's two
  already-on-file 2024 chemistry samples show Cl = 570 and 470 mg/L --
  genuinely thermal-signature chloride, not background -- which
  independently supports a real 50.7 C reading being plausible rather
  than a units error, since this monitoring well already shows other
  evidence of real thermal influence.
- **Template artifact noted, not treated as meaningful**: the form's
  own "Non-well location: Plant Injection Outlet Pipe" text
  contradicts its own "Monitoring" location-type checkbox and real
  well-construction fields (400 ft total depth, steel casing) --
  almost certainly leftover boilerplate from the same template used
  for this session's plant-outlet forms, not describing this well.
  Real construction facts (400 ft total depth, steel casing, status
  "Inactive - Only used for sampling") appended to `Locations.notes`
  regardless, since they're genuinely new information.
- No coordinate given on this form (field left blank) -- Soccer
  Field's existing NBMG-sourced coordinate is unchanged.
- Applied to the real database (backed up first to
  `database/archive/geochem_operational_pre_soccerfield_monitor_<timestamp>.sqlite`).
  Views rebuilt, QC re-run clean. Still not committed to git.

### Addendum: Herz Domestic Well added -- confirms unit conventions, real time-of-day tracking, real water-level decline

User asked directly whether sample TIME (not just date) was being
captured, specifically to support later shallow-well diurnal/time-of-
day comparisons -- confirmed yes, every sample this session has a real
`collection_time`/`Sampling_Events.date` down to the minute (e.g.
Soccer Field 09:15, this well 09:45, same day), specifically for that
purpose.

- **New real sample: Herz Domestic Well, 2025-08-27 09:45** -- field
  pH = 6.91, temperature = 33.2 C, specific conductance = 1,037 uS/cm.
- **This form independently validates two unit-interpretation
  decisions made on the Soccer Field form just before it**: it
  explicitly labels temperature "33.2 deg C" (confirming the Celsius
  assumption used everywhere this session a form omitted units), and
  writes conductivity as "1.037us" -- the same decimal-as-thousands-
  separator style as Soccer Field's "2.262us" -- read as 1,037 uS/cm,
  not 1.037 uS/cm.
- **Real water-level data**: last gauged 2025-06-27 (depth to water
  56.8 ft, sounding tape) and a new measured water level of 57.3 ft on
  this 2025-08-27 sample date -- a real ~0.5 ft decline over two
  months. No `Wells` row exists for this `Locations`-only well (same
  situation as Soccer Field Monitoring Well), so this water-level
  history is recorded in `Locations.notes` rather than
  `Water_Level_Observations` (which requires a `well_id` FK).
- Applied to the real database (backed up first to
  `database/archive/geochem_operational_pre_herzdom_<timestamp>.sqlite`).
### Addendum: Eich Well sample added, Soccer Field/Herz Domestic given real Wells rows, a real historical cross-check found

User supplied Eich Well's U230 form pair (same 2025-08-27 monitoring-
well round as Soccer Field/Herz Dom), plus asked to give Soccer Field
"a well id" and its water-level observation "(it is a well)."

- **New real sample: Eich Well, 2025-08-27 10:05** -- field pH = 7.12,
  temperature = 33 C, specific conductance = 1,733 uS/cm (form reads
  plain "1.733," no "us" suffix this time -- same thousands-separator
  convention as Soccer Field/Herz Dom, applied for consistency).
- **Soccer Field Monitoring Well given a real, genuinely NEW Wells
  row** (`well_id 267`, `well_role='monitor'`, `total_depth=400` ft,
  linked to `location_id 154`) -- confirmed via a direct pre-check
  that no Wells row existed for it before. Its own U230 form's Water
  Level section is entirely N/A, so there is no real number to give it
  yet -- stated plainly rather than fabricated.
- **Real finding while attempting the same for Herz Domestic Well**:
  it already had a Wells row (`well_id 210`), silently linked to
  `Locations 156` since the Skalbeck (2001) Table 1 ingestion --
  confirmed by a pre-insert check that correctly skipped creating a
  duplicate. Its existing `total_depth` (34, in meters) converts to
  111.5 ft, matching the new U230 form's independently-reported 110 ft
  total depth to within 1% -- a genuine cross-validation between two
  unrelated sources, left as-is rather than overwritten. Two new real
  water-level readings (2025-06-27: 56.8 ft; 2025-08-27: 57.3 ft,
  sounding tape) added to `Water_Level_Observations` alongside the
  pre-existing 1985-1988 Skalbeck readings (in meters, magnitudes
  7-12 vs. 56-57 ft, making the unit difference self-evident rather
  than silently mixed).
- Applied to the real database (backed up first to
  `database/archive/geochem_operational_pre_eich_soccerfield_herz_wells_<timestamp>.sqlite`).
  Views rebuilt, QC re-run clean. Still not committed to git.

### Addendum: NDOT resolved as a real well record (still no coordinate) -- notably warm reading flagged

User supplied NDOT's U230 form pair, same 2025-08-27 monitoring-well
round. NDOT has been a standing, multi-session unresolved identity
(flagged since Session 4, a real NDWR log candidate rejected in
Session 33 as being 2.2-4.4 km from the expected cluster) -- this
form gives real construction/status/chemistry data but, like every
other NDOT lead so far, no coordinate.

- **New Locations row (`location_id 246`, coordinate-less/
  provisional) and new Wells row (`well_id 268`, `well_role='monitor'`,
  total_depth 100 ft, diameter 4 in, steel casing)** -- registered per
  this session's Soccer Field precedent ("it is a well," give it a
  real Wells row) rather than left entirely stranded, since a real
  form now documents it. The long-standing coordinate gap is
  unchanged: this form's own Well Location field is blank, so nothing
  here helps resolve it.
- **New real sample: 2025-08-27 10:05** -- field pH = 7.21,
  temperature = 74.4 C, specific conductance = 3,130 uS/cm.
  **Flagged**: 74.4 C is notably warmer than every other monitoring-
  well reading this session (Herz Dom 33.2, Eich 33.0, Soccer Field
  50.7) -- a real, worth-noting finding (possibly indicating more
  direct thermal influence at this location than the others), not
  treated as an error.
- **Real coincidence checked, not a duplicate**: this sample shares
  the identical recorded time (10:05) with the same day's Eich Well
  sample -- confirmed every other field (pH, conductivity,
  temperature, purge volume, collection method) is genuinely
  different, so this is a real, distinct sample.
- Two real water-level readings (2025-06-27: 55.0 ft; 2025-08-27:
  56.6 ft, sounding tape) added to `Water_Level_Observations`.
- Applied to the real database (backed up first to
  `database/archive/geochem_operational_pre_ndot_<timestamp>.sqlite`).
  Views rebuilt, QC re-run clean. Still not committed to git.

### Addendum: Boyd Domestic Well added, same 2025-08-27 field-visit round, real low-conductivity pair confirmed

User supplied the Boyd Domestic Well U230 form pair from the same
2025-08-27 field-visit round as Soccer Field/Herz Dom/Eich/NDOT.

- **New real sample: 2025-08-27 10:50** -- field pH = 7.76,
  temperature = 24.2 C, specific conductance = 568 uS/cm. No lat/long
  is given on this form (left blank) -- Boyd Domestic Well's existing
  NBMG-sourced coordinate is unchanged.
- No real water-level number exists on this form (water-level section
  reads "Domestic water sourced from residential home") -- consistent
  with this being a residential tap rather than a monitoring well,
  not a data gap.
- Applied to the real database (backed up first to
  `database/archive/geochem_operational_pre_boyd_domestic_<timestamp>.sqlite`).
  Views rebuilt, QC re-run clean. Still not committed to git.

### Addendum: Jeppson Domestic Well sample added, same 2025-08-27 round

User supplied Jeppson Domestic's U230 form pair, same 2025-08-27
field-visit round as Soccer Field/Herz Dom/Eich/NDOT/Boyd Domestic.
The form itself calls this well "Jeppson Domestic," matching this
project's existing "Jeppson Geothermal Well" Location by the same
station-name mapping already on file (`staged_ndep_location_map.csv`).

- **New real sample: 2025-08-27 11:05** -- field pH = 7.17,
  temperature = 26.4 C, specific conductance = 460 uS/cm. Purge volume
  recorded in minutes (10 minutes), not gallons, unlike every other
  domestic-well form this session -- recorded as given.
- No coordinate or real water-level number on this form (residential
  tap, not a monitoring well) -- existing coordinate unchanged.
- Applied to the real database (backed up first to
  `database/archive/geochem_operational_pre_jeppson_domestic_<timestamp>.sqlite`).
  Views rebuilt, QC re-run clean. Still not committed to git.

### Addendum: Rogers Domestic Well added -- completes the 2025-08-27 monitoring/domestic-well round on file so far

User supplied Rogers Domestic's U230 form pair, same 2025-08-27
field-visit round as Soccer Field/Herz Dom/Eich/NDOT/Boyd/Jeppson.

- **New real sample: 2025-08-27 11:05** -- specific conductance =
  482 uS/cm only. This form's own pH and Temperature fields are both
  genuinely "N/A" -- not recorded on the form at all, not a parsing
  gap -- so only conductivity was added.
- No coordinate or water-level number given (residential tap, not a
  monitoring well) -- existing coordinate unchanged.
- Applied to the real database (backed up first to
  `database/archive/geochem_operational_pre_rogers_domestic_<timestamp>.sqlite`).
  Views rebuilt, QC re-run clean. Still not committed to git.

### Addendum: two new injection-side samples (2025-09-30), Galena 1 given a new location, Galena 2 attached to its existing TFT injection location

User supplied two new U230 form pairs, a later round (2025-09-30) than
the 08/04/25 outlet-sampling round, this time describing the
injection side "inside plant" rather than the plant discharge
outlets.

- **Galena 1**: no pre-existing injection-side location existed (only
  "Galena 1 Outlet," the discharge tap sampled 2025-08-04), so a new
  Location was registered -- `Galena 1 Injection Outlet`
  (`location_id 247`, `NDEP_U230_Galena1_Injection`), anchored to the
  Galena 1 `Sampling_Ports` facility centroid (no coordinate on this
  form). New sample, 2025-09-30 16:15: pH 6.24, temperature 43.4 C
  (converted from the form's own 110.2 F -- the first Fahrenheit
  reading this session, everything else so far was Celsius),
  conductivity 3,551 uS/cm.
- **Galena 2**: correctly recognized as the SAME physical point as the
  already-registered `Galena 2 Injection Composite (TFT)`
  (`location_id 245`, from the WETLAB Appendix D reports) -- both
  describe "injection...inside plant"/"downstream of HX in Plant." A
  third real sample was added to that existing location rather than
  creating a duplicate: 2025-09-30 08:30, pH 5.91, temperature 38.3 C
  (converted from 101 F), conductivity 3,300 uS/cm.
- Applied to the real database (backed up first to
  `database/archive/geochem_operational_pre_galena1_injection_<timestamp>.sqlite`
  and `..._pre_galena2_injection2_<timestamp>.sqlite`). Views rebuilt,
  QC re-run clean. Still not committed to git.

### Addendum: Galena 3 and SB2 injection-outlet samples added, same 2025-09-30 injection-side round

User supplied U230 form pairs for Galena 3 and SB2's injection side
(same round as Galena 1/2's injection samples above). Neither had a
pre-existing injection-side location (Galena 2 was the only one with
one, from the WETLAB reports), so two new Locations were registered,
same pattern as Galena 1 Injection Outlet: anchored to their
respective Sampling_Ports facility centroids (no coordinate given on
either form).

- **Galena 3 Injection Outlet** (`location_id 248`,
  `NDEP_U230_Galena3_Injection`) -- 2025-09-30 15:55: pH 6.12,
  temperature 37.2 C (converted from the form's 99 F), conductivity
  3,500 uS/cm.
- **SB2 Injection Outlet** (`location_id 249`, `NDEP_U230_SB2_Injection`)
  -- 2025-09-30 16:48: pH 6.32, temperature 22.8 C (converted from
  73 F), conductivity 3,420 uS/cm. Distinct from "SB2 Outlet" (the
  discharge tap sampled 2025-08-04).
- Applied to the real database (backed up first to
  `database/archive/geochem_operational_pre_galena3_injection_<timestamp>.sqlite`
  and `..._pre_sb2_injection_<timestamp>.sqlite`). Views rebuilt, QC
  re-run clean. Still not committed to git.

### Addendum: SB3 injection-outlet sample added, completes the 2025-09-30 injection-side round

User supplied the SB3 Outlet U230 form pair's injection side, same
2025-09-30 round as Galena 1/2/3 and SB2's injection samples above.

- **SB3 Injection Outlet** (`location_id 250`, `NDEP_U230_SB3_Injection`,
  new -- no pre-existing injection-side location for SB3, same as
  SB2/Galena 1/3) -- 2025-09-30 17:15: pH 6.06, temperature 39.4 C
  (converted from 103 F), conductivity 3,524 uS/cm. Distinct from "SB3
  Outlet" (the discharge tap sampled 2025-08-04).
- Applied to the real database (backed up first to
  `database/archive/geochem_operational_pre_sb3_injection_<timestamp>.sqlite`).
  Views rebuilt, QC re-run clean. Still not committed to git.

### Addendum: SBHR injection-outlet sample added, same 2025-09-30 injection-side round, large coordinate discrepancy flagged

User supplied the SBHR Outlet U230 form pair's injection side (same
2025-09-30 round as Galena 1/2/3 and SB2/SB3's injection samples
above) -- completing the full five-port injection-side set matching
the 2025-08-04 outlet round.

- **SBHR Injection Outlet** (`location_id 251`,
  `NDEP_U230_SBHR_Injection`, new -- no pre-existing injection-side
  location for SBHR) -- 2025-09-30 09:00: pH 5.98, temperature 38.9 C
  (converted from 102.1 F), conductivity 3,201 uS/cm. Distinct from
  "SBHR Outlet" (the discharge tap sampled 2025-08-04, which itself
  was already flagged with an unusually large ~1,248 m coordinate
  discrepancy).
- Applied to the real database (backed up first to
  `database/archive/geochem_operational_pre_sbhr_injection_<timestamp>.sqlite`).
  Views rebuilt, QC re-run clean. Still not committed to git.

### Addendum: IW-3/Cox I-1 marked Plugged & Abandoned from the 2025 TFT Report's Table 2

User supplied the same 2025 TFT Report Technical Memorandum's Table 2
("Well Summary During Tracer Flow Testing", tracer test date
2025-07-09) as a clean image, covering 24-5 (production) and 12
injection wells (IW-1 through IW-6, 23-33, 64A-32, 43-33, 21-32,
42A-32, Cox-1). Cross-referenced against `Wells`/`Well_Aliases`:

- **IW-3 (well_id 103) and Cox I-1 (well_id 190, alias `COX-1`)** are
  listed "P&A" (0 flow, 0 wellhead temperature/pressure, not tested) --
  added a real `Well_Work_Events` row for each (`work_type =
  'abandonment'`, `event_date = '2025-07-09'`, `source_document_id`
  NULL since this is an NDEP PRR document, not a `Well_Log_Documents`
  driller's report -- provenance instead recorded in `notes`). Cox I-1
  now correctly shows `display_status = 'plugged_abandoned'` in
  `vw_wells_gis`; IW-3 does not yet (no coordinate on file for it at
  all, so it's outside `vw_wells_gis`'s coordinate-having filter --
  the event itself is recorded and will surface the moment IW-3 gets a
  real coordinate).
- **IW-2 is "Idle"**, a real, different status from P&A -- not
  recorded as a `Well_Work_Events` abandonment (would misrepresent it),
  captured only in its `Wells.notes` entry below.
- **All 13 wells** (including the 11 "Online"/"Normal" ones) got a
  real, appended (never overwritten) `Wells.notes` entry transcribing
  this table's own status/flow-rate/enthalpy-temperature/wellhead-
  temperature/wellhead-pressure/comments for each -- so the table's
  real data isn't only captured for the two P&A wells.
- Applied directly to the real database (backed up first to
  `database/archive/geochem_operational_pre_tft_table2_<timestamp>.sqlite`).
  GIS views/GeoPackage re-exported (`well_work_events` layer 42 -> 43
  rows -- only Cox I-1's new event is currently mappable, per the
  coordinate gap above); QC re-run clean. No git-trackable file
  changed (this was a direct, documented database update, not a new
  script/CSV), so nothing new to commit for this addendum.

This session's file changes are not
  yet committed/pushed to git.

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
