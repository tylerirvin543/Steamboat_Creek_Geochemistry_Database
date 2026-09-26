# `data/raw/earthquakes/` — Local Seismicity Catalog (USGS)

## What this is

A real earthquake catalog for the greater Reno/Washoe Valley/Lake
Tahoe region, pulled directly from the **USGS FDSN Event Web Service**
(`earthquake.usgs.gov/fdsnws/event/1/query`), used to check whether
nearby seismicity coincides with detectable anomalies in this
project's water-level, temperature, or barometric-pressure records.
Sorey & Colvard (1992) explicitly name earthquakes -- alongside
barometric pressure changes and precipitation -- as a real,
historically documented influence on spring/well water levels at this
site (see `notebooks/07_historical_context_sorey1992.qmd`), which is
the motivation for pulling this catalog.

## How to (re-)download more data

Query the FDSN Event Web Service directly (no account/key needed):

```
https://earthquake.usgs.gov/fdsnws/event/1/query?format=csv&starttime=2025-01-01&endtime=2026-09-25&minlatitude=38.8&maxlatitude=40.0&minlongitude=-120.3&maxlongitude=-119.2&minmagnitude=1.5
```

Adjust `starttime`/`endtime` to extend the window; the bounding box
(`minlatitude`/`maxlatitude`/`minlongitude`/`maxlongitude`) is a loose
box around the greater Reno-Washoe Valley-Lake Tahoe seismic region,
centered on but not restricted to Steamboat Hills itself (39.385 N /
-119.755 W), since regional fault-system activity at 10-50 km can
still be worth screening even if it's not literally under the field.
`minmagnitude=1.5` keeps the catalog to events large enough to be
reliably located by the regional network (`nn`/`nc`) without
overwhelming it with the much larger number of sub-M1 microseismicity
events. Full documentation of available query parameters:
<https://earthquake.usgs.gov/fdsnws/event/1/>

Save the resulting CSV anywhere under this folder — `ingest_earthquakes.R`
scans the whole directory tree and auto-detects any file with the FDSN
CSV column signature (`time`, `latitude`, `longitude`, `mag`, `place`,
`id`, ...), so filename/subfolder doesn't matter.

## File format (as downloaded, unmodified)

Standard USGS FDSN event CSV: `time, latitude, longitude, depth, mag,
magType, nst, gap, dmin, rms, net, id, updated, place, type,
horizontalError, depthError, magError, magNst, status, locationSource,
magSource`. Retrieved and saved **verbatim** (no reformatting) — this
project's standing "raw data is never modified" rule.

## Where it lands in the database

`scripts/ingest/ingest_earthquakes.R` writes into a new
`Earthquake_Events` table (`database/schema/12_earthquake_schema.R`),
computing each event's great-circle distance to the Steamboat Hills
field center (`dist_to_steamboat_km`) at ingest time so downstream
analysis doesn't have to repeat that calculation. Idempotent on the
USGS event `id` (globally unique and stable), so re-running after a
fresh download only inserts genuinely new events — a previously
`automatic`-status event that USGS later updates to `reviewed` (same
`id`) is intentionally **not** re-fetched/updated by this script; if
you want the latest revision, re-download and manually verify, since
re-running the ingest alone won't overwrite an existing row.

## Ingesting

```r
source("scripts/ingest/ingest_earthquakes.R")
ingest_earthquakes(con)   # csv_dir defaults to "data/raw/earthquakes"
```

Wired into `run_pipeline.R` as `RUN_INGEST$earthquakes` (`TRUE` in
profiles 1/2).

## Known limitations

- This is a **screening catalog**, not a rigorous seismological
  analysis: no completeness-magnitude analysis, no declustering, no
  focal-mechanism/stress-tensor data. It answers "did anything nearby
  happen around this date," not "what caused it."
- The 2025-01-01 to 2026-09-25 window was chosen to match this
  project's real overlapping barometric-pressure/water-level/
  temperature-logger records — extend the window if a longer
  historical comparison (e.g., against Sorey & Colvard's own 1988-1992
  observations) is ever wanted, but note the temperature-logger record
  itself only starts April 2026 regardless of how far back the
  earthquake catalog goes.
- `nn` (Nevada Seismological Laboratory) and `nc` (NCSN/Berkeley)
  network locations both appear in this box — location precision
  varies by network and by automatic-vs-reviewed status (see the
  `status`/`horizontalError` columns); treat sub-km distance
  differences between nearby events as not meaningfully distinguishable.
