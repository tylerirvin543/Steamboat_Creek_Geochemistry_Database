# `data/raw/nbmg/` — NBMG Statewide Well Database

## What this is

Two overlapping (not identical) exports of the Nevada Bureau of Mines
& Geology's statewide geothermal-well compilation, used throughout
this project to resolve well coordinates by exact-name matching
against Dhakal-diagram/NDOM/NDWR well names.

## Files

- **`Geothermal_Wells.csv`** — the NBMG ArcGIS Open Data "Geothermal_Wells"
  layer, 2854 rows statewide. Source (cite wherever this data is used):
  <https://data-nbmg.opendata.arcgis.com/datasets/72341ba987e34c12a575c83f1d7c5367_0>
  — direct CSV export works at the same URL with `.../<id>.csv`.
- **`GEOTHERM06102019.csv`** — an earlier, separately-saved statewide
  well-log compilation (2238 wells), used before the ArcGIS layer
  above was found; still useful as a cross-check since the two sources
  occasionally disagree on a coordinate for the same well name (see
  `AGENTS.md`'s Session 6 "HA-4" note for a real example).

## How this is used

Not ingested wholesale into the database — instead, filtered (Washoe
County + a Steamboat-area bounding box) and matched by normalized well
name against wells needing a coordinate, one batch at a time, via
`scripts/ingest/register_well_coordinates.R` reading a small
per-batch CSV (e.g. `data/raw/wells/dhakal_well_coordinates.csv`) that
records exactly which NBMG record was matched, its `apino` permit ID,
and any rejected competing candidates — the match decisions are
version-controlled and reviewable, not just a live join against this
raw file.

## Known limitations

- NBMG sometimes reuses a generic/estimated coordinate for different
  wells (a real, confirmed case: `HA-4`'s NBMG coordinate is
  suspiciously identical to a coordinate previously seen for the
  unrelated "Harold Herz Geothermal Well 2") — always sanity-check a
  new NBMG match against a second source (NDWR, ArcGIS digitization)
  before trusting it at high confidence.
- Neither file is committed to git (large, statewide, and not this
  project's own data) — re-download from the ArcGIS Open Data URL
  above if missing after a fresh clone.
