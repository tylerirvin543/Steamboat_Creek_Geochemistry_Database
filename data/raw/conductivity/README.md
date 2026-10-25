# `data/raw/conductivity/` — Stream Conductivity Loggers (SBRR/SBGG)

## What this is

Two HOBO/Onset "Full Range" EC loggers deployed mid-July 2026 in
Steamboat Creek, supporting the thesis question of how frequently
chloride needs to be sampled to accurately estimate Cl flux from
continuous conductivity (see
`notebooks/01_conductivity_temporal_structure.qmd` for the full
methodology). Locations/roles (corrected 2026-09-05 after an initial
serial/location mix-up — see `AGENTS.md`):

- **SBRR** ("Rhodes Road", upstream control, co-located with USGS
  gauge 10349300) — serial `22575724`.
- **SBGG** ("Geiger Grade", downstream) — serial `22575725`.

## Files

- **`conductivity_logger_deployments.csv`** — human-maintained
  logger↔location↔serial↔role metadata (mirrors
  `data/raw/loggers/temperature_logger_deployments.csv`'s format).
  Edit this file to correct a deployment assignment or add a new
  logger; the ingest script never guesses this mapping.
- **`raw/Conductivity_Logger_1.csv`**, **`raw/Conductivity_logger_2.csv`**
  — raw HOBO/Onset exports (timestamp, raw EC, raw temperature). Place
  additional raw exports directly in `raw/` with a unique filename
  (e.g. date-suffixed) — `ingest_conductivity()`'s file-level dedup is
  keyed on basename, so a re-exported file reusing an existing name
  would be silently skipped rather than processed. Row-level dedup is
  independently keyed on `(logger_id, timestamp)`, so overlapping date
  ranges across files (e.g. a shuttle readout that re-exports the
  entire deployment history) are handled safely either way.

## Ingestion behavior

`scripts/ingest/ingest_conductivity.R` (`ingest_conductivity(con)`,
wired into `run_pipeline.R` as `RUN_INGEST$conductivity`) reads the
deployment CSV to resolve logger→location→role, parses each raw
export, computes specific conductance at 25°C (`sc_25c`) via
`scripts/ingest/helpers/compute_specific_conductance.R`'s temperature-
compensation formula, and inserts into `Conductivity_Observations`
(`database/schema/02_conductivity_schema.R`). Idempotent on
`(logger_id, timestamp)`.

## Known limitations

- Real lab chemistry (Cl and other majors) at SBRR/SBBV predates the
  logger deployment by ~2.5 months, so the sampling-frequency Cl-vs-SC
  statistical workflow (`scripts/analysis/sampling_frequency/`) still
  runs only against synthetic self-test data — as of 2026-10-24, zero
  real chloride samples overlap the logger deployment window at all,
  despite the record now extending through 2026-10-10. It will produce
  real results automatically once a chloride sample is collected
  during (or after) an active logger deployment window; no code change
  needed then.
- `SBGG` still has no paired chemistry at all.
- **Both loggers show a real, recurring retrieval/relaunch ambient-air
  exposure artifact** at every shuttle download: specific conductance
  crashes from the normal in-stream value toward near-zero in the
  minutes immediately around the physical retrieval/relaunch event
  (the logger briefly reads air, not stream water), confirmed at both
  the 2026-08-22 and 2026-10-10 downloads. These rows are flagged
  `qc_flag='field_visit_disturbance'` in `Conductivity_Observations`,
  detected automatically by a general retrieval-boundary detector in
  `scripts/qc/qc_conductivity_checks.R` (not a manual, per-download
  check) — any future download gets this flagged the same way with no
  further action needed.
- Current record: both loggers run continuously from 2026-07-15
  through 2026-10-10.
