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
