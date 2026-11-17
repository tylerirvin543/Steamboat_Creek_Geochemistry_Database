# `data/raw/noaa/` — NOAA Weather (Precipitation, Air Temperature)

## What this is

NOAA weather exports for stations near Steamboat (primarily Reno
Airport, `USW00023185`), used for the data-availability record and as
a covariate for recharge/temperature-logger cross-checks. **Not**
barometric pressure — see `data/raw/airpressure/` for that (a
different NOAA-family product, IEM ASOS, ingested by a separate
script).

## Files (any filename works — format is auto-detected from content)

- `4360800.csv`, `Galena_Avg_temp_data_5_17_26.csv`,
  `US1NVWH0201_precipitation_data_5_17_26.csv` — each auto-classified
  by `scripts/ingest/ingest_noaa_weather.R` into one of two known
  formats:
  - **`search_tool`** — NCEI Search Tool order export (metric units,
    per-value quality flags), detected by a `"STATION"`-quoted first
    line.
  - **`ghcn_daily_summary`** — NOAA "Daily Summaries" web export
    (°F/inches), detected by a quoted `"NAME, ST US (STATION_ID)"`
    header line.

## Ingestion behavior

Long-format `Weather_Observations` (`station_id`, `date`, `parameter`,
`value`, `unit`) so a third format is just a new parser function, not
a schema change (`vw_weather_metric` in `create_analysis_views.R`
handles unit normalization downstream, not the ingest step itself).
Idempotent via `Weather_Files_Processed` + an anti_join on
`(station_id, date, parameter)`. Wired into `run_pipeline.R` as
`RUN_INGEST$noaa_weather`.

## Known limitations

- Values are stored **as reported** — one format is °F/inches, the
  other °C/mm — with `unit` carried per row; always query
  `vw_weather_metric` (or check `unit` explicitly) rather than
  assuming a consistent unit across all rows of `Weather_Observations`.

## Reno Airport daily precipitation (GHCN-Daily)

`reno_airport_USW00023185_PRCP_1938_2026.csv` (1938-01-01 to 2026-10-24) and
`reno_airport_USW00023185_PRCP_20261025_20261110.csv` (update, to 2026-11-10) come from the
NCEI Data Access service (no token needed). To extend the record, change `startDate` and `endDate`
in this query and save the result as a new file in this folder (the ingest detects the format and
skips rows already present):

https://www.ncei.noaa.gov/access/services/data/v1?dataset=daily-summaries&stations=USW00023185&dataTypes=PRCP&startDate=2026-10-25&endDate=2026-11-14&format=csv&units=metric&includeStationName=true&includeStationLocation=true&includeAttributes=true

The most recent days can be revised or missing for a few days after the date. Current record end: 2026-11-10.
