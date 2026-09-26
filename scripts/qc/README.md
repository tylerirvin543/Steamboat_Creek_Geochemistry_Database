# Quality Control (QC)

Non-destructive quality-control checks applied after data ingestion.

## What QC Does

- Identifies missing or invalid metadata
- Flags impossible or out-of-range measurements
- Detects duplicate or conflicting records
- Checks temporal integrity of sensor data
- Summarizes QC results in tables and reports

## What QC Does Not Do

- Does not modify raw data
- Does not delete database records
- Does not enforce modeling decisions

## Scripts

| Script | What it checks |
|---|---|
| `qc_data_integrity_checks.R` | `run_qc_checks(con)` -- the main entry point, called at the end of every `run_pipeline.R` run. Checks: missing field-measurement params, missing major ions, PHREEQC-flagged samples (incomplete input), `PHREEQC_Run_Failures` count, gradient-value distribution sanity, logger-observation coverage, logger outliers. Writes to `QC_Issues` (one row per issue, with `issue_type`/`severity`) and prints a console summary. |
| `qc_conductivity_checks.R` | Conductivity-logger-specific QC: gaps, spikes, and field-visit disturbance flags in `Conductivity_Observations`. Parses `Sampling_Events.date` per-value (tries serial/ISO/US-datetime formats in turn) since that column mixes formats across sources. |
| `qc_temperature_vs_air.R` | Cross-checks logged water/ground temperatures against NOAA air temperature for the same period -- flags physically implausible readings (e.g. a "spring" reading tracking ambient air too closely, suggesting a dry/exposed sensor). |
| `qc_well_log_matches.R` | `qc_well_log_matches(con)` -- for every unmatched, coordinate-having `Well_Log_Documents` row, writes the nearest existing `Wells`/`Locations` row + distance to `data/derived/well_log_match_candidates.csv` (a standing, regenerable report). Never auto-matches; each row gets a `recommendation` (download the reformatted NDWR scan / review as a close match / keep unresolved). |
| `audit_sample_duplicates.R` | Scans `Lab_Analyses`/`Samples` for duplicate `(sample_id, analyte, source_id)` combinations -- the check that caught the ~13x NDEP duplication bug (Session 4) and the SGS-promotion duplication bug (Session 16). |
| `create_qc_views.R` | Creates any SQL views the QC scripts themselves depend on (kept separate from `create_analysis_views.R` since these are QC-internal, not general-purpose). |
| `plot_qc_logger.R` | Quick diagnostic plot of a single logger's raw time series, for visually spot-checking a QC flag before deciding it's real. |
| `validate_database.R` | Ad hoc, broader database-validation helper (schema presence, row-count sanity) -- run manually, not part of the automated `run_qc_checks()` battery. |

## Outputs

- `QC_Issues` table (queryable; summarized by `issue_type` x `severity` in `pipeline_report.Rmd`)
- `data/derived/well_log_match_candidates.csv`, `data/derived/ndom_coordinate_discrepancies.csv`, `data/derived/well_coordinate_review.csv` (regenerable, disposable derived-QC output)
- Console output for immediate review during a pipeline run
