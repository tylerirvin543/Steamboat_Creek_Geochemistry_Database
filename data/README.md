# `data/` — Data Pathways, Ingest Process, and Reproducibility

This is the top-level index for every raw, processed, and derived
dataset in this project. It exists so a new session (human or AI) can
answer "where did this number come from, and how do I reproduce it"
without re-deriving the whole pipeline from scratch.

## The Three-Layer Pattern

```
data/raw/        ->  scripts/ingest/*.R   ->   database/*.sqlite   ->  data/derived/, output/
(never edited)        (idempotent)             (the single source        (regenerable
                                                  of truth)                  outputs)
```

- **`data/raw/`** — exactly what was downloaded/received/scanned/
  exported, unmodified. Every subfolder below has its own README (or
  README.Rmd, an earlier-format equivalent — both are honored)
  describing its source, exact download/acquisition steps, file
  format, and which ingest script consumes it. **Never hand-edit a
  raw file** — if a raw file has a real error, fix it at the source
  (re-download, re-export) or handle the correction in the ingest
  script/a documented mapping CSV, not by editing the raw file in place.
- **`scripts/ingest/`** (not under `data/`, but the connective tissue)
  — one script per source, each idempotent (safe to re-run; only
  inserts genuinely new rows) and orchestrated by `scripts/run_pipeline.R`'s
  `RUN_INGEST` flags. See the root [README.md](../README.md)'s "Setup
  and Running the Pipeline" section for how to actually invoke these.
- **`database/geochem_operational.sqlite`** (or `geochem_demo.sqlite`
  in DEMO mode) — the single source of truth. Every downstream number
  (a notebook statistic, a website chart, a GeoPackage layer) traces
  back to a query against this database, not to a raw file directly.
- **`data/processed/`** — archived copies of raw inputs that follow an
  "ingest-then-wipe" pattern (see below) plus normalized intermediate
  files; effectively an ingest audit trail, not a place to look for
  "the real data."
- **`data/derived/`** — analysis-stage outputs (CSVs, QC reports,
  candidate-match tables) that a script regenerates from the database
  — safe to delete and re-run the relevant script, never hand-edited.

## Reproducibility Rules (apply project-wide)

1. **Raw data is never modified.** Corrections happen in the ingest
   script or in a small, version-controlled mapping/correction CSV
   (see "Manual Confirmation / Promotion Steps" in the root README),
   never by editing a file under `data/raw/` in place.
2. **Every ingest script is idempotent.** Re-running the full pipeline
   twice in a row should insert zero new rows the second time. If a
   script isn't idempotent, that's a bug — see the root README's
   Troubleshooting section for real examples of this being caught and
   fixed.
3. **Database changes affecting real (OPERATIONAL) data are backed up
   first**, to `database/archive/<name>_pre_<change>_<timestamp>.sqlite`,
   before any schema migration or risky re-ingest — see `database/archive/`
   for the running history of these.
4. **`data/raw/` is gitignored by default**, but small, hand-maintained
   CSVs that encode real provenance decisions (coordinate resolutions,
   location maps, deployment metadata) are the exception — those need
   `git add -f <path>` explicitly, since git won't evaluate a per-file
   exception inside an already-ignored directory. See the root
   README's "Version-Controlling New Raw-Data Files" section.
5. **A folder without a README below means it hasn't been documented
   yet, not that it's undocumentable** — if you add a new raw-data
   folder, add a README.md to it in the same style as its neighbors
   (source, download/acquisition steps, file format, which ingest
   script reads it, known limitations).

## `data/raw/` Subfolder Index

| Folder | Source | Ingest script | README |
|---|---|---|---|
| `field/` | Field sampling (Excel templates, the *only* approved data-entry interface) | `ingest_field.R` | [README.Rmd](raw/field/README.Rmd) |
| `lab/` | Laboratory chemistry (ICP-MS, general chemistry) | `ingest_lab.R` | [README.md](raw/lab/README.md) |
| `isotopes/` | Isotope analyses (δ18O/δD) | `ingest_isotopes.R` | [README.md](raw/isotopes/README.md) |
| `loggers/` | Elitech temperature-logger exports | `ingest_temperature_loggers.R` | [README.Rmd](raw/loggers/README.Rmd) |
| `conductivity/` | HOBO/Onset stream conductivity loggers (SBRR/SBGG) | `ingest_conductivity.R` | [README.md](raw/conductivity/README.md) |
| `airpressure/` | Reno Airport barometric pressure (IEM ASOS) | `ingest_barometric_pressure.R` | [README.md](raw/airpressure/README.md) |
| `earthquakes/` | USGS regional earthquake catalog | `ingest_earthquakes.R` | [README.md](raw/earthquakes/README.md) |
| `noaa/` | NOAA weather (precipitation, air temperature) | `ingest_noaa_weather.R` | [README.md](raw/noaa/README.md) |
| `usgs/` | USGS discharge, water level, historic SC, air temperature | `ingest_usgs.R`, `ingest_usgs_historic_chemistry.R` | [README.md](raw/usgs/README.md) |
| `ndep/` | Nevada DEP production-well chemistry (public record + PRR) | `ingest_ndep.R`, `ingest_ndep_prr.R` | [README.Rmd](raw/ndep/README.Rmd) |
| `ndwr/` | Nevada DWR well logs, water levels, spring/stream flow | `ingest_ndwr.R`, `ingest_well_logs.R`, `ingest_ndwr_stream_flow.R` | [README.Rmd](raw/ndwr/README.Rmd), [Ormat_well_logs/README.md](raw/ndwr/Ormat_well_logs/README.md) |
| `ndom/` | Nevada Division of Minerals well-permit records | `ingest_ndom_wells.R` | [README.md](raw/ndom/README.md) |
| `nbmg/` | Nevada Bureau of Mines & Geology statewide well database | (referenced by `register_well_coordinates.R`) | [README.md](raw/nbmg/README.md) |
| `wells/` | Hand-maintained well-network/coordinate/alias CSVs (Dhakal diagram, NBMG matches, ArcGIS digitization) | `register_well_network.R`, `register_well_coordinates.R` | [README.md](raw/wells/README.md) |
| `arcgis/` | User-digitized ArcGIS shapefiles (wells, power-plant polygons; faults, planned) | `register_facility_areas.R`, `ingest_fault_traces.R` | [README.md](raw/arcgis/README.md) |
| `historical/` | Digitized historical-literature chemistry (Sorey & Colvard 1992, Mariner & Janik 1995) | `ingest_historical_sorey1992.R`, `ingest_mariner_janik_1995.R` | [README.md](raw/historical/README.md) |
| `images/` | Field photos/video (EXIF GPS extraction) | `ingest_image_locations.R` | [README.md](raw/images/README.md) |
| `discharge/` | Stream-transect discharge/flux measurements | `ingest_flux.R` | [README.md](raw/discharge/README.md) |
| `phreeqc/` | User-editable mixing/inverse/gas-phase model configuration CSVs | `run_phreeqc_mixing_from_config()` etc. | [README.md](raw/phreeqc/README.md) |

## `data/processed/`

Archived, timestamped copies produced automatically by the
"ingest-then-wipe" pattern used for field/logger/flux/conductivity
Excel templates (`field_archive/`, `logger_archive/`, `flux_archive/`,
`conductivity_archive/`, each folder named by ingest timestamp) —
every successfully ingested template is copied here before its
working copy is wiped back to a header-only state, so no raw
submission is ever truly lost even though the "live" template file in
`data/raw/` looks empty between field trips. Also holds
`lab_normalized/`, `qc_exports/`, and `staging_snapshots/` (intermediate
normalized forms). **Nothing here should be treated as an authoritative
source** — the database is; these are an audit trail.

## `data/derived/`

Analysis-stage CSV outputs, each regenerated by a specific script —
if one looks stale or wrong, re-run the script that produces it rather
than hand-editing:

| File/folder | Produced by |
|---|---|
| `data_availability/` | `scripts/analysis/data_availability.R` |
| `sampling_frequency/` | `scripts/analysis/sampling_frequency/05_recommendation_report.R` |
| `well_log_match_candidates.csv` | `scripts/qc/qc_well_log_matches.R` |
| `ndom_coordinate_discrepancies.csv` | `scripts/ingest/ingest_ndom_wells.R` |
| `qc/` | `scripts/qc/qc_data_integrity_checks.R` |
| `phreeqc_inputs/`, `phreeqc_outputs/`, `inverse_models/` | `scripts/phreeqc/*.R` |
| `clustering/` | `scripts/analysis/cluster_hydrochemical_facies.R` (not currently written here automatically — see that script's own header) |
