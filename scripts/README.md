# scripts/ -- folder index

Top-level index. Each subfolder has its own README with a one-paragraph
description per script; this page is just the map.

| Folder | Role |
|---|---|
| [`ingest/`](ingest/README.md) | ETL: one script per external data source (USGS, NDEP, NDWR, NDOM, NOAA, field, lab, isotopes, loggers, well logs, earthquakes, fault traces, barometric pressure, photos, ...) plus the `register_*`/`promote_*` human-confirmation staging scripts and the GIS/GeoPackage exporters. The largest and most actively-growing folder in the project. |
| [`analysis/`](analysis/README.md) | Derived analysis: SQL views, gradients, isotope pairs, facies clustering, barometric efficiency/aquifer classification, data-availability reporting, the Cl-sampling-frequency sub-workstream. Runs after ingestion, never writes raw source data. |
| [`phreeqc/`](phreeqc/README.md) | PHREEQC geochemical modeling: speciation/saturation-index runs, real + synthetic-self-test mixing/inverse/gas-phase modes, gas geothermometry. |
| [`qc/`](qc/README.md) | Data-quality checks: integrity checks, conductivity-logger QC, temperature-vs-air-temperature checks, well-log match candidates, sample-duplicate auditing, ad hoc database validation. |
| [`leapfrog/`](leapfrog/README.md) | Exports well collar/survey/interval/lithology data into Leapfrog Geo's CSV input format for 3D geologic modeling. |
| [`templates/`](templates/README.md) | Standalone diagram generators and the blank flux-data-entry template -- none touch the database. |
| `documentation/` | Auto-generates plain-language table/column descriptions for the documentation website. |
| `templates/` (also holds) `pipeline_report_files/` | knitr's auto-generated figure-output folder for `pipeline_report.Rmd` -- not source, safe to ignore/regenerate. |

## Top-level scripts (not in a subfolder)

- **`run_pipeline.R`** -- the main orchestrator. Source it (optionally
  setting `MODE`/`RUN_INGEST`/`RUN_ANALYSIS`/`BUILD_WEBSITE` first) to
  run the full ETL + analysis + reporting pipeline end-to-end. See
  README.md's "Setup and Running the Pipeline" section for the exact
  console commands for every common workflow.
- **`pipeline_report.Rmd`** -- renders the "Pipeline QC & Status
  Report" (table row counts, QC issue summary, PHREEQC run failures,
  facies-clustering/aquifer-classification/well-network summaries).
  Called automatically at the end of a full `run_pipeline.R` run, or
  render it directly for a quick status check without re-running
  ingestion.

See also `database/schema/` (not under `scripts/`, but the natural
companion folder) for the numbered schema-migration files this project
runs.
