# `data/raw/usgs/` — USGS Discharge, Water Level, Historic Chemistry, Air Temperature

## What this is

Multiple distinct USGS products, all for gauge 10349300 (Steamboat
Creek near Rhodes Road, co-located with the SBRR conductivity logger)
and related basin sites, feeding different tables/purposes.

## Subfolders

- **`input/`** — live discharge/water-level pulls (Monitoring Location
  Pages, `mlp_continuous_USGS-<site>_<daterange>/`), one folder per
  site+date-range export. Ingested by `scripts/ingest/ingest_usgs.R`
  into `USGS_Timeseries`/`USGS_Stations` (parameter `60` = discharge).
- **`air_temperature_data/`** — the same Monitoring Location Page
  format, but for parameter `00020` (air temperature) at gauge
  10349300. Ingested by the *same* `ingest_usgs()` function with a
  `base_dir` argument pointed here — no new ingest logic needed, since
  it's the same file format, just a different parameter code and
  folder.
- **`fullphyschem_station_download/fullphyschem.csv`** — historic USGS
  Water Quality Portal (WQP) grab-sample data, currently just Specific
  Conductance (param `00095`). Ingested by
  `scripts/ingest/ingest_usgs_historic_chemistry.R`, deliberately into
  the **same** `USGS_Timeseries`/`USGS_Stations` tables `ingest_usgs.R`
  uses for live discharge — so SC and discharge are a one-line join
  apart (`vw_sc_discharge_daily`).

## Ingestion behavior

`RUN_INGEST$usgs` (live discharge/air temp) and
`RUN_INGEST$usgs_historic_chem` (historic SC, default `FALSE` — opt-in)
both idempotent on `(station_id, date, parameter)`.

## Known limitations

- `input/desktop.ini` is a stray Windows folder-view artifact, not
  data — harmless, ignored by the ingest scan.
