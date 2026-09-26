# `data/raw/airpressure/` — Barometric Pressure (Reno Airport, IEM ASOS)

## What this is

Hourly mean sea-level pressure (MSLP) at Reno-Tahoe International Airport
(ASOS station identifier **RNO**), pulled from the **Iowa Environmental
Mesonet (IEM)** ASOS archive:

<https://mesonet.agron.iastate.edu/request/download.phtml?network=NV_ASOS>

This is a different NOAA-network product than the daily-summary
temperature/precipitation data already ingested from Reno Airport
(`ingest_noaa_weather.R`, source `USW00023185` via NOAA/NCEI's GHCN
Daily product) — GHCN Daily does not carry any pressure element at
all. IEM's ASOS archive is the same underlying ASOS instrument record
NOAA's Local Climatological Data (LCD) product is built from, but is
free to bulk-download directly with no order/request step, which is
why it was used here instead of LCD.

Barometric pressure is needed for a real (non-synthetic) **barometric
efficiency** calculation for spring/well water levels (Sorey & Colvard
1992's method — linear regression of water level against barometric
pressure — was documented as a ready-to-run-but-unblocked stub in
`notebooks/07_historical_context_sorey1992.qmd` starting 2026-09-12,
specifically because no barometric-pressure parameter existed in this
database at all before this data was added). See
`scripts/analysis/barometric_efficiency.R` for the real calculation
built against this data.

## How to (re-)download more data

1. Go to <https://mesonet.agron.iastate.edu/request/download.phtml?network=NV_ASOS>
2. Select station **RNO** (Reno Tahoe Intl).
3. Select the date range you want (this project's first pull covers
   2025-01-01 through the download date).
4. Under "Which types of data to include", make sure **sea level
   pressure** is checked (the exported column is `mslp`, in
   hectopascals).
5. Download format: comma-delimited (CSV), one row per METAR
   observation (roughly hourly).
6. Save the resulting file anywhere under this folder, in its own
   dated subfolder if you like (see the existing
   `data_09_25_mesonet.agron.iastate/` example) — the ingest script
   scans this whole directory tree recursively and auto-detects any
   file whose header contains `station`, `valid`, and `mslp` columns,
   so the exact filename/subfolder doesn't matter.

## File format (as downloaded, unmodified)

```
station,valid,lon,lat,elevation,mslp
RNO,1/1/2025 0:55,-119.7711,39.4839,1345,1021.7
RNO,1/1/2025 1:55,-119.7711,39.4839,1345,1021.5
...
```

| Column      | Meaning                                                        |
|-------------|-----------------------------------------------------------------|
| `station`   | ASOS station identifier (`RNO`)                                 |
| `valid`     | Local observation time, `M/D/YYYY H:MM` (no leading zeros)      |
| `lon`/`lat` | IEM's own coordinate for the ASOS sensor (see note below)       |
| `elevation` | Station elevation, meters                                       |
| `mslp`      | Mean sea-level pressure, **hectopascals (hPa)**                  |

Files are ingested **as downloaded** — this project's standing
"raw data is never modified" rule — including the raw column names
and units; unit/format handling happens entirely inside the ingest
script.

## Where it lands in the database

`scripts/ingest/ingest_barometric_pressure.R` writes into the
*existing* `Weather_Observations` / `Weather_Stations` tables
(`database/schema/03_weather_schema.R`), **not** a new table — this
project's `Weather_Observations` is already a generic long-format
table (`station_id`, `date`, `parameter`, `value`, `unit`) designed so
a new variable at an already-known station is just a new `parameter`
value, not a schema change.

- `station_id` is deliberately set to **`USW00023185`** — the same
  station_id already used for Reno Airport's GHCN daily
  temperature/precipitation data — so pressure joins to those series
  by `station_id` with no extra mapping step. (IEM's own reported
  ASOS coordinate, 39.4839/-119.7711, is ~2.6 km from the coordinate
  already on file for that station; both are real reference points on
  or near the same airport, not two different stations — the existing
  `Weather_Stations` coordinate is left untouched, per this project's
  "never overwrite an existing field" convention, and the discrepancy
  is only logged to the console.)
- `parameter = "MSLP"`, `unit = "hPa"`.
- `date` stores the **full hourly timestamp** (`YYYY-MM-DD HH:MM:SS`),
  not just a calendar date — `Weather_Observations`'s primary key is
  `(station_id, date, parameter)`, and a `TEXT` column with a full
  timestamp in it satisfies that constraint fine for an hourly series;
  this is a deliberate reuse of a table originally designed around
  daily data, not a new date convention.

## Ingesting

```r
source("scripts/ingest/ingest_barometric_pressure.R")
ingest_barometric_pressure(con)   # base_dir defaults to "data/raw/airpressure"
```

Wired into `run_pipeline.R` as `RUN_INGEST$barometric_pressure`
(`TRUE` in ingestion profiles 1/2). Idempotent: a `Weather_Files_Processed`
log (the same table `ingest_noaa_weather.R` already writes to) and an
`anti_join` against existing `(station_id, date, parameter)` rows mean
re-running after adding a new download only ingests the new rows.

## Known limitations

- Single station only (RNO) — no spatial interpolation is meaningful
  or attempted; this is one regional atmospheric-pressure time series
  used as a covariate against water-level records, not a spatially
  varying field.
- ASOS reporting is roughly hourly but not perfectly regular (gaps
  during outages, occasional sub-hourly SPECI reports) — not resampled
  to a strict hourly grid at ingest time; anything doing a regression
  against water-level timestamps (`barometric_efficiency.R`) matches
  or interpolates at use time instead.
- Mean sea-level pressure (`mslp`), not raw station pressure — this is
  the standard, elevation-corrected value most weather products report
  and is what Sorey & Colvard's own method used (Reno Airport
  barometric pressure); if a future need specifically wants
  station-level (uncorrected) pressure, that would need re-requesting
  the IEM export with the station-pressure column also checked, which
  is not currently included in this project's downloaded files.
