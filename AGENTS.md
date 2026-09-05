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

**Packages installed for this work** (were missing from the R library):
`lubridate`, `here`, `zoo`, `ranger`.

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
