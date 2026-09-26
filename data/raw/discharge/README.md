# `data/raw/discharge/` — Stream-Transect Discharge/Flux Measurements

## What this is

`stream_discharge.xlsx` — a manual stream-transect discharge/flux
measurement template (velocity/depth/width readings across a channel
cross-section, at named transects `transect_A`/`transect_B`/`transect_C`),
intended to support future mass-flux (chloride/heat) calculations
independent of the SBRR/SBBV chloride-mass-balance approach.

## File format

Three sheets (one per transect), each with columns including
`datetime`, `transect_id` (twice, per a source-spreadsheet quirk — see
below), `point_id`, velocity/depth measurements, `notes`, and a
sheet-repeating `sheet_name`.

**Known source-file defect, handled in the ingest script, not fixed
in the raw file**: each sheet has **two** columns both literally named
`transect_id` (readxl renames them `transect_id...3`/`transect_id...11`
on read). The first occurrence (right after `datetime`, before
`point_id`) is the real per-point transect identifier; the second
(right before `notes`) is a spreadsheet-authoring artifact that just
repeats the sheet name as a constant on every row — already redundant
with the `sheet_name` column the ingest script adds itself.
`ingest_flux.R` keeps only the first occurrence.

## Ingestion behavior

`scripts/ingest/ingest_flux.R` (`RUN_INGEST$flux`, `TRUE` in
chemistry-bearing profiles 1/2) drops fully-blank rows and exits
cleanly (0 rows) if a sheet is header-only — as of the last check, all
three transect sheets **are** header-only templates awaiting field
data entry, not populated data. The ingest runs cleanly today and will
start processing rows automatically the moment real transect
measurements are entered, no further code change needed.

## Known limitations

- No real transect data has been collected/entered yet — this folder
  currently documents a ready-but-unused ingestion path, not existing
  results.
